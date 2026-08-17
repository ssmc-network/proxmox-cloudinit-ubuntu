# proxmox-cloudinit-ubuntu

オンプレミスの Proxmox VE 上に Terraform で Ubuntu の VM を払い出し、
その上に Kubernetes クラスタを立てるためのリポジトリです。

**目的は Kubernetes のバージョンアップ追従**で、そのために
「簡単に作って、簡単に壊せる」ことを最優先にしています。
クラスタは使い捨てで、壊れたら直さずに作り直します。

## 構成

```
terraform/       Terraform 一式。VM の払い出しはここが担当する
cloud-init/      cloud-config とノード準備スクリプトのテンプレート
manifests/       クラスタに流し込む YAML (MetalLB, 動作確認用 nginx)
legacy/          qm コマンドを直接叩く旧経路（後述。フォールバックとして残置）
k8s-setup/       旧経路が VM 起動時に取得するノード準備スクリプト（後述）
```

## 前提条件

Terraform の外側で、先に済ませておく必要があるものです。

### 1. Proxmox に API トークンを作る

`terraform@pve` などのユーザを作り、API トークンを発行して、
VM の作成・削除に必要な権限を与えてください。

### 2. データストアで snippets を有効にする

**これを忘れると apply が失敗します。**
cloud-init の user-data は snippets としてアップロードされますが、
Proxmox のデータストアでは snippets が既定で無効になっています。

Datacenter > Storage で対象のデータストア（既定では `local`）を開き、
内容種別に **Snippets** を追加してください。

### 3. Proxmox ノードへの SSH を通す

ほとんどの操作は API だけで完結しますが、
**snippets のアップロードだけはノードへの SSH を使います。**
実行元から Proxmox ノードへ SSH できる状態にしてください
（SSH エージェントを使う場合は鍵をロードしておく）。

### 4. 環境変数を設定する

認証情報はコードにもファイルにも書かず、環境変数で渡します。

```sh
export PROXMOX_VE_ENDPOINT="https://192.168.20.3:8006/"
export PROXMOX_VE_API_TOKEN="terraform@pve!provider=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
export PROXMOX_VE_SSH_USERNAME="root"
export PROXMOX_VE_SSH_AGENT="true"
```

## 使い方

```sh
cd terraform

# 必要なら設定を上書きする（terraform.tfvars は .gitignore 済み）
cp terraform.tfvars.example terraform.tfvars

terraform init
terraform plan
terraform apply
```

これで VM が払い出され、cloud-init が各ノードで次を行います。

- 管理ユーザの作成と、`https://github.com/<user>.keys` から取得した SSH 公開鍵の配置
- `qemu-guest-agent` の導入
- swap の無効化、カーネルモジュール、sysctl の設定
- containerd の導入（cgroup ドライバは `systemd`）
- kubelet / kubeadm / kubectl の導入と `apt-mark hold`

**ここまでです。`kubeadm init` / `join` は行いません。**

### 壊す

```sh
cd terraform
terraform destroy
```

前提条件も後始末も不要です。1 コマンドで終わることを維持してください。

VM を作り直すと SSH のホスト鍵が変わるので、必要なら手元で消してください。

```sh
ssh-keygen -R 192.168.20.40
```

## apply の後にやること

ノードの準備が終わったか確認します。

```sh
ssh cloudinit@192.168.20.40 'cloud-init status --wait && ls -l /var/lib/k8s-node-prepared'
```

その後、クラスタを組みます（`terraform output next_steps` にも同じ内容が出ます）。

```sh
# 1 台目の Control Plane で
sudo kubeadm init --pod-network-cidr=10.244.0.0/16

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# CNI (flannel)
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# 残りのノードを join する（kubeadm init の出力に従う）

# MetalLB と動作確認用の nginx
kubectl apply -f manifests/
```

### Control Plane 3 台構成についての注意

**API サーバの VIP / ロードバランサは未対応です。**
Control Plane を複数台にする場合、`--control-plane-endpoint` に指定する
VIP を先に決める必要があります（kube-vip、HAProxy + keepalived など）。

**VIP を決めるまでは、CP 1 台 + Worker 2 台で動作確認するのが安全です。**
`terraform.tfvars` で `nodes` を上書きすれば減らせます。

## バージョンを上げるとき

このリポジトリの主目的です。**変更は 1 箇所で済むようにしてあります。**

### Kubernetes

`terraform.tfvars` の `k8s_minor_version` を変えて、`destroy` → `apply` します。

```hcl
k8s_minor_version = "1.31"
```

上げたときに壊れやすいのは containerd の `config.toml` の形式です
（version 2 / 3 で構造が変わります）。ノードが Ready にならない場合は
まずそこを疑ってください。

### Ubuntu

`ubuntu_image_url` と `ubuntu_image_checksum` を**セットで**更新します。
チェックサムは対象ディレクトリの `SHA256SUMS` から取得してください。

URL は `/releases/<codename>/release-<date>/` の形で日付まで固定しています。
`/<codename>/current/` は daily build で日によって中身が変わるため、
**使わないでください。**「同じコードから同じクラスタを作り直す」が成立しなくなります。

## home-api (VMID 110) について

k8s クラスタとは別用途の Docker ホストです。
旧 `vm-setup-docker.sh` が担当していたものを Terraform に移植してあります。

**既定では作成しません。** この VM は既に稼働しているため、同じ VMID / IP のまま
`apply` すると衝突します。有効化するときは `terraform/home-api.tf` の
冒頭コメントを読んで、作り直すか `terraform import` で取り込むかを決めてください。

有効にする場合は `terraform.tfvars` に次を書きます。

```hcl
home_api = { vm_id = 110, cores = 2, memory = 8192, ip = "192.168.20.13" }
```

## 旧経路（`legacy/` と `k8s-setup/`）について

Terraform 移行前の、`qm` コマンドを直接叩くシェルスクリプトです。
Proxmox ホスト上で実行します。

**Terraform 経路の動作確認が済むまでのフォールバックとして残しています。**
中身は移行前から変更していません（`vm-setup/` から `legacy/` へ移動しただけです）。

```sh
# 旧経路で k8s クラスタを作る場合（Proxmox ホスト上で実行）
bash legacy/vm-setup-kubernetes.sh
```

注意点が 2 つあります。

- **`k8s-setup/setup.sh` を移動・改名しないでください。**
  `legacy/vm-setup-kubernetes.sh` の cloud-init が、VM の起動時に
  このファイルを `raw.githubusercontent.com` 経由で `main` から取得します。
  つまり **`main` にあるそのファイルは、次に VM を起動した瞬間に実行されます。**
  `legacy/` 配下へ移すとファイルが残っていても URL が 404 になり、旧経路が壊れます
- 旧経路のクラスタは VMID `1001`-`1006` / IP `192.168.20.30`-`.35`、
  Terraform 経路は `1101`-`1106` / `192.168.20.40`-`.45` を使うので、**同居できます**

ノード準備の内容を変えたいときは、`k8s-setup/setup.sh` ではなく
**`cloud-init/k8s-setup.sh.tftpl` の方を直してください**（`k8s-setup/setup.sh` を
触ると、旧経路で作り直したクラスタに即座に影響します）。

### 旧クラスタの後始末

Terraform 経路に完全に移った後、旧経路で作った VM を消す場合の手順です。
これらは Terraform の管理外なので `terraform destroy` では消えません。

```sh
for id in 1001 1002 1003 1004 1005 1006; do qm shutdown $id; done
for id in 1001 1002 1003 1004 1005 1006; do qm destroy  $id; done

# テンプレート VM（Terraform はイメージを直接取り込むため不要）
qm destroy 9000
```

**Terraform 経路の動作確認が済むまでは消さないでください。**

## 動作確認の状況

Terraform のコードは **実 Proxmox がないと apply できないため、未実行です。**
実施済みの静的チェックは次のとおりです。

- `cloud-init/*.tftpl` 4 ファイルを描画し、未定義の補間参照が無いことを確認
- 描画後のセットアップスクリプト 2 本に対する `bash -n`
- 描画後の cloud-config 2 本の YAML パース、埋め込みスクリプトの base64 往復一致、
  および `qemu-guest-agent` が `packages` に含まれること
  （`agent { enabled = true }` と矛盾していないかの確認）
- `terraform/*.tf` の括弧の対応、未定義変数の参照、未使用変数、
  解決できないリソース参照が無いこと

`terraform fmt` / `terraform validate` は実行環境に Terraform が無いため未実行です。
**初回の `terraform init` の後に必ず流してください。**
