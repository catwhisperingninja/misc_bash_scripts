#!/bin/bash

echo "=== VM Fresh Install Script ==="
echo "Installing essential development tools..."
echo ""

# Update the package list (CRITICAL)
echo "Updating package list..."
sudo apt update
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to update package list. Check your internet connection."
    exit 1
fi

# Install essential packages (CRITICAL)
echo "Installing essential packages..."
sudo apt install -y curl net-tools htop git openssh-server openssh-client bleachbit libfuse2 gh
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to install essential packages. Cannot continue."
    exit 1
fi

# Install Brave Browser (OPTIONAL)
curl -fsS https://dl.brave.com/install.sh | sh

# Install Visual Studio Code (OPTIONAL)
echo ""
echo "Installing Visual Studio Code..."
curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg
sudo install -o root -g root -m 644 microsoft.gpg /etc/apt/trusted.gpg.d/
echo "deb [arch=amd64] https://packages.microsoft.com/repos/vscode stable main" | sudo tee /etc/apt/sources.list.d/vscode.list
sudo apt update
sudo apt install -y code
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to install Visual Studio Code. Cannot continue."
    exit 1
fi
echo "✓ Visual Studio Code installed successfully"

# Install fastfetch (OPTIONAL)
echo ""
echo "Installing fastfetch..."
sudo add-apt-repository -y ppa:zhangsongcui3371/fastfetch 2>/dev/null && sudo apt install -y fastfetch
if [ $? -eq 0 ]; then
    echo "✓ fastfetch installed successfully"
else
    echo "⚠ Warning: fastfetch installation failed, skipping..."
fi

# Prepare for Docker (OPTIONAL)
echo ""
echo "Setting up Docker repository..."
{
    sudo apt-get update &&
    sudo apt-get install ca-certificates curl &&
    sudo install -m 0755 -d /etc/apt/keyrings &&
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc &&
    sudo chmod a+r /etc/apt/keyrings/docker.asc &&
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null &&
    sudo apt-get update
} 2>/dev/null
if [ $? -eq 0 ]; then
    echo "✓ Docker repository setup completed"
else
    echo "⚠ Warning: Docker repository setup failed, skipping..."
fi

# Install Powerline fonts (OPTIONAL)
echo ""
echo "Installing Powerline fonts..."
{
    git clone https://github.com/powerline/fonts.git --depth=1 2>/dev/null &&
    cd fonts &&
    ./install.sh 2>/dev/null &&
    cd ..
} 2>/dev/null
if [ $? -eq 0 ]; then
    echo "✓ Powerline fonts installed successfully"
else
    echo "⚠ Warning: Powerline fonts installation failed, skipping..."
fi

# Install zsh (OPTIONAL)
echo ""
echo "Installing zsh shell..."
sudo apt install -y zsh 2>/dev/null
if [ $? -eq 0 ]; then
    echo "✓ zsh installed successfully"
else
    echo "⚠ Warning: zsh installation failed, skipping..."
fi

# Install Poetry (CRITICAL)
echo ""
echo "Installing Poetry package manager..."
curl -sSL https://install.python-poetry.org | python3 -
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to install Poetry. Cannot continue."
    exit 1
fi

# Install Powerlevel10k (OPTIONAL)
echo ""
echo "Installing Powerlevel10k theme..."
{
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ~/powerlevel10k 2>/dev/null &&
    echo 'source ~/powerlevel10k/powerlevel10k.zsh-theme' >>~/.zshrc
} 2>/dev/null
if [ $? -eq 0 ]; then
    echo "✓ Powerlevel10k installed successfully"
else
    echo "⚠ Warning: Powerlevel10k installation failed, skipping..."
fi

# Note: p10k configure will run automatically on first zsh startup
# The user will need to log out and log back in (or restart the system) 
# for the shell change to take effect

# Create a new ssh key (CRITICAL)
echo ""
echo "=== SSH Key Generation ==="
echo "We'll now create an SSH key for secure authentication."
echo ""
echo "About hostnames vs IP addresses:"
echo "- Your hostname is the human-readable name of your computer: $(hostname)"
echo "- This is essentially the same as your IP address, but much easier to remember"
echo "- It helps identify which machine this SSH key belongs to"
echo ""
echo "SSH Key Naming:"
echo "You can customize your SSH key name to make it more meaningful."
echo "For example, append '-GH' for GitHub keys, '-GL' for GitLab, etc."
echo "Default format will be: $USER@[hostname-or-identifier]"
echo ""

# Get custom hostname/identifier
echo "Current hostname: $(hostname)"
read -p "Enter a custom identifier for this key (or press Enter to use '$(hostname)'): " CUSTOM_HOSTNAME
HOSTNAME_PART=${CUSTOM_HOSTNAME:-$(hostname)}

# Get full SSH key name
DEFAULT_KEY_NAME="$USER@$HOSTNAME_PART"
echo ""
read -p "Enter full SSH key name (or press Enter for '$DEFAULT_KEY_NAME'): " SSH_KEY_NAME
SSH_KEY_NAME=${SSH_KEY_NAME:-$DEFAULT_KEY_NAME}

# Ensure .ssh directory exists
mkdir -p ~/.ssh
chmod 700 ~/.ssh

echo ""
echo "Creating SSH key: $SSH_KEY_NAME"
ssh-keygen -t ed25519 -C "$SSH_KEY_NAME" -f ~/.ssh/$SSH_KEY_NAME -N ""
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create SSH key. Cannot continue."
    exit 1
fi

# Add the new ssh key to the ssh agent
echo "Adding SSH key to ssh-agent..."
ssh-add ~/.ssh/$SSH_KEY_NAME
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to add SSH key to ssh-agent. Cannot continue."
    exit 1
fi
echo "✓ SSH key created and added successfully!"

echo ""
echo "=== Installation Complete ==="
echo "Your development environment is ready!"
echo ""
echo "Next steps:"
echo "1. Log out and log back in (or restart) for shell changes to take effect"
echo "2. Your SSH public key is located at: ~/.ssh/$SSH_KEY_NAME.pub"
echo "3. Add this public key to your Git hosting service (GitHub, GitLab, etc.)"
echo ""
echo "To display your public key, run:"
echo "cat ~/.ssh/$SSH_KEY_NAME.pub"

# Install nvm version 0.40.3 (CRITICAL)
echo ""
echo "Installing nvm (Node Version Manager)..."
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to install nvm. Cannot continue."
    exit 1
fi
source ~/.bashrc
echo "✓ nvm installed successfully"

cd ~
export PATH="~/.local/bin:$PATH"
echo "Let's see how that went..."
poetry --version
echo "If you see a Poetry version and not an error, cool!"

# Try to set up poetry completions (optional part)
mkdir -p ~/.zfunc 2>/dev/null
poetry completions zsh > ~/.zfunc/_poetry 2>/dev/null || echo "⚠ Warning: Could not set up Poetry zsh completions"

echo "Setting zsh as default shell..."
chsh -s $(which zsh)