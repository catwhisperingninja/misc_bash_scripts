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

# Install Visual Studio Code
curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg
sudo install -o root -g root -m 644 microsoft.gpg /etc/apt/trusted.gpg.d/
echo "deb [arch=amd64] https://packages.microsoft.com/repos/vscode stable main" | sudo tee /etc/apt/sources.list.d/vscode.list
sudo apt update
sudo apt install -y code

# install fastfetch
sudo add-apt-repository -y ppa:zhangsongcui3371/fastfetch 
sudo apt install -y fastfetch

