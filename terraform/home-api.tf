# home-api (VMID 110) — Kubernetes クラスタとは別用途の Docker ホスト。
#
# 旧 vm-setup/vm-setup-docker.sh が担当していたものを移植した。
#
# ------------------------------------------------------------------------
# 既定では作成しません（var.home_api = null）。
#
# この VM は既に稼働しているため、同じ VMID / IP のまま apply すると
# 既存 VM と衝突します。有効化する前に、どちらかを選んでください。
#
#   a) 作り直す
#      既存 VM を先に消してから var.home_api を設定して apply する。
#      データは失われるので、必要なら退避しておくこと。
#
#   b) 既存 VM を Terraform の管理下に取り込む
#      var.home_api を設定したうえで import する。
#        terraform import 'proxmox_virtual_environment_vm.home_api["home-api"]' pve01/110
#      取り込んだ後の plan には、既存 VM と現在の定義との差分が出ます。
#      その差分を適用すると VM が作り直される可能性があるため、
#      plan の内容を必ず確認してから apply してください。
# ------------------------------------------------------------------------

locals {
  home_api_instances = var.home_api == null ? {} : { "home-api" = var.home_api }
}

resource "proxmox_virtual_environment_file" "home_api_cloud_config" {
  for_each = local.home_api_instances

  content_type = "snippets"
  datastore_id = var.datastore_files
  node_name    = var.proxmox_node_name

  source_raw {
    file_name = "${each.key}-cloud-config.yaml"

    data = templatefile("${path.module}/../cloud-init/home-api.yaml.tftpl", {
      hostname                 = each.key
      admin_user               = var.admin_user
      ssh_authorized_keys_yaml = local.ssh_authorized_keys_yaml

      docker_setup_script_b64 = base64encode(templatefile(
        "${path.module}/../cloud-init/docker-setup.sh.tftpl",
        { admin_user = var.admin_user }
      ))
    })
  }

  lifecycle {
    precondition {
      condition     = length(local.ssh_authorized_keys) > 0
      error_message = "SSH 公開鍵が 1 つも得られませんでした。このまま apply すると誰もログインできない VM ができます。"
    }
  }
}

resource "proxmox_virtual_environment_vm" "home_api" {
  for_each = local.home_api_instances

  node_name = var.proxmox_node_name
  vm_id     = each.value.vm_id
  name      = each.key

  description = "Managed by Terraform (role=docker)"
  tags        = ["terraform", "docker"]

  cpu {
    cores = each.value.cores
    type  = var.cpu_type
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = var.datastore_vm_disk

    # ここを変更すると plan に "# forces replacement" が出て VM が作り直される。
    import_from = proxmox_virtual_environment_download_file.ubuntu.id

    interface = "scsi0"

    # Proxmox の制約により、一度作った後に縮小はできない。
    size = var.vm_disk_size

    discard = "on"
    ssd     = true
  }

  initialization {
    datastore_id = var.datastore_vm_disk

    upgrade = false

    dns {
      domain  = var.dns_domain
      servers = var.dns_servers
    }

    ip_config {
      ipv4 {
        address = "${each.value.ip}/${var.network_cidr_prefix}"
        gateway = var.network_gateway
      }
    }

    user_data_file_id = proxmox_virtual_environment_file.home_api_cloud_config[each.key].id
  }

  network_device {
    bridge = var.network_bridge
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  agent {
    enabled = true
  }

  # k8s ノードと違い、home-api は使い捨てではない。
  # 誤って消したときの被害が大きいので、シャットダウンの完了を待つ。
  stop_on_destroy = false
}
