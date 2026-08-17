terraform {
  required_version = ">= 1.5.0"

  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      # bpg/proxmox はまだ 0.x のため、マイナーバージョンで破壊的変更が入りうる。
      # "~> 0.111.1" は >= 0.111.1, < 0.112.0 の意味で、パッチ更新のみを許可する。
      # マイナーを上げるときは CHANGELOG を読んでから手で変更すること。
      version = "~> 0.111.1"
    }

    # SSH 公開鍵を https://github.com/<user>.keys から取得するために使う。
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}
