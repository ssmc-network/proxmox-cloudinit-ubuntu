# SSH 公開鍵を GitHub から取得する。
#
# 旧 bash 経路では VM 起動後に runcmd の中で curl していたため、鍵の内容が
# Terraform の管理外だった。plan 時に取得しておけば、鍵が変わったことが
# plan の差分に現れる。
data "http" "github_keys" {
  url = "https://github.com/${var.github_keys_user}.keys"

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "GitHub から SSH 公開鍵を取得できませんでした (HTTP ${self.status_code})。github_keys_user の値を確認してください。"
    }
  }
}

locals {
  github_keys = [
    for key in split("\n", trimspace(data.http.github_keys.response_body)) :
    trimspace(key) if trimspace(key) != ""
  ]

  ssh_authorized_keys = distinct(concat(local.github_keys, var.extra_ssh_authorized_keys))

  # cloud-config の ssh_authorized_keys に差し込む YAML 断片。
  # テンプレート側で for ディレクティブを使うとインデントの制御が
  # 分かりにくくなるため、整形済みの文字列を渡す。
  ssh_authorized_keys_yaml = join("\n", [
    for key in local.ssh_authorized_keys : "      - ${key}"
  ])

  # ノード準備スクリプト。全ノードで共通なので一度だけ描画する。
  # base64 にして cloud-config の write_files に埋め込むため、
  # YAML のインデントやエスケープを気にしなくてよい。
  k8s_setup_script = templatefile("${path.module}/../cloud-init/k8s-setup.sh.tftpl", {
    k8s_minor_version = var.k8s_minor_version
  })
}

# ノードごとの cloud-config を snippets としてアップロードする。
#
# 注意: snippets はデータストアで既定では無効になっている。
# Proxmox の Datacenter > Storage で対象データストアの内容種別に
# snippets を追加しておくこと（Terraform の外側の前提条件）。
resource "proxmox_virtual_environment_file" "cloud_config" {
  for_each = var.nodes

  content_type = "snippets"
  datastore_id = var.datastore_files
  node_name    = var.proxmox_node_name

  source_raw {
    file_name = "${each.key}-cloud-config.yaml"

    data = templatefile("${path.module}/../cloud-init/k8s-node.yaml.tftpl", {
      hostname                 = each.key
      admin_user               = var.admin_user
      ssh_authorized_keys_yaml = local.ssh_authorized_keys_yaml
      k8s_setup_script_b64     = base64encode(local.k8s_setup_script)
    })
  }

  lifecycle {
    precondition {
      condition     = length(local.ssh_authorized_keys) > 0
      error_message = "SSH 公開鍵が 1 つも得られませんでした。このまま apply すると誰もログインできない VM ができます。github_keys_user か extra_ssh_authorized_keys を確認してください。"
    }
  }
}
