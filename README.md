# known_host登録削除
```sh
ssh-keygen -R 192.168.20.41
ssh-keygen -R 192.168.20.42
ssh-keygen -R 192.168.20.43
```

# VMを生やすスクリプト
```sh
/bin/bash <(curl -s https://raw.githubusercontent.com/goegoe0212/proxmox-cloudinit-ubuntu/main/vm-setup/setup.sh)
```
