# 認証値はコードに書かない。次の環境変数で渡すこと。
#
#   export PROXMOX_VE_ENDPOINT="https://192.168.20.3:8006/"
#   export PROXMOX_VE_API_TOKEN="terraform@pve!provider=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
#
# ほとんどの操作は API だけで完結するが、snippets（cloud-init の user-data）の
# アップロードだけはノードへの SSH を必要とするため ssh ブロックが要る。
#
#   export PROXMOX_VE_SSH_USERNAME="root"
#   export PROXMOX_VE_SSH_AGENT="true"
#
# 変数側を null のままにしておけば、上記の環境変数が使われる。
provider "proxmox" {
  insecure = var.proxmox_insecure

  ssh {
    agent    = var.proxmox_ssh_agent
    username = var.proxmox_ssh_username
  }
}

provider "http" {}
