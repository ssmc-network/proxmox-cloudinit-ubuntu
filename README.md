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

# k8s CPを生やす
```sh
sudo kubeadm init --pod-network-cidr=10.244.0.0/16

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config


kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
```