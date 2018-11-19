#!/bin/bash

# DON'T INSTALL PYTHON PACKAGES WITH PIP!!! ONLY PACKMAN!

# Before start make sure that you have 3 LUKS partitions decrypted and mounted to /, /home and /data

LOCATION=America/Los_Angeles
HOSTNAME=klabunpc
USER=klabun
GROUPS=(log network floppy scanner power wheel audio optical storage users rfkill)
DISTNAME=Arch Linux
DISTENTRY=archlinux

UNENCRYPTED_ROOTDRIVE=$(findmnt /mnt -o SOURCE -n)
ROOTDRIVE="/dev/"$(dmsetup deps -o blkdevname $UNENCRYPTED_ROOTDRIVE | cut -f2 -d":" | tr -d "() ")
ROOTDRIVE_PARTUUID=blkid -s PARTUUID -o value $ROOTDRIVE

UNENCRYPTED_HOMEDRIVE=$(findmnt /mnt/home -o SOURCE -n)
HOMEDRIVE="/dev/"$(dmsetup deps -o blkdevname $UNENCRYPTED_HOMEDRIVE | cut -f2 -d":" | tr -d "() ")
HOME_PARTUUID=blkid -s PARTUUID -o value $HOMEDRIVE

UNENCRYPTED_DATADRIVE=$(findmnt /mnt/data -o SOURCE -n)
DATADRIVE="/dev/"$(dmsetup deps -o blkdevname $UNENCRYPTED_DATADRIVE | cut -f2 -d":" | tr -d "() ")
DATA_PARTUUID=blkid -s PARTUUID -o value $DATADRIVE

BOOTDRIVE=$(findmnt /mnt/boot -o SOURCE -n)

# Install distribution base to /mnt
pacstrap -i /mnt base base-devel terminus-font
arch-chroot /mnt

# Configure locale and timezone
echo "en_US.UTF-8 UTF-8\nru_RU.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo LANG=en_US.UTF-8 > /etc/locale.conf
echo FONT=ter-118n > /etc/vconsole.conf
ln -sf /usr/share/zoneinfo/$LOCATION /etc/localtime
hwclock --systohc

# Configure modules
echo 'options usbcore autosuspend=1' | sudo tee -a /etc/modprobe.d/usbcore.conf

# Configure systemd-boot
pacman -S intel-ucode
mkinitcpio -p linux

echo "\
timeout 1
default $DISTNAME"\
> /boot/loader/loader.conf

echo "\
title ArchLinux
linux       /vmlinuz-linux
initrd      /intel-ucode.img
initrd      /initramfs-linux.img
options     cryptdevice=PARTUUID=$ROOTDRIVE_PARTUUID:system-root root=/dev/mapper/system-root rw pcie_aspm=force i915.enable_rc6=7 net.ifnames=0"\
> /boot/loader/entries/$DISTENTRY.conf
bootctl install

# Configure other partions decryption, when / is already decrypted
mkdir /.cryptokeys
dd bs=512 count=4 if=/dev/random of=/.cryptokeys/home.key
dd bs=512 count=4 if=/dev/random of=/.cryptokeys/data.key
chmod 600 /.cryptokeys -R
cryptsetup luksAddKey $HOMEDRIVE /.cryptokeys/home.key
cryptsetup luksAddKey $DATADRIVE /.cryptokeys/data.key

echo "\
# <name>       <device>                                     <password>              <options>
home           $HOMEDRIVE                               /.cryptokeys/home.key   luks,timeout=15
data           $DATADRIVE                               /.cryptokeys/data.key   luks,timeout=15"\
> /etc/crypttab

echo "\
# $UNENCRYPTED_ROOTDRIVE
UUID=$UNENCRYPTED_ROOTDRIVE_UUID   /         	ext4      	rw,noatime,discard,data=ordered	0 1

# $BOOTDRIVE LABEL=ESP
UUID=$BOOTDRIVE_UUID                          	/boot/   	vfat      	rw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=iso8859-1,shortname=mixed,utf8,errors=remount-ro	0 2

# $UNENCRYPTED_HOMEDRIVE
UUID=$UNENCRYPTED_HOMEDRIVE_UUID	/home     	ext4      	rw,noatime,discard,data=ordered	0 2

# $UNENCRYPTED_DATADRIVE
UUID=$UNENCRYPTED_DATADRIVE_UUID	/data     	ext4      	rw,noatime,discard,data=ordered	0 2

# Add swap device here if needed 
#UUID=	none      	swap      	defaults,pri=-2	0 0"\
> /etc/fstab

# Configure Network
echo $HOSTNAME > /etc/hostname
echo "::1     $HOSTNAME.localdomain  $HOSTNAME" >> /etc/hosts

useradd -mG $GROUPS $USER
passwd $USER

# Install yay
cd /tmp
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si

# Clean distro
yay -R --noconfirm grub virtualbox-guest-modules-arch virtualbox-guest-utils

# Update distro
yay -Syu --noconfirm

# Install Software
yay -S --noconfirm xclip mesa libva xorg-server xorg-xinit xorg-xbacklight systemd-boot-pacman-hook linux-headers dialog wpa_supplicant --noconfirm
yay -S termite alacritty tmux powerline vim fish ranger fzf --noconfirm
yay -S google-chrome chromium gpicview --noconfirm
yay -S yadm-git xfce4-screenshooter scrot playerctl xbackflight pamixer --noconfirm

# docker
yay -S docker-bin docker-compose-bin --noconfirm
sudo systemctl enable docker.service
sudo usermod -aG docker $USER

# Fonts
yay -S ttf-dejavu ttf-liberation ttf-roboto ttf-ubuntu-font-family --noconfirm
yay -S nerd-fonts-complete --noconfirm 
fc-cache -vf

# Dev Tools
yay -S gradle maven jdk jdk8 nodejs spring-boot-cli httpie uuid traceroute tldr visual-studio-code-bin aws-cli --noconfirm
sudo npm install -g yarn yo @angular/cli backslide
sudo yarn global add generator-jhipster

# Password Tools
sudo npm install -g lesspass-cli
yay -S gopass --noconfirm

# Desktop Environment
ya -S polybar openbox obconf

# Configure VPN
pacman -S openvpn
cd /etc/openvpn 
wget https://downloads.nordcdn.com/configs/archives/servers/ovpn.zip
unzip ovpn.zip
sudo systemctl enable openvpn-client@nordvpn.service
sudo systemctl start openvpn-client@nordvpn.service

# Minucube And Google Cloud SDK
#yay -Sy libvirt qemu-headless ebtables dnsmasq google-cloud-sdk 
#sudo systemctl enable libvirtd.service
#sudo systemctl enable virtlogd.service
#yay -Sy docker-machine minikube-bin kubectl-bin docker-machine-driver-kvm2 
#newgrp libvirt
#usermod -a -G libvirt $(whoami)
#minikube start --vm-driver kvm2

# On network inactive error:
#sudo virsh net-list --all
#sudo virsh net-start minikube-net
#sudo virsh net-autostart minikube-net

### Troubleshooting - just recreate all configuration 
# minikube delete
# rm -rf ~/.minikube ~/.kube
# minikube start --vm-driver kvm2

