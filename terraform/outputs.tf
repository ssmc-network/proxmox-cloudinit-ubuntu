locals {
  control_plane_names = sort([for name, n in var.nodes : name if n.role == "control-plane"])
  worker_names        = sort([for name, n in var.nodes : name if n.role == "worker"])

  # kubeadm init を実行する 1 台目。名前でソートしているので、
  # ノードを増減させても対象が勝手に入れ替わらない。
  bootstrap_node = local.control_plane_names[0]
}

output "nodes" {
  description = "払い出したノードの一覧"
  value = {
    for name, n in var.nodes : name => {
      vm_id = n.vm_id
      ip    = n.ip
      role  = n.role
    }
  }
}

output "control_plane_ips" {
  description = "Control Plane ノードの IP"
  value       = [for name in local.control_plane_names : var.nodes[name].ip]
}

output "worker_ips" {
  description = "Worker ノードの IP"
  value       = [for name in local.worker_names : var.nodes[name].ip]
}

output "bootstrap_node" {
  description = "kubeadm init を実行する Control Plane ノード"
  value = {
    name = local.bootstrap_node
    ip   = var.nodes[local.bootstrap_node].ip
  }
}

output "ssh_commands" {
  description = "各ノードへの SSH コマンド"
  value = {
    for name, n in var.nodes : name => "ssh ${var.admin_user}@${n.ip}"
  }
}

output "next_steps" {
  description = "apply 後に手で実行する手順。詳細は README を参照"
  value       = <<-EOT
    1. 各ノードの準備完了を確認する（cloud-init の完了を待つ）
         ssh ${var.admin_user}@${var.nodes[local.bootstrap_node].ip} 'cloud-init status --wait && ls -l /var/lib/k8s-node-prepared'

    2. Control Plane を初期化する（${local.bootstrap_node} 上で実行）
         sudo kubeadm init --pod-network-cidr=10.244.0.0/16

       注意: Control Plane が複数ある構成では、API サーバの VIP を
       決めてから --control-plane-endpoint を付けて init すること。
       VIP が未定のうちは CP 1 台で動作確認するのが安全。

    3. CNI を導入する
         kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

    4. 残りのノードを join する（kubeadm init の出力に従う）

    5. MetalLB と動作確認用の nginx を流す
         kubectl apply -f manifests/
  EOT
}
