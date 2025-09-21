#!/bin/bash

set -euo pipefail

# Configuration
readonly SCRIPT_NAME="auto-docker-installer"
readonly SCRIPT_VERSION="2.0"
readonly DOCKER_VERSION="latest"
readonly MIN_UBUNTU_VERSION="20.04"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_debug() { echo -e "${CYAN}[DEBUG]${NC} $1"; }
check_sudo() {
    if [[ $EUID -eq 0 ]]; then
        log_error "This script should not be run as root. It will use sudo when needed."
        exit 1
    fi
    
    if ! sudo -n true 2>/dev/null; then
        log_info "Please enter your sudo password when prompted"
        if ! sudo -v; then
            log_error "Sudo authentication failed"
            exit 1
        fi
    fi
}

check_ubuntu_version()
{
    if [[ ! -f /etc/os-release ]]; then
        log_error "This script is designed for Ubuntu only"
        exit 1
    fi

    source /etc/os-release
    if [[ "$ID" != "ubuntu" ]]; then
        log_error "This script is designed for Ubuntu only. Detected OS: $ID"
        exit 1
    fi

    local current_version=$(echo "$VERSION_ID" | cut -d'.' -f1-2)
    local required_version=$(echo "$MIN_UBUNTU_VERSION" | cut -d'.' -f1-2)

    if (( $(echo "$current_version < $required_version" | bc -l) )); then
        log_error "Ubuntu $VERSION_ID is not supported. Minimum required: $MIN_UBUNTU_VERSION"
        exit 1
    fi

    log_info "Detected Ubuntu $VERSION_ID ($VERSION_CODENAME)"
}

check_docker_installed() {
    if command -v docker &>/dev/null; then
        local docker_ver=$(docker --version | cut -d' ' -f3 | tr -d ',')
        log_warning "Docker is already installed: version $docker_ver"
        
        read -p "Do you want to reinstall Docker? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Installation cancelled"
            exit 0
        fi
        
        log_info "Proceeding with reinstallation..."
    fi
}

install_dependencies()
{
    log_info "Installing required dependencies..."
    
    local dependencies=(
        "ca-certificates"
        "curl"
        "gnupg"
        "lsb-release"
        "software-properties-common"
        "apt-transport-https"
    )
    
    if ! sudo apt update -qq; then
        log_error "Failed to update package lists"
        exit 1
    fi
    
    if ! sudo apt install -y -qq "${dependencies[@]}" > /dev/null; then
        log_error "Failed to install dependencies"
        exit 1
    fi
}
add_docker_repo()
{
    log_info "Setting up Docker repository..."
    sudo install -m 0755 -d /etc/apt/keyrings
    if ! curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
         sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg; then
        log_error "Failed to add Docker GPG key"
        exit 1
    fi
    
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    local arch=$(dpkg --print-architecture)
    local codename=$(. /etc/os-release && echo "$VERSION_CODENAME")
    
    echo "deb [arch=$arch signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $codename stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    if ! sudo apt update -qq; then
        log_error "Failed to update package lists with Docker repository"
        exit 1
    fi
}

install_docker_packages()
{
    log_info "Installing Docker packages..."
    
    local packages=(
        "docker-ce"
        "docker-ce-cli"
        "containerd.io"
        "docker-buildx-plugin"
        "docker-compose-plugin"
    )
    if [[ "$DOCKER_VERSION" != "latest" ]]; then
        packages=("${packages[@]/%/=${DOCKER_VERSION}}")
    fi
    
    if ! sudo apt install -y -qq "${packages[@]}" > /dev/null; then
        log_error "Failed to install Docker packages"
        exit 1
    fi
}

configure_docker()
{
    log_info "Configuring Docker..."
    if ! sudo usermod -aG docker "$USER"; then
        log_error "Failed to add user to docker group"
        exit 1
    fi
    if ! sudo systemctl enable docker.service containerd.service > /dev/null; then
        log_error "Failed to enable Docker services"
        exit 1
    fi
    
    if ! sudo systemctl start docker; then
        log_error "Failed to start Docker service"
        exit 1
    fi
    mkdir -p ~/.docker
    sudo chown "$USER:$USER" ~/.docker -R
}
verify_installation()
{
    log_info "Verifying installation..."

    if ! docker --version &>/dev/null; then
        log_error "Docker command not found"
        return 1
    fi
    
    local docker_ver=$(docker --version | cut -d' ' -f3 | tr -d ',')
    local compose_ver=$(docker compose version | cut -d' ' -f4 | tr -d 'v')
    
    log_success "Docker installed: version $docker_ver"
    log_success "Docker Compose installed: version $compose_ver"
    log_info "Testing Docker with hello-world container..."
    if docker run --rm hello-world | grep -q "Hello from Docker!"; then
        log_success "Docker test successful!"
    else
        log_warning "Docker test completed but output verification failed"
    fi
}

show_post_install_message()
{
    echo
    echo "================================================================"
    echo " Docker Installation Complete!"
    echo "================================================================"
    echo
    echo " Installed:"
    echo "   • Docker Engine: $(docker --version | cut -d' ' -f3)"
    echo "   • Docker Compose: $(docker compose version | cut -d' ' -f4)"
    echo
    echo "  Important:"
    echo "   • You must LOG OUT and LOG BACK IN for group changes to take effect"
    echo "   • After that, you can run Docker commands without sudo"
    echo
    echo " Quick test after logging back in:"
    echo "   docker run hello-world"
    echo "   docker --version"
    echo
    echo " Next steps:"
    echo "   • Learn Docker: https://docs.docker.com/get-started/"
    echo "   • Find images: https://hub.docker.com/"
    echo
    echo " Tip: Run 'docker info' to see detailed Docker information"
    echo "================================================================"
}

cleanup()
{
    log_info "Cleaning up temporary files..."
}
main()
{
    echo
    log_info "Starting $SCRIPT_NAME v$SCRIPT_VERSION"
    log_info "Target Docker version: $DOCKER_VERSION"
    echo
    trap cleanup EXIT
    check_sudo
    check_ubuntu_version
    check_docker_installed
    install_dependencies
    add_docker_repo
    install_docker_packages
    configure_docker
    verify_installation
    show_post_install_message
    
    log_success "Installation completed successfully!"
}

handle_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--version)
                echo "$SCRIPT_NAME v$SCRIPT_VERSION"
                exit 0
                ;;
            -h|--help)
                echo "Usage: $0 [OPTIONS]"
                echo
                echo "Options:"
                echo "  -v, --version    Show script version"
                echo "  -h, --help       Show this help message"
                echo "  --dry-run        Simulate installation without making changes"
                echo
                echo "This script automates Docker installation on Ubuntu systems."
                exit 0
                ;;
            --dry-run)
                log_info "Dry run mode - no changes will be made"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use -h for help"
                exit 1
                ;;
        esac
        shift
    done
}

handle_arguments "$@"
main