# クラウドイメージをデータストアに取得する。
#
# 旧 bash 経路では wget でイメージを落とし、qm create -> qm importdisk ->
# qm template でテンプレート VM (VMID 9000) を作っていたが、Terraform では
# disk の import_from で直接取り込めるため、テンプレート VM は不要になる。
resource "proxmox_virtual_environment_download_file" "ubuntu" {
  content_type = "iso"
  datastore_id = var.datastore_files
  node_name    = var.proxmox_node_name

  url       = var.ubuntu_image_url
  file_name = var.ubuntu_image_file_name

  # チェックサムを付けておくと、URL の中身が差し替わったことに気づける。
  checksum           = var.ubuntu_image_checksum
  checksum_algorithm = "sha256"

  # 既定値だが意図を明示しておく。ローカルのファイルがチェックサムと
  # 一致しない場合は取得し直される。
  overwrite = true

  # 大きいイメージなので既定の 600 秒では足りないことがある。
  upload_timeout = 1800
}
