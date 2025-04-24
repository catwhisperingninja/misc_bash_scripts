#!/bin/bash

# Update the package list
sudo apt update

sudo apt install -y htop
sudo apt install -y bleachbit
sudo apt install -y kitty
sudo apt install -y veracrypt
sudo apt install -y kleopatra
sudo apt install -y keepassxc
sudo apt install -y testdisk
sudo apt install -y net-tools
# install fastfetch
sudo add-apt-repository -y ppa:zhangsongcui3371/fastfetch
sudo apt install -y fastfetch

# install brave-browser
curl -fsS https://dl.brave.com/install.sh | sh

# Install Powerline fonts
git clone https://github.com/powerline/fonts.git --depth=1
cd fonts
./install.sh

# Install Powerlevel10k
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ~/powerlevel10k
echo 'source ~/powerlevel10k/powerlevel10k.zsh-theme' >>~/.zshrc

# Note: zsh now installed on Kali by default