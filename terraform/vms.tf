resource "proxmox_virtual_environment_vm" "node" {
  for_each = var.nodes

  node_name = var.proxmox_node_name
  vm_id     = each.value.vm_id
  name      = each.key

  description = "Managed by Terraform (role=${each.value.role})"
  tags        = ["terraform", "kubernetes", each.value.role]

  cpu {
    cores = each.value.cores
    type  = var.cpu_type
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = var.datastore_vm_disk

    # テンプレート VM を経由せず、取得したクラウドイメージを直接取り込む。
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

    # Proxmox 側の自動アップグレードは無効にする。パッケージの更新は
    # cloud-config 側で順序を制御したい（apt のロック競合を避けるため）。
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

    user_data_file_id = proxmox_virtual_environment_file.cloud_config[each.key].id
  }

  network_device {
    bridge = var.network_bridge
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  # ゲストの IP 取得などに使う。cloud-config 側で qemu-guest-agent を
  # 導入しているので有効化してよい。入っていないと apply が
  # タイムアウトまで待たされる。
  agent {
    enabled = true
  }

  # destroy 時にシャットダウンの完了を待たない。使い捨て前提なので、
  # 「壊す」を速く確実に終わらせる方を優先する。
  stop_on_destroy = true
}
