# ---------------------------------------------------------------------------
# Proxmox 接続
# ---------------------------------------------------------------------------

variable "proxmox_node_name" {
  type        = string
  description = "VM を配置する Proxmox ノード名"
  default     = "pve01"
}

variable "proxmox_insecure" {
  type        = bool
  description = "Proxmox API の TLS 証明書検証をスキップするか（自己署名証明書なら true）"
  default     = true
}

variable "proxmox_ssh_username" {
  type        = string
  description = "snippets アップロードに使う SSH ユーザ。null なら PROXMOX_VE_SSH_USERNAME を使う"
  default     = null
}

variable "proxmox_ssh_agent" {
  type        = bool
  description = "SSH エージェントで認証するか。false にする場合は PROXMOX_VE_SSH_PRIVATE_KEY を設定すること"
  default     = true
}

# ---------------------------------------------------------------------------
# ストレージ
# ---------------------------------------------------------------------------

variable "datastore_vm_disk" {
  type        = string
  description = "VM のディスクを置くデータストア"
  default     = "local-lvm"
}

variable "datastore_files" {
  type        = string
  description = "クラウドイメージと snippets を置くデータストア。snippets の内容種別を有効化しておくこと"
  default     = "local"
}

variable "vm_disk_size" {
  type        = number
  description = "VM のディスクサイズ (GB)。Proxmox の制約で後から縮小はできない"
  default     = 64
}

# ---------------------------------------------------------------------------
# クラウドイメージ
#
# /<codename>/current/ は daily build で、同じ URL でも日によって中身が変わる。
# 再現性のため /releases/<codename>/release-<date>/ を明示して固定する。
# チェックサムは同ディレクトリの SHA256SUMS から取得すること。
# ---------------------------------------------------------------------------

variable "ubuntu_image_url" {
  type        = string
  description = "取得する Ubuntu クラウドイメージの URL"
  default     = "https://cloud-images.ubuntu.com/releases/noble/release-20260814/ubuntu-24.04-server-cloudimg-amd64.img"
}

variable "ubuntu_image_checksum" {
  type        = string
  description = "クラウドイメージの SHA256 チェックサム。ubuntu_image_url と必ずセットで更新すること"
  default     = "6e40c07ae715f744f84af0bec76415cc1987dd115b4b8de437818561f01a3733"
}

variable "ubuntu_image_file_name" {
  type        = string
  description = "データストア上のファイル名"
  default     = "ubuntu-24.04-server-cloudimg-amd64.img"
}

# ---------------------------------------------------------------------------
# ネットワーク
# ---------------------------------------------------------------------------

variable "network_bridge" {
  type        = string
  description = "VM を接続する Proxmox のブリッジ"
  default     = "vmbr1"
}

variable "network_gateway" {
  type        = string
  description = "デフォルトゲートウェイ"
  default     = "192.168.20.2"
}

variable "network_cidr_prefix" {
  type        = number
  description = "各ノードの IP に付けるプレフィックス長"
  default     = 24
}

variable "dns_servers" {
  type        = list(string)
  description = "ゲストに設定する DNS サーバ"
  default     = ["192.168.1.1"]
}

variable "dns_domain" {
  type        = string
  description = "DNS 検索ドメイン"
  default     = "local"
}

# ---------------------------------------------------------------------------
# ノード定義
#
# count ではなく for_each で回すため map にしている。count だと途中のノードを
# 消したときにインデックスがずれ、無関係な VM が作り直される。
#
# VMID / IP は旧 bash 経路のクラスタ (1001-1006 / .30-.35)、テンプレート VM
# (9000)、home-api (110 / .13) と重ならない値にしてある。移行中は新旧が
# 同居しうるので、ここを既存と揃えないこと。
# ---------------------------------------------------------------------------

variable "nodes" {
  type = map(object({
    vm_id  = number
    cores  = number
    memory = number # MB
    ip     = string
    role   = string # "control-plane" もしくは "worker"
  }))
  description = "払い出す Kubernetes ノードの定義。キーがホスト名になる"

  default = {
    "k8s-cp-01" = { vm_id = 1101, cores = 2, memory = 8192, ip = "192.168.20.40", role = "control-plane" }
    "k8s-cp-02" = { vm_id = 1102, cores = 2, memory = 8192, ip = "192.168.20.41", role = "control-plane" }
    "k8s-cp-03" = { vm_id = 1103, cores = 2, memory = 8192, ip = "192.168.20.42", role = "control-plane" }
    "k8s-wk-01" = { vm_id = 1104, cores = 4, memory = 8192, ip = "192.168.20.43", role = "worker" }
    "k8s-wk-02" = { vm_id = 1105, cores = 4, memory = 8192, ip = "192.168.20.44", role = "worker" }
    "k8s-wk-03" = { vm_id = 1106, cores = 4, memory = 8192, ip = "192.168.20.45", role = "worker" }
  }

  validation {
    condition     = alltrue([for n in var.nodes : contains(["control-plane", "worker"], n.role)])
    error_message = "role は \"control-plane\" もしくは \"worker\" のいずれかにしてください。"
  }

  validation {
    condition     = length([for n in var.nodes : n.role if n.role == "control-plane"]) > 0
    error_message = "control-plane のノードが最低 1 台必要です。"
  }

  validation {
    condition     = length(distinct([for n in var.nodes : n.vm_id])) == length(var.nodes)
    error_message = "vm_id が重複しています。"
  }

  validation {
    condition     = length(distinct([for n in var.nodes : n.ip])) == length(var.nodes)
    error_message = "ip が重複しています。"
  }
}

variable "cpu_type" {
  type        = string
  description = "エミュレートする CPU タイプ。host はホストの機能をそのまま渡すが、異なる CPU のノードへのライブマイグレーションができなくなる"
  default     = "host"
}

# ---------------------------------------------------------------------------
# Kubernetes
# ---------------------------------------------------------------------------

variable "k8s_minor_version" {
  type        = string
  description = "導入する Kubernetes のマイナーバージョン。パッケージリポジトリの URL に含まれる (例: \"1.30\")"
  default     = "1.30"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.k8s_minor_version))
    error_message = "k8s_minor_version は \"1.30\" のように メジャー.マイナー の形式で指定してください（パッチ番号は含めない）。"
  }
}

# ---------------------------------------------------------------------------
# アクセス
# ---------------------------------------------------------------------------

variable "admin_user" {
  type        = string
  description = "各ノードに作成する管理ユーザ名"
  default     = "cloudinit"
}

variable "github_keys_user" {
  type        = string
  description = "SSH 公開鍵の取得元となる GitHub ユーザ名。https://github.com/<user>.keys を plan 時に取得する"
  default     = "goegoe0212"
}

variable "extra_ssh_authorized_keys" {
  type        = list(string)
  description = "GitHub から取得する鍵に追加したい SSH 公開鍵"
  default     = []
}
