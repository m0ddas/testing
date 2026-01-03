#!/bin/bash
set -eo pipefail

UCODE=""
GPU_PKGS="mesa lib32-mesa" # Mesa räcker för VA-API nu
KERNEL_PARAMS="quiet splash"

if grep -q "AuthenticAMD" /proc/cpuinfo; then
    UCODE="amd-ucode"
    # AMD Max-Performance Stack
    GPU_PKGS="$GPU_PKGS vulkan-radeon lib32-vulkan-radeon rocm-opencl-runtime"
    MODULE_NAME="amdgpu"

elif grep -q "GenuineIntel" /proc/cpuinfo; then
    UCODE="intel-ucode"
    # Intel 13th Gen Optimering
    GPU_PKGS="$GPU_PKGS vulkan-intel lib32-vulkan-intel intel-media-driver intel-compute-runtime"
    MODULE_NAME="i915"
    # Aktivera GuC/HuC för media-prestanda på 13th gen
    KERNEL_PARAMS="$KERNEL_PARAMS i915.enable_guc=3"
fi

if [ ! -d "/root/.dotfiles" ]; then
    echo "FEL: /root/.dotfiles hittades inte! Klona ditt repo först."
    exit 1
fi

sed -i 's/^#Color/Color/' /etc/pacman.conf
sed -i 's/^ParallelDownloads = 5/ParallelDownloads = 10/' /etc/pacman.conf
sed -i '/#\[multilib\]/,/#Include = \/etc\/pacman.d\/mirrorlist/ s/^#//' /etc/pacman.conf
pacman -Syy

mkfs.vfat -F32 /dev/nvme0n1p1
mkswap /dev/nvme0n1p2
swapon /dev/nvme0n1p2
mkfs.ext4 -F /dev/nvme0n1p3

mount /dev/nvme0n1p3 /mnt
mkdir -p /mnt/boot
mount -o uid=0,gid=0,fmask=0077,dmask=0077 /dev/nvme0n1p1 /mnt/boot

pacstrap -K /mnt base base-devel linux linux-firmware $UCODE $GPU_PKGS neovim efibootmgr networkmanager bluez git terminus-font

echo "Ange lösenord för root och modda:"
read -s USER_PASS

arch-chroot /mnt /bin/bash <<EOF
set -e
ln -sf /usr/share/zoneinfo/Europe/Stockholm /etc/localtime
hwclock --systohc

sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/^#sv_SE.UTF-8 UTF-8/sv_SE.UTF-8 UTF-8/' /etc/locale.gen
locale-gen

echo "LANG=C.UTF-8" > /etc/locale.conf
{
  echo "LC_NUMERIC=sv_SE.UTF-8"
  echo "LC_TIME=sv_SE.UTF-8"
  echo "LC_MONETARY=sv_SE.UTF-8"
  echo "LC_PAPER=sv_SE.UTF-8"
  echo "LC_MEASUREMENT=sv_SE.UTF-8"
} >> /etc/locale.conf

echo "KEYMAP=sv-latin1" > /etc/vconsole.conf
echo "FONT=ter-124n" >> /etc/vconsole.conf

echo "arch-desktop" > /etc/hostname
{
  echo "127.0.0.1   localhost"
  echo "::1         localhost"
  echo "127.0.1.1   arch-desktop.localdomain arch-desktop"
} > /etc/hosts

sed -i 's/^#Color/Color/' /etc/pacman.conf
sed -i 's/^ParallelDownloads = 5/ParallelDownloads = 10/' /etc/pacman.conf
sed -i '/#\[multilib\]/,/#Include = \/etc\/pacman.d\/mirrorlist/ s/^#//' /etc/pacman.conf

if [ -n "$MODULE_NAME" ]; then
    sed -i "s/^MODULES=(/MODULES=($MODULE_NAME /" /etc/mkinitcpio.conf
    mkinitcpio -P
fi

bootctl install
UUID=\$(blkid -s UUID -o value /dev/nvme0n1p3)
{
  echo "title Arch Linux"
  echo "linux /vmlinuz-linux"
  echo "initrd /$UCODE.img"
  echo "initrd /initramfs-linux.img"
  echo "options root=UUID=\$UUID rw $KERNEL_PARAMS"
} > /boot/loader/entries/arch.conf
echo "default arch.conf" > /boot/loader/loader.conf

useradd -m -G wheel modda
echo "root:$USER_PASS" | chpasswd
echo "modda:$USER_PASS" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

pacman -Syy
systemctl enable NetworkManager.service
systemctl enable NetworkManager-dispatcher.service
systemctl enable NetworkManager-wait-online.service
systemctl enable bluetooth.service
EOF

genfstab -U /mnt >> /mnt/etc/fstab

mv /root/.dotfiles /mnt/home/modda/
chown -R modda:modda /mnt/home/modda/.dotfiles
