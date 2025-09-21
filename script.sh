#!/bin/bash
set -e
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

if [ "$EUID" -eq 0 ]; then
    print_error "Please do not run this script as root. It will use sudo when needed."
    exit 1
fi

if [ ! -f /etc/os-release ]; then
    print_error "This script is designed for Ubuntu only."
    exit 1
fi

source /etc/os-release
if [ "$ID" != "ubuntu" ]; then
    print_error "This script is designed for Ubuntu only. Detected OS: $ID"
    exit 1
fi

print_status "Starting Docker installation on Ubuntu $VERSION_CODENAME"
print_status "Updating package list..."
sudo apt update -qq
print_status "Installing required dependencies..."
sudo apt install -y -qq ca-certificates curl gnupg > /dev/null
print_status "Adding Docker's GPG key..."
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
print_status "Setting up Docker repository..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
print_status "Updating package list with Docker repository..."
sudo apt update -qq
print_status "Installing Docker packages..."
sudo apt install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin > /dev/null
print_status "Adding current user to docker group..."
sudo usermod -aG docker $USER
print_status "Enabling Docker to start on boot..."
sudo systemctl enable docker.service > /dev/null
sudo systemctl enable containerd.service > /dev/null

if ! sudo systemctl is-active --quiet docker; then
    print_status "Starting Docker service..."
    sudo systemctl start docker
fi

print_status "Verifying Docker installation..."
if sudo docker --version; then
    print_status "Docker installed successfully!"
else
    print_error "Docker installation failed!"
    exit 1
fi

print_status "Testing Docker with hello-world container..."
if sudo docker run --rm hello-world | grep -q "Hello from Docker!"; then
    print_status "Docker test successful!"
else
    print_warning "Docker test failed, but installation may still be working."
fi

print_status "Installation complete!"
print_warning "IMPORTANT: Please log out and log back in for group changes to take effect."
print_warning "After logging back in, you can run 'docker run hello-world' without sudo."

echo ""
print_status "Docker version: $(sudo docker --version | cut -d' ' -f3 | cut -d',' -f1)"
print_status "Docker Compose version: $(sudo docker compose version | cut -d' ' -f4)"