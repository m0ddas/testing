#!/bin/bash

DOTFILES_DIR="$HOME/.dotfiles"
PACKAGES_FILE="$DOTFILES_DIR/blueprint/template/packages.txt"

link_item() {
    local src="$DOTFILES_DIR/$1"
    local dest="$2"
    mkdir -p "$(dirname "$dest")"
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        rm -rf "$dest"
    fi
    ln -s "$src" "$dest"
    echo "  [OK] Länkad: $1 -> $2"
}

install_yay() {
    if ! command -v yay &> /dev/null; then
        echo "--- Installerar yay (AUR helper) ---"
        git clone https://aur.archlinux.org/yay-bin.git /tmp/yay-bin
        cd /tmp/yay-bin || exit
        makepkg -si --noconfirm
        cd - || exit
        rm -rf /tmp/yay-bin
    else
        echo "--- yay finns redan, hoppar över ---"
    fi
}

sudo -v
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

install_yay

yay -S --needed --noconfirm swayfx

if [ -f "$PACKAGES_FILE" ]; then
    yay -S --needed --noconfirm - < "$PACKAGES_FILE"
fi


link_item "gpg-agent.conf" "$HOME/.gnupg/gpg-agent.conf"

config_items=(
    "alacritty" "btop" "fish" "gtk-3.0" "gtk-4.0" "mc"
    "nvim" "sway" "ulauncher" "user-dirs.dirs" "user-dirs.locale"
    "wallpaper" "waybar" "yazi"
)

for item in "${config_items[@]}"; do
    link_item "$item" "$HOME/.config/$item"
done

chmod 700 ~/.gnupg
chmod 600 ~/.gnupg/* 2>/dev/null

if [ "$SHELL" != "/usr/bin/fish" ]; then
    echo "--- Byter standardskal till Fish ---"
    sudo chsh -s /usr/bin/fish "$USER"
fi

sudo nvim /etc/mkinitcpio.conf
sudo mkinitcpio -P

sudo systemctl enable lightdm.service
systemctl --user enable pipewire.socket
systemctl --user enable pipewire-pulse.socket
systemctl --user enable pipewire.service
systemctl --user enable pipewire-pulse.service
systemctl --user enable wireplumber.service
systemctl --user enable gnome-keyring-daemon.socket
systemctl --user enable gnome-keyring-daemon.service
systemctl --user enable p11-kit-server.socket
systemctl --user enable xdg-user-dirs.service

if grep -q "GenuineIntel" /proc/cpuinfo; then
    echo 'output eDP-1 mode 1920x1080@60hz' > ~/.config/sway/outputs.conf
else
    echo 'output DP-2 mode 2560x1440@170hz' > ~/.config/sway/outputs.conf
fi

reboot
