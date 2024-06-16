#!/bin/bash

# Update the package list
sudo apt update

# Install curl
sudo apt install -y curl
sudo apt install -y net-tools
sudo apt install -y multiverse
# sudo apt install -y ubuntu-restricted-extras
sudo apt install -y libfuse2

# Install Visual Studio Code
curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg
sudo install -o root -g root -m 644 microsoft.gpg /etc/apt/trusted.gpg.d/
echo "deb [arch=amd64] https://packages.microsoft.com/repos/vscode stable main" | sudo tee /etc/apt/sources.list.d/vscode.list
sudo apt update
sudo apt install -y code

# Install Node JS via NVM (version is hardcoded)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
source ~/.bashrc
nvm list-remote
nvm install lts/iron
node -v



