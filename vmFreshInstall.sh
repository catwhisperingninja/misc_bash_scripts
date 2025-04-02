#!/bin/bash

# Update the package list
sudo apt update

# Install curl
sudo apt install -y curl
sudo apt install -y net-tools
sudo apt install -y htop
sudo apt install -y git
sudo apt install -y openssh-server
sudo apt install -y openssh-client
sudo apt install -y bleachbit

# Install Visual Studio Code
curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg
sudo install -o root -g root -m 644 microsoft.gpg /etc/apt/trusted.gpg.d/
echo "deb [arch=amd64] https://packages.microsoft.com/repos/vscode stable main" | sudo tee /etc/apt/sources.list.d/vscode.list
sudo apt update
sudo apt install -y code

# install fastfetch
sudo add-apt-repository -y ppa:zhangsongcui3371/fastfetch 
sudo apt install -y fastfetch

# install brave-browser
curl -fsS https://dl.brave.com/install.sh | sh

# install Poetry
curl -sSL https://install.python-poetry.org | python3 -
poetry completions bash >> ~/.bash_completion


#prepare for Docker#
# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the Docker repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

# Install nvm version 0.40.1
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
source ~/.bashrc

# Install Powerline fonts
git clone https://github.com/powerline/fonts.git --depth=1
cd fonts
./install.sh

# Install zsh
sudo apt install -y zsh

# Make zsh the default shell
chsh -s $(which zsh)

# Install Powerlevel10k
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ~/powerlevel10k
echo 'source ~/powerlevel10k/powerlevel10k.zsh-theme' >>~/.zshrc

# Note: p10k configure will run automatically on first zsh startup
# The user will need to log out and log back in (or restart the system) 
# for the shell change to take effect
