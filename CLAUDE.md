# CLAUDE.md

このファイルは、Claude Code がこのリポジトリで作業する際のガイドです。

## プロジェクトの目的

オンプレミスの **Proxmox VE** 上に **Ubuntu の VM** を払い出し、
その上に **Kubernetes クラスタ** を立てるためのリポジトリです。

**本題は Kubernetes です。** OS はそのための土台であって、目的ではありません。
Kubernetes のバージョンアップ追従を速く安全に回すために、以下を最優先の設計方針とします。

- **クラスタは使い捨て**: 壊れたら直すのではなく、作り直す
- **「壊す」は常に 1 コマンドで完了すること**: 前提条件や後始末を持ち込まない。
  ここが重くなると、作り直すのが億劫になって目的そのものが崩れる
- **手作業を残さない**: VM に入って手で直した変更は、必ずコード側に還元する。
  コードに入っていない手作業は、次に作り直した瞬間に消える
- **バージョンは 1 箇所で切り替えられること**: Kubernetes のマイナーバージョン更新も
  Ubuntu のリリース更新も、変数 1 つの変更で済む状態を保つ
- **同じコードから同じクラスタが再現できること**: 「使い捨て」は再現性とセットで意味を持つ

## 現状

**Terraform への移行は完了していますが、まだ実 Proxmox で apply していません。**

```
terraform/               # VM 払い出し。ここが現行の実装
  versions.tf            # required_providers とバージョン固定
  providers.tf           # provider 設定（認証値は環境変数から）
  variables.tf           # ノード定義、k8s / Ubuntu バージョン、ネットワーク値
  images.tf              # download_file
  cloud-init.tf          # SSH 公開鍵の取得と snippets 生成
  vms.tf                 # VM 群
  outputs.tf             # 払い出された IP、apply 後の手順
  terraform.tfvars.example
  home-api.tf            # home-api (VMID 110)。既定では作成しない
cloud-init/
  k8s-node.yaml.tftpl    # k8s ノードの cloud-config テンプレート
  k8s-setup.sh.tftpl     # k8s ノード準備スクリプト（base64 で cloud-config に埋め込む）
  home-api.yaml.tftpl    # home-api の cloud-config テンプレート
  docker-setup.sh.tftpl  # home-api の Docker 導入スクリプト
manifests/               # クラスタに流し込む YAML (metallb, 動作確認用 nginx)
```

**旧 `qm` シェルスクリプト経路（`vm-setup/` `k8s-setup/`）は削除済みです。**
VM の払い出しは Terraform に一本化されています。

### Terraform に移行して何が変わったか

- **「壊す」が `terraform destroy` の 1 コマンドになった。** 以前は
  `qm shutdown` / `qm destroy` を VMID の数だけ手で並べていました
- **テンプレート VM（VMID 9000）を手で作る工程が消えた。** `disk` の `import_from` で
  クラウドイメージを直接取り込めるため、`qm create` → `importdisk` → `qm template` が不要です
- **ノード定義が位置依存のパースから解放された。** 以前の
  `"vmid vmname cpu mem ip ..."` というスペース区切り文字列 + `while read -r` は、
  カラムを 1 つ増やすだけで壊れました
- **state があるので、何が存在するかをコードが把握できる。** 以前は `qm list` を grep していました
- **cloud-init の中身が Terraform の管理下に入った。** 以前は VM の起動時に
  `raw.githubusercontent.com` から `k8s-setup/setup.sh` を curl しており、
  **`main` に push した瞬間に次に起動する全 VM の挙動が変わる**構造でした。
  現在は `templatefile()` で描画して base64 で埋め込むため、
  スクリプトの変更が `plan` の差分に現れます。**この方式を崩さないこと**

### 削除済みのファイル（記録・復活させないこと）

- `vm-setup/vm-setup-docker.sh` → `terraform/home-api.tf` + `cloud-init/home-api.yaml.tftpl` に移植
- `vm-setup/mv-setup-kubernetes.sh` → `terraform/vms.tf` + `cloud-init/k8s-node.yaml.tftpl` に移植
- `k8s-setup/setup.sh` → `cloud-init/k8s-setup.sh.tftpl` に移植

**旧経路のクラスタ（VMID 1001-1006）とテンプレート VM（9000）は Terraform の
管理外なので、`terraform destroy` では消えません。** 手で消す手順は README にあります。

## OS 選定の経緯（決定記録・蒸し返さないこと）

一時期 **RHEL 9 への移行**（Red Hat Developer Subscription / 16 ノード枠）を
別リポジトリ `goegoe0212/proxmox-rhel-kubernetes` で検討していましたが、
**運用のしやすさを優先して Ubuntu 継続に決定しました。** そのリポジトリは統合・廃止されます。

判断材料は次のとおりです。

- **k8s バージョン追従という主目的は、OS にほとんど依存しない。**
  バージョンアップで壊れるのはリポジトリ URL、CRI の設定形式、kubeadm の API 変更あたりで、
  これは Ubuntu でも RHEL でも同じように壊れて同じように直す。主目的では差がつかない
- **RHEL は「壊す」が重い。** `terraform destroy` はサブスクリプションを解放しないため、
  事前に全ノードで `subscription-manager unregister` が必要になる。
  6 ノード構成では 16 枠が **2 回の作り直しで尽きる**。
  しかも **ノードが壊れているときほど unregister の SSH が通らず**、枠だけ食って VM が消える。
  「一番壊したい場面で一番コストが上がる」構造で、このリポジトリの目的と正面から衝突する
- **SELinux / firewalld が純粋なコストになる。** RHEL 系で kubeadm を通すには SELinux を
  permissive にするのが定石だが、permissive にした時点で「本番同等の検証」という
  RHEL を選ぶ動機自体がかなり失われる
- **エコシステムの厚みが違う。** cloud-init は Canonical 製で Ubuntu が第一級のターゲット。
  kubeadm の公式ドキュメントもコミュニティ記事も大半が Debian/Ubuntu 前提
- **ユーザの本業は RHEL だが、自宅の運用とは切り離す方針。** RHEL 自体の学習は別途 VM を立てて行う

したがって **RHEL / Rocky / AlmaLinux への切り替え機構は作りません。** 使わない抽象化は複雑さだけを増やします。

## 技術スタック

### Terraform プロバイダ: `bpg/proxmox` を使う

Proxmox 向けには `Telmate/proxmox` と `bpg/proxmox` がありますが、**`bpg/proxmox` を使ってください。**
現在活発にメンテナンスされているのはこちらで、cloud-init やイメージ取得の扱いが素直です。

```hcl
terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      # 0.x なのでマイナーで破壊的変更が入りうる。パッチのみ許可する形で固定する
      # （"~> 0.111.1" は >= 0.111.1, < 0.112.0）。マイナーを上げるときは
      # CHANGELOG を読んでから手で変更すること。
      version = "~> 0.111.1"
    }
  }
}

provider "proxmox" {
  endpoint  = "https://192.168.20.3:8006/"
  api_token = "terraform@pve!provider=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}
```

### 認証と、SSH が必要になる理由

- 認証は **API トークン**を使う（`username` / `password` は使わない）
- 値はコードに書かず環境変数で渡す:
  `PROXMOX_VE_ENDPOINT` / `PROXMOX_VE_API_TOKEN`
- **ほとんどの操作は API だけで完結しますが、snippets（cloud-init の user-data）のアップロードは
  ノードへの SSH を必要とします。** そのため provider に `ssh` ブロックの設定が要ります
  （`agent = true` か `private_key`、`username`）。
  対応する環境変数は `PROXMOX_VE_SSH_USERNAME` / `PROXMOX_VE_SSH_AGENT` など
- **snippets はデータストアで既定では無効**です。Proxmox の
  Datacenter > Storage で対象データストア（`local`）の内容種別に snippets を追加しておく必要があります。
  これは Terraform の外側の前提条件なので README に書いてください

### 旧シェル処理との対応（記録）

| 削除した `qm` ベースの処理 | 置き換えた Terraform リソース |
|---|---|
| `wget` でクラウドイメージ取得 | `proxmox_virtual_environment_download_file` |
| `qm create` + `importdisk` + `qm template` でテンプレート作成 | **不要**（`disk` の `import_from` で直接取り込む） |
| `cat > /var/lib/vz/snippets/*.yaml` | `proxmox_virtual_environment_file`（`content_type = "snippets"`） |
| `qm clone` / `qm set` / `qm resize` / `qm start` | `proxmox_virtual_environment_vm` |
| `qm shutdown` + `qm destroy` | `terraform destroy` |
| `curl` でスクリプトを取ってきて実行 | `templatefile()` で cloud-init に埋め込む |

### イメージの取得

**Ubuntu 24.04 LTS（noble）を継続してください。** 動作実績があり、k8s 関連の情報も最も揃っています。

26.04 LTS（resolute）もリリース済みで kubeadm も動きますが、**先に新しい方へ乗り換えないこと。**
まず 24.04 で Terraform のパイプラインを通し、**その後 26.04 への更新を
「移行後の最初の仕事」として試す**のが筋の良い順序です。使い捨て環境を作る目的がそれです。

```hcl
resource "proxmox_virtual_environment_download_file" "ubuntu" {
  content_type = "iso"      # VM イメージは "iso" もしくは "import"
  datastore_id = "local"
  node_name    = "pve01"
  url          = "https://cloud-images.ubuntu.com/releases/noble/release/ubuntu-24.04-server-cloudimg-amd64.img"

  checksum           = "..."       # SHA256SUMS から取得して固定する
  checksum_algorithm = "sha256"
}
```

**`/<codename>/current/` は daily build なので使わないこと。**
同じ URL でも日によって中身が変わるため、「同じコードから同じクラスタを作り直す」が成立しません。
旧スクリプトはここを踏んでいました。現在は `/releases/<codename>/release-<date>/` で
日付まで固定し、`checksum` を付けてあります。

- **`checksum` を外さないこと。** イメージが差し替わったことに気づけなくなります
- **URL とチェックサムは必ずセットで更新すること。** 片方だけ変えると apply が落ちます
- URL・チェックサム・ファイル名はすべて変数化済み（`ubuntu_image_*`）
- `import_from` の ID 書式は **`<datastore_id>:import/<file_name>`**。
  リソース参照でもリテラル文字列でも構いません
- 圧縮イメージ（`.qcow2.xz` 等）は `import_from` では扱えません。その場合は
  `file_id`（書式は `<datastore_id>:<content_type>/<file_name>`）を使います

### VM 本体（公式ドキュメントの例を元にした骨格）

```hcl
resource "proxmox_virtual_environment_vm" "node" {
  node_name = "pve01"
  vm_id     = 1101

  cpu    { cores = 2 }
  memory { dedicated = 8192 }

  disk {
    datastore_id = "local-lvm"
    import_from  = proxmox_virtual_environment_download_file.ubuntu.id
    interface    = "scsi0"
    size         = 64
  }

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.20.40/24"
        gateway = "192.168.20.2"
      }
    }
    user_data_file_id = proxmox_virtual_environment_file.cloud_config.id
  }

  network_device { bridge = "vmbr1" }
  operating_system { type = "l26" }

  agent { enabled = true }   # 既定は false。IP 取得などに使うなら有効化し、
                             # ゲスト側に qemu-guest-agent を入れること
  stop_on_destroy = true     # destroy 時にシャットダウンを待たない。使い捨て用途では有用
}
```

cloud-init の user-data は `cloud-init/*.yaml.tftpl` を `templatefile()` で読む形にしてください。
ノードごとに内容が変わる（ホスト名、role）ので、テンプレート化が前提です。

### 既知の落とし穴

- **`.qcow2` 拡張子**: Proxmox 8.4 より前は `.qcow2` / `.raw` の拡張子を弾くことがあります。
  その場合は `.img` としてダウンロードする回避策を取ります
  （Ubuntu のクラウドイメージは元から `.img` なので通常は問題になりません）
- **`agent { enabled = true }` にしたのにゲストに qemu-guest-agent が入っていない**と、
  apply がタイムアウトするまで待たされます。cloud-init 側の `packages` に必ず含めること
- **`disk` の `size` を後から縮小できません**。Proxmox の制約であり Terraform でも同じです
- **`.tftpl` の中の `$` の扱い**: `templatefile()` ではドル記号 + 波括弧が
  Terraform の補間になります。**シェル変数を波括弧付きで書くと壊れます。**
  `cloud-init/*.sh.tftpl` は波括弧を付けない `$VAR` の形で統一してあるので、
  この方針を崩さないこと。波括弧が必要な場合は `$` を 2 つ重ねてエスケープします。
  **コメント内に書くときも同様に解釈される**ので、説明文でこの記法に触れるときは
  記号をそのまま書かず、文章で表現してください（テンプレート内にその例があります）
- **cloud-config の YAML はインデントに弱い**: 複数行を差し込むときは、
  テンプレート側で `for` ディレクティブを使うより、Terraform 側で整形済みの
  文字列を作って渡す方が安全です（`ssh_authorized_keys_yaml` がその形）。
  スクリプトの埋め込みは base64 (`encoding: b64`) にして、
  インデントとエスケープの問題を回避しています

## ノード定義の書き方

ノードは **`map(object({...}))` の変数 1 つ**にまとめ、`for_each` で回します。
旧経路のスペース区切り文字列 + `while read -r` による位置依存のパースは廃止済みです。

```hcl
variable "nodes" {
  type = map(object({
    vm_id  = number
    cores  = number
    memory = number
    ip     = string
    role   = string   # "control-plane" | "worker"
  }))
}
```

`count` ではなく **`for_each` を使うこと**。`count` だと途中のノードを消したときに
インデックスがずれて、無関係な VM が作り直されます。

## インフラの前提値（動作実績のある値）

- Proxmox ホスト: `pve01` = `192.168.20.3`
- ブリッジ: `vmbr1`
- ゲートウェイ: `192.168.20.2` / DNS: `192.168.1.1` / netmask: `/24`
- ストレージ: VM ディスクは `local-lvm`、イメージと snippets は `local`
- ディスクサイズ: 64G
- NIC 名: `ens18`（virtio）
- MetalLB の払い出しレンジ: `192.168.20.101` - `192.168.20.150`
- Pod CIDR: `10.244.0.0/16`（flannel 前提）

**VMID / IP の割り当て:**

| 用途 | VMID | IP | Terraform の管理下 |
|---|---|---|---|
| k8s CP 3 台 / Worker 3 台（現行） | 1101 - 1106 | 192.168.20.40 - .45 | あり |
| home-api | 110 | 192.168.20.13 | 既定では作らない設定 |
| k8s クラスタ（旧経路。残っていれば手で消す） | 1001 - 1006 | 192.168.20.30 - .35 | なし |
| テンプレート VM（不要になった。残っていれば手で消す） | 9000 | - | なし |

**旧経路の VM は Terraform の管理外なので `terraform destroy` では消えません。**
新旧は VMID / IP が重ならないので、動作確認が済むまで同居させて構いません。
消す手順は README にあります。

`home-api` は既に稼働している VM です。同じ VMID / IP のまま apply すると衝突するため、
`var.home_api` は既定で `null`（作成しない）にしてあります。
有効化する手順は `terraform/home-api.tf` の冒頭コメントを参照してください。

## ノード構成

**Control Plane 3 台 + Worker 3 台 = 6 ノード。**

- CP 3 台構成なので、`kubeadm init` した 1 台目に対して残り 2 台を
  `--control-plane` 付きで join させる手順が必要です
- CP が 3 台ある以上、**API サーバの VIP / ロードバランサをどうするかを決める必要があります**
  （kube-vip、HAProxy + keepalived など）。現状は未対応で、ここは未決です
- ノード数は `map(object)` 変数で定義するので、検証を速く回したいときは
  tfvars で CP 1 + Worker 2 に減らせる形にしておいてください

## Kubernetes ノードのセットアップ

`cloud-init/k8s-setup.sh.tftpl` が担当します。旧 `k8s-setup/setup.sh` からの
変更点と、その理由は次のとおりです。**元に戻す前にここを読んでください。**

- **`update-alternatives --set iptables iptables-legacy` を外しました。**
  古い k8s 向けの対処で、現在の containerd + kube-proxy では通常不要です。
  問題が出たら戻す（スクリプト内にコメントを残してあります）
- **sysctl を 1 ファイルに集約しました。** 旧スクリプトは
  `/etc/sysctl.d/k8s.conf` を 2 回書いており、後の定義が前を黙って上書きしていました
- **`ufw allow 6443/tcp` を外しました。** クラウドイメージでは ufw は通常 inactive で、
  有効化されていない環境では意味がないためです。有効化する運用に変える場合は戻すこと
- **k8s のリポジトリ URL のマイナーバージョンを変数化しました**
  （`k8s_minor_version`）。バージョン追従で必ず触る箇所です
- **apt のロック待ちを追加しました。** クラウドイメージでは起動直後に
  unattended-upgrades がロックを掴んでいることがあり、`apt-get` が失敗します

引き続き注意が必要な点:

- **cgroup ドライバは `systemd` に揃える。** containerd の
  `/etc/containerd/config.toml` で `SystemdCgroup = true`、kubelet 側も `systemd`。
  ここがずれるとノードが Ready にならない典型的な事故です
- **containerd の設定ファイルの形式はバージョンで変わります。**
  `config.toml` の version 2 / 3 で構造が違うため、`sed` による書き換えが
  そのまま効くとは限りません。k8s のバージョンを上げたときに真っ先に疑う箇所です。
  スクリプトには書き換え結果を検証する `grep` を入れて、
  効かなかった場合に警告が出るようにしてあります
- **`apt-mark hold kubelet kubeadm kubectl`**: 意図しない自動更新でクラスタが壊れるのを防ぐ。
  バージョンを上げるときは明示的に `unhold` する
- **`kubeadm init` / `join` はスクリプトに含めていません。** ノード内の構成管理を
  cloud-init だけで完結させるか Ansible を併用するかが未決のためです（未決事項を参照）

## コーディング規約

- **Terraform**: `terraform fmt` を通す。変数には必ず `type` と `description` を書く。
  秘密情報を持つ変数には `sensitive = true` を付ける
- **プロバイダのバージョンは固定する**（`~>` で範囲指定し、`.terraform.lock.hcl` はコミットする）
- **既存シェルスクリプト**: `#!/usr/bin/env bash` で開始。移行までは現状の書式を維持する
- **YAML / cloud-init**: コメントは日本語で可
- **秘密情報をコミットしない**: API トークン、パスワード平文、秘密鍵。
  SSH 公開鍵は `https://github.com/<user>.keys` から取得する現行方式でよい
- 破壊的な変更を伴うリソース属性を変えるときは、`plan` の差分で
  `# forces replacement` が出ることをコメントで注意喚起する

## 動作確認について

このリポジトリのコードは **実 Proxmox がないと実行できません**。
Claude の作業環境からは実行して確認できないので、次を守ってください。

- **「テストした」「動作確認した」と書かない。** 実行していないなら実行していないと明示する
- 代わりにできる静的チェックは必ず通す:
  - `terraform fmt -check`
  - `terraform validate`（`terraform init` にはネットワークが要る）
  - シェルは `bash -n` / `shellcheck`、YAML は構文チェック
- `terraform apply` / `destroy` や `qm` コマンドは**ユーザに実行してもらう**。勝手に実行しない
- state を壊す操作（`terraform state rm`、`import`、`-target`）を提案するときは、
  何が起きるかを明記してユーザの判断を仰ぐ

## いまの状況と、次にやること

**コードの整理は完了しています。残っているのは実機での確認です。**

1. ~~`terraform/` を実装する~~ — 完了
2. ~~README を書き直す~~ — 完了
3. ~~旧 `qm` 経路（`vm-setup/` `k8s-setup/`）を削除する~~ — 完了
4. **`terraform apply` が通ることを確認する** ← いまここ。**ユーザに実行してもらうこと**
5. 確認できたら、旧クラスタ（VMID 1001-1006）とテンプレート VM（9000）を手で消す
6. `goegoe0212/proxmox-rhel-kubernetes` をアーカイブする

### 4 で確認したいこと

- `terraform init` / `plan` がプロバイダのバージョン制約で通るか
- snippets のアップロードが通るか（データストアの内容種別と SSH の設定）
- `import_from` でクラウドイメージが取り込めるか（テンプレート VM を使わない経路）
- cloud-init が完走し、各ノードに `/var/lib/k8s-node-prepared` ができるか
- `terraform destroy` が 1 コマンドで完了するか

**まだ apply していないので、コードが動く保証はありません。**
エラーが出た場合、真っ先に疑うのは上の 2 番目と 3 番目です。

## 決定済み事項

- **OS**: Ubuntu 24.04 LTS（noble）継続。RHEL / Rocky / Alma への切り替え機構は作らない
- **VM 払い出し**: Terraform（`bpg/proxmox`）。旧 `qm` シェルスクリプト経路は削除済み
- **ノード構成**: CP 3 + Worker 3 の計 6 ノード。VMID 1101-1106 / IP 192.168.20.40-.45
- **`home-api`（VMID 110）**: Terraform に移植済み。ただし既存 VM が稼働しているため既定では作らない
- **リポジトリ**: `goegoe0212/proxmox-rhel-kubernetes` は統合・廃止し、ここに一本化する

## 未決事項（作業前にユーザに確認すること）

1. **CP の VIP / ロードバランサ**: CP 3 台構成なので必須。kube-vip か HAProxy + keepalived か。
   **決まるまでは tfvars で CP 1 + Worker 2 に減らして検証すること**
2. **ノード内の構成管理**: cloud-init だけで完結させるか、Ansible を併用するか。
   ユーザは「まだ決めない」との判断。現状 `kubeadm init` / `join` は手動
3. **Terraform か OpenTofu か**: コードはほぼ共通だが、CI やドキュメントの書き方が変わる
4. **state の置き場**: 現状はローカル state（`.gitignore` 済み）。
   state を失うと VM が孤児になる（VMID を固定してあるので
   `terraform import` か `qm destroy` で復旧できる）。
   MinIO 等の S3 互換バックエンドに移すかは未決
5. **Kubernetes のターゲットバージョン**: 現状は v1.30 のまま。まず同じ版で通してから上げる想定
6. **旧クラスタの VMID / IP の再利用**: 1001-1006 / .30-.35 を空けた後、再利用するか放置するか
7. **正となるリモート**: `ssmc-network` と `goegoe0212` に同名リポジトリがあります。
   コード上の依存は無くなった（`raw.githubusercontent.com` の参照を削除したため）ので
   急ぎませんが、どちらを正とするかは決めた方がよいです
8. **CNI**: 現状は flannel。踏襲するか
