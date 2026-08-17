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

**Terraform 経路を実装済みですが、まだ実 Proxmox で apply していません。**
旧 `qm` シェルスクリプト経路は `legacy/` にフォールバックとして残してあります。

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
cloud-init/
  k8s-node.yaml.tftpl    # cloud-config テンプレート
  k8s-setup.sh.tftpl     # ノード準備スクリプト（base64 で cloud-config に埋め込む）
manifests/               # クラスタに流し込む YAML (metallb, 動作確認用 nginx)
legacy/                  # 旧経路。Proxmox ホスト上で実行する
  vm-setup-docker.sh       # home-api (VMID 110) 用
  vm-setup-kubernetes.sh   # k8s クラスタ (VMID 1001-1006) 用
k8s-setup/
  setup.sh               # 旧経路が起動時に取得するスクリプト（後述・動かさないこと）
```

**Terraform 経路と旧経路は VMID / IP が重ならないので同居できます。**

| | VMID | IP |
|---|---|---|
| Terraform 経路 | 1101 - 1106 | 192.168.20.40 - .45 |
| 旧経路 | 1001 - 1006 | 192.168.20.30 - .35 |

### なぜ Terraform にするのか

- **「壊す」が `terraform destroy` の 1 コマンドになる。** 現状は README に
  `qm shutdown` / `qm destroy` を VMID の数だけ並べたメモがあり、手作業です
- **テンプレート VM（VMID 9000）を手で作る工程が消える。** `disk` の `import_from` で
  クラウドイメージを直接取り込めるため、`qm create` → `importdisk` → `qm template` が不要になります
- **ノード定義が位置依存のパースから解放される。** 現状の
  `"vmid vmname cpu mem ip ..."` というスペース区切り文字列 + `while read -r` は、
  カラムを 1 つ増やすだけで壊れます
- **state があるので、何が存在するかをコードが把握できる。** 現状は `qm list` を grep しています

## 移行中に壊してはいけないもの（重要）

**このリポジトリの `main` は「動いているインフラ」です。** 移行作業では次に注意してください。

### 1. `k8s-setup/setup.sh` のパスを動かさないこと

`legacy/vm-setup-kubernetes.sh` の cloud-init が、VM の起動時にこの URL を叩いています。

```
https://raw.githubusercontent.com/ssmc-network/proxmox-cloudinit-ubuntu/main/k8s-setup/setup.sh
```

つまり **`main` にあるこのファイルは、次に VM を起動した瞬間に実行されます。**

- **このパスを移動・改名しないこと。** 旧経路でクラスタを作り直したときに壊れます
- Terraform 経路の動作確認が取れて `legacy/` を削除するまでは触らない
- 中身を変更する場合も、**push した瞬間に次回起動分から挙動が変わる**ことを意識すること

この「push が即座に本番に効く」構造自体が問題なので、**Terraform 側は
`cloud-init/k8s-setup.sh.tftpl` を `templatefile()` で描画し、base64 にして
cloud-config の `write_files` に埋め込む方式**にしてあります。
スクリプトの内容が Terraform の管理下に入り、`plan` の差分にも現れます。

なお `k8s-setup/setup.sh` と `cloud-init/k8s-setup.sh.tftpl` は**内容が重複しています。**
移行期間中の意図的な重複です。**旧経路を消すときに `k8s-setup/` ごと削除してください。**
それまでの間、ノード準備の内容を変える場合は `cloud-init/` 側だけを直すこと
（`k8s-setup/setup.sh` を触ると動いているクラスタの再構築に即座に影響します）。

### 2. 対応済みの問題（記録）

以前ここに挙げていた不具合は対応済みです。再発させないために残します。

- **`README.md` の入口が存在しないファイル（`vm-setup/setup.sh`）を指していた** — 書き直し済み
- **`vm-setup/` を `legacy/` に移動し、`mv-setup-kubernetes.sh` のタイポを
  `vm-setup-kubernetes.sh` に修正済み。** `k8s-setup/setup.sh` は前述の理由で動かしていません
- **README の URL が `goegoe0212/` を指し、`setup.sh` の参照先 `ssmc-network/` と食い違っていた** —
  どちらを正とするかは未決のままです（このクローンの origin は `ssmc-network`）

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
      source  = "bpg/proxmox"
      version = "~> 0.x"   # 必ずバージョンを固定する
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

### 既存のシェル処理と Terraform リソースの対応

| 現状のシェル処理 | Terraform での置き換え |
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

**現状のスクリプトは `cloud-images.ubuntu.com/noble/current/` を使っていますが、これは daily build です。**
同じ URL でも日によって中身が変わるため、「同じコードから同じクラスタを作り直す」が成立しません。
移行時に必ず直してください。

- **`/<codename>/current/` ではなく `/releases/<codename>/release/` を使うこと**
- **`checksum` を必ず付けてください。** イメージが差し替わったことに気づけます
- **URL とバージョンは変数にしてください。** Ubuntu のリリースを上げるときに 1 箇所で済みます
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
- **ヒアドキュメント内の `$` エスケープ**: 現状のスクリプトは cloud-init を
  ヒアドキュメントで生成しており、パスワードハッシュの `$5$...` を `\$5\$...` と
  エスケープしています。Terraform の `templatefile()` に移すと
  **エスケープの規則が変わります**（`${}` が Terraform の補間になる）。移行時の事故ポイントです

## ノード定義の書き方

現状はスペース区切りの文字列配列（`"vmid vmname cpu mem ip ..."`）ですが、
Terraform では **`map(object({...}))` の変数 1 つ**にまとめ、`for_each` で回してください。
位置依存のパース（`while read -r`）はもう不要です。

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

**現在割り当て済みの VMID / IP:**

| 用途 | VMID | IP |
|---|---|---|
| テンプレート VM（Terraform 移行後は不要になる） | 9000 | - |
| k8s CP 3 台 / Worker 3 台 | 1001 - 1006 | 192.168.20.30 - .35 |
| home-api | 110 | 192.168.20.13 |

**移行中は新旧クラスタが同居する可能性があります。**
Terraform 側で払い出すクラスタは、動作確認が済むまで
**上記と重ならない VMID / IP 帯**を使ってください。同じ値を使うと既存クラスタを踏み潰します。

## ノード構成

**Control Plane 3 台 + Worker 3 台 = 6 ノード**（現状を踏襲）。

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

## 移行の進め方

**旧経路を残したまま Terraform 経路を並行して作り、動作確認してから旧経路を消します。**

1. ~~`terraform/` を追加する~~ — 実装済み
2. ~~README を書き直す~~ — 対応済み
3. **`terraform apply` で、既存と重ならない VMID / IP にクラスタを払い出せることを確認する**
   ← いまここ。**ユーザに実行してもらうこと**
4. 確認できたら `legacy/` と `k8s-setup/` を削除する。
   **この時点で初めて `k8s-setup/setup.sh` を消してよい**
5. `goegoe0212/proxmox-rhel-kubernetes` をアーカイブする

### 3 で確認したいこと

- `terraform init` / `plan` がプロバイダのバージョン制約で通るか
- snippets のアップロードが通るか（データストアの内容種別と SSH の設定）
- `import_from` でクラウドイメージが取り込めるか（テンプレート VM を使わない経路）
- cloud-init が完走し、各ノードに `/var/lib/k8s-node-prepared` ができるか
- `terraform destroy` が 1 コマンドで完了するか

## 決定済み事項

- **OS**: Ubuntu 24.04 LTS（noble）継続。RHEL / Rocky / Alma への切り替え機構は作らない
- **VM 払い出し**: `qm` シェルスクリプトから Terraform（`bpg/proxmox`）へ移行する
- **ノード構成**: CP 3 + Worker 3 の計 6 ノード
- **リポジトリ**: `goegoe0212/proxmox-rhel-kubernetes` は統合・廃止し、ここに一本化する

## 未決事項（作業前にユーザに確認すること）

1. **正となるリモートはどちらか**: `ssmc-network` と `goegoe0212` に同名リポジトリがあり、
   `setup.sh` の参照先と README の URL が食い違っています
2. **`home-api`（VMID 110）の扱い**: k8s クラスタとは別用途です。
   Terraform 移行の対象に含めるか、別で管理するか
3. **ノード内の構成管理**: cloud-init だけで完結させるか、Ansible を併用するか。
   ユーザは「まだ決めない」との判断。まずは Terraform の VM 払い出しまでを作る
4. **CP の VIP / ロードバランサ**: CP 3 台構成なので必須。kube-vip か HAProxy + keepalived か
5. **Terraform か OpenTofu か**: コードはほぼ共通だが、CI やドキュメントの書き方が変わる
6. **state の置き場**: ローカル state（`.gitignore`）で始めるか、
   MinIO 等の S3 互換バックエンドを使うか。ローカルの場合、state を失うと VM が孤児になる
   （VMID を固定しておけば `terraform import` か `qm destroy` で復旧できる）
7. **Kubernetes のターゲットバージョン**: 現状は v1.30。移行と同時に上げるか、まず同じ版で通すか
8. **移行後の VMID / IP**: 旧クラスタを消した後、1001-1006 / .30-.35 を再利用するか、別帯にするか
9. **CNI**: 現状は flannel。踏襲するか
