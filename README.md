# known_host登録削除
```sh
ssh-keygen -R 192.168.20.41
ssh-keygen -R 192.168.20.42
ssh-keygen -R 192.168.20.43
```

# known_host登録削除
```sh
qm shutdown 1001
qm shutdown 1002
qm shutdown 1003
qm destroy 1001
qm destroy 1002
qm destroy 1003
```


# VMを生やすスクリプト
```sh
/bin/bash <(curl -s https://raw.githubusercontent.com/goegoe0212/proxmox-cloudinit-ubuntu/main/vm-setup/setup.sh)
```
