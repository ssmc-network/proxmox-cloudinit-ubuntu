#!/usr/bin/env bash

# special thanks!: https://github.com/unchama/kube-cluster-on-proxmox 

# ----- #

TEMPLATE_VMID=9000
VM_LIST=(
    # ---
    # vmid:       proxmox上でVMを識別するID
    # vmname:     proxmox上でVMを識別する名称およびホスト名
    # cpu:        VMに割り当てるコア数(vCPU)
    # mem:        VMに割り当てるメモリ(MB)
    # vmip:       VMに割り振る固定IP
    # targetip:   VMの配置先となるProxmoxホストのIP
    # targethost: VMの配置先となるProxmoxホストのホスト名
    # ---
    #vmid #vmname      #cpu #mem #vmip         #targetip    #targethost
    "1001 ubuntu-k3s01 4    8192 192.168.20.41 192.168.20.3 pve01"
    "1002 ubuntu-k3s02 4    8192 192.168.20.42 192.168.20.3 pve01"
    "1003 ubuntu-k3s03 4    8192 192.168.20.43 192.168.20.3 pve01"
)

# ---

# Check if the template VM already exists
if ! qm list | grep "${TEMPLATE_VMID}"; then
    echo "Template VMID ${TEMPLATE_VMID} does not exist. Creating template."

    # download the image(ubuntu 24.04 LTS)
    wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img

    # create a new VM and attach Network Adaptor
    qm create $TEMPLATE_VMID --cores 2 --memory 4096 --net0 virtio,bridge=vmbr1

    # import the downloaded disk to local-lvm storage
    qm importdisk $TEMPLATE_VMID noble-server-cloudimg-amd64.img local-lvm

    # add 
    qm set $TEMPLATE_VMID --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-$TEMPLATE_VMID-disk-0

    # add Cloud-Init CD-ROM drive
    qm set $TEMPLATE_VMID --ide2 local-lvm:cloudinit

    # set the bootdisk parameter to scsi0
    qm set $TEMPLATE_VMID --boot c --bootdisk scsi0

    # set serial console
    qm set $TEMPLATE_VMID --serial0 socket --vga serial0

    # migrate to template
    qm template $TEMPLATE_VMID

    # cleanup
    rm noble-server-cloudimg-amd64.img
else
    echo "Template VMID ${TEMPLATE_VMID} already exists. Skipping template creation."
fi

# ---

for array in "${VM_LIST[@]}"
do
    echo "${array}" | while read -r vmid vmname cpu mem vmip targetip targethost
    do
        # clone from template
        # in clone phase, can't create vm-disk to local volume
        qm clone "${TEMPLATE_VMID}" "${vmid}" --name "${vmname}" --full true --target "${targethost}"
        
        # set compute resources
        ssh -n "${targetip}" qm set "${vmid}" --cores "${cpu}" --memory "${mem}"

        # move vm-disk to local
        ssh -n "${targetip}" qm move-disk "${vmid}" scsi0 local-lvm --delete true

        # resize disk (Resize after cloning, because it takes time to clone a large disk)
        ssh -n "${targetip}" qm resize "${vmid}" scsi0 64G

        # create snippet for cloud-init(user-config)
# ----- #
cat > /var/lib/vz/snippets/"$vmname"-user.yaml << EOF
#cloud-config
hostname: ${vmname}
timezone: Asia/Tokyo
manage_etc_hosts: true
ssh_authorized_keys: []
chpasswd:
  expire: False
users:
  - default
  - name: cloudinit
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: false
    passwd: \$5\$t17XO334\$pPuwv1rAgg6Ie/etN3oEhmyDWe7qR1IXvCIGkGPOFB5
package_upgrade: true
runcmd:
  # set ssh_authorized_keys
  - su - cloudinit -c "mkdir -p ~/.ssh && chmod 700 ~/.ssh"
  - su - cloudinit -c "curl -sS https://github.com/goegoe0212.keys >> ~/.ssh/authorized_keys"
  - su - cloudinit -c "chmod 600 ~/.ssh/authorized_keys"
  # change default shell to bash
  - chsh -s $(which bash) cloudinit
EOF
# ----- #
        # create snippet for cloud-init(network-config)
# ----- #
cat > /var/lib/vz/snippets/"$vmname"-network.yaml << EOF
version: 1
config:
    - type: physical
      name: ens18
      subnets:
      - type: static
        address: '${vmip}'
        netmask: '255.255.255.0'
        gateway: '192.168.20.2'
    - type: nameserver
      address:
      - '192.168.1.1'
      search:
      - 'local'
EOF
# ----- #

        # set snippet to vm
        ssh -n "${targetip}" qm set "${vmid}" --cicustom "user=local:snippets/${vmname}-user.yaml,network=local:snippets/${vmname}-network.yaml"

    done
done

# ----- #

for array in "${VM_LIST[@]}"
do
    echo "${array}" | while read -r vmid vmname cpu mem vmsrvip vmsanip targetip targethost
    do
        # start vm
        ssh -n "${targetip}" qm start "${vmid}"
        
    done
done

# ----- #