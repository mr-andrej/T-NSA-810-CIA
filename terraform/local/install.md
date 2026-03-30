## 1. Prérequis CPU

```bash
# Vérifier que la virtualisation matérielle est disponible
egrep -c '(vmx|svm)' /proc/cpuinfo  # doit retourner > 0

# Voir le détail du CPU
lscpu | grep -E "CPU\(s\)|Thread|Core|Socket|Model name"
```

---

## 2. Installation KVM/libvirt (Tuxedo OS / Ubuntu)

```bash
# Installer KVM + libvirt + virt-manager
sudo apt install -y qemu-kvm libvirt-daemon-system \
  libvirt-clients bridge-utils virt-manager

# Démarrer et activer libvirt
sudo systemctl enable --now libvirtd

# Ajouter ton user aux groupes
sudo usermod -aG libvirt,kvm $USER

# Vérifier que le socket existe
ls /run/libvirt/libvirt-sock
```

> **Important** : fermer et rouvrir la session (ou rebooter) pour que les groupes soient actifs.

---

## 3. Activation de la nested virtualization

### AMD

```bash
echo "options kvm-amd nested=1" | sudo tee /etc/modprobe.d/kvm-amd.conf
sudo modprobe -r kvm_amd && sudo modprobe kvm_amd
cat /sys/module/kvm_amd/parameters/nested  # doit retourner Y
```

### Intel

```bash
echo "options kvm-intel nested=1" | sudo tee /etc/modprobe.d/kvm-intel.conf
sudo modprobe -r kvm_intel && sudo modprobe kvm_intel
cat /sys/module/kvm_intel/parameters/nested  # doit retourner Y
```

---

## 4. Commandes Terraform

```bash
# Initialiser le projet
terraform init

# Vérifier le plan
terraform plan

# Appliquer
terraform apply

# Détruire (pour repartir de zéro)
terraform destroy
```

---

## 5. Accéder à la VM Proxmox

```bash
# Via virt-manager (interface graphique)
virt-manager

# Via console
virt-viewer proxmox1
```

L'installateur Proxmox se lance graphiquement. Une fois installé, l'interface web est accessible sur `https://<IP-VM>:8006`.



---

## Notes importantes

- `cpu { mode = "host-passthrough" }` est **indispensable** pour que Proxmox puisse créer des VMs KVM
- Le pool libvirt doit être créé via `qemu:///system` (et non `qemu+unix`) pour être visible par Terraform
- L'ISO Proxmox peut être fournie via une URL directe plutôt qu'un chemin local
- Ansible ne tourne pas nativement sur Windows — utiliser WSL2

## AppArmor issues

I had this issue when having `AppArmor` installed and enabled and i found solutions and it worked for me.  
For my case:

- `libvirt` + `qemu` + `kvm`
- OS: `Ubuntu server`
- OS version: `24.04`
- arch: `amd64`
- target disk images dir: `/var/lib/images/mypool/debian12.qcow2`

[libvirt-qemu.txt](https://github.com/user-attachments/files/19262458/libvirt-qemu.txt)

`libvirt` create new `AppArmor` profile when creating new `domain (vm)` and each profile uses file `/etc/apparmor.d/abstractions/libvirt-qemu` and it does not have write access to images dir `/var/lib/libvirt/images` .

- Solution 1: Disable `AppArmor` (bad for security)

```shell
sudo systemctl disable --now apparmor
```

- Solution 2: Create file in `AppArmor` config dir
    
    > Notes:  
    > By default, dirs, sub dirs, files and sub files in `/etc/apparmor.d/` have these permissions:
    > 
    > - For dir:s `0755`
    > - For files: `0644`
    
    - Check file `/etc/apparmor.d/abstractions/libvirt-qemu`, it should be like this
        
        ```shell
        less /etc/apparmor.d/abstractions/libvirt-qemu
        ```
        
        See the uploaded file `libvirt-qemu.txt`. (I added extension .txt just for upload but it should not have this)  
        At the end of file you should have.
        
        > Notes:  
        > There are 2 spaces at the beginning of each line.
        
        ```
          include if exists <abstractions/libvirt-qemu.d>
        ```
        
    - Create dir if no exists: `/etc/apparmor.d/abstractions/libvirt-qemu.d`
        
        ```shell
        sudo mkdir -p /etc/apparmor.d/abstractions/libvirt-qemu.d
        ```
        
    - Create this file `/etc/apparmor.d/abstractions/libvirt-qemu.d/override`.
        
        ```shell
        sudo vim /etc/apparmor.d/abstractions/libvirt-qemu.d/override
        ```
        
        ```
        # /etc/apparmor.d/abstractions/libvirt-qemu.d/override
        
         /var/lib/libvirt/images/** rwk,
        ```
        
    - Restart `AppAmor`
        
        ```shell
        sudo systemctl restart apparmor
        ```
