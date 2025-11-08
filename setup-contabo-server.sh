#!/bin/bash

# Setup script for Contabo server (Ubuntu 24.04)
# This script installs Docker, Caddy, and configures the firewall

set -e

echo "==> Setting up Contabo server for Bisan deployment..."

# Update system packages
echo "==> Updating system packages..."
sudo apt-get update
sudo apt-get upgrade -y

# Install Docker
echo "==> Installing Docker..."
if ! command -v docker &> /dev/null; then
    # Add Docker's official GPG key
    sudo apt-get install -y ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    # Add the repository to Apt sources
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Add current user to docker group
    sudo usermod -aG docker $USER
    
    echo "Docker installed successfully!"
else
    echo "Docker is already installed."
fi

# Install Caddy
echo "==> Installing Caddy..."
if ! command -v caddy &> /dev/null; then
    sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
    sudo apt update
    sudo apt install -y caddy
    
    echo "Caddy installed successfully!"
else
    echo "Caddy is already installed."
fi

# Configure firewall
echo "==> Configuring firewall..."
if command -v ufw &> /dev/null; then
    sudo ufw allow 22/tcp      # SSH
    sudo ufw allow 80/tcp      # HTTP
    sudo ufw allow 443/tcp     # HTTPS
    sudo ufw allow 7700/tcp    # Meilisearch (optional, only if needed externally)
    sudo ufw allow 8080/tcp    # Kamal proxy
    sudo ufw --force enable
    echo "Firewall configured successfully!"
else
    echo "UFW not available, skipping firewall configuration."
fi

# Create log directory for Caddy
echo "==> Creating Caddy log directory..."
sudo mkdir -p /var/log/caddy
sudo chown caddy:caddy /var/log/caddy

# Enable Caddy service
echo "==> Enabling Caddy service..."
sudo systemctl enable caddy

echo ""
echo "==> Setup complete!"
echo ""
echo "Next steps:"
echo "1. Copy your SSH public key: ssh-copy-id -i ~/bisan.pub root@185.185.82.142"
echo "2. Upload Caddyfile.contabo to server: scp Caddyfile.contabo root@185.185.82.142:/etc/caddy/Caddyfile"
echo "3. Restart Caddy: ssh root@185.185.82.142 'sudo systemctl restart caddy'"
echo "4. Deploy application: bin/kamal deploy -c config/deploy.contabo.yml"
echo ""
