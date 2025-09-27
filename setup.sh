#!/bin/bash

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Check system requirements
check_system() {
    print_message $BLUE "=== System Requirements Check ==="
    
    # OS Check
    if [[ "$OSTYPE" != "linux-gnu"* ]]; then
        print_message $RED "ERROR: This script currently only supports Linux."
        exit 1
    fi
    
    # Architecture Check
    ARCH=$(uname -m)
    if [[ "$ARCH" != "x86_64" ]]; then
        print_message $RED "ERROR: Currently only x86_64 architecture is supported."
        print_message $YELLOW "ARM64 support is planned for future releases."
        exit 1
    fi
    
    print_message $GREEN "✓ OS: Linux (${OSTYPE})"
    print_message $GREEN "✓ Architecture: ${ARCH}"
    
    # Memory Check
    MEM_GB=$(free -g | awk '/^Mem:/{print $2}')
    if [[ $MEM_GB -lt 16 ]]; then
        print_message $YELLOW "WARNING: Less than 16GB RAM detected (${MEM_GB}GB). Build may fail or be slow."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    # Disk Space Check
    DISK_GB=$(df -BG . | awk 'NR==2{gsub(/G/,"",$4); print $4}')
    if [[ $DISK_GB -lt 30 ]]; then
        print_message $YELLOW "WARNING: Less than 30GB free space (${DISK_GB}GB). Build may fail."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    print_message $GREEN "✓ Memory: ${MEM_GB}GB RAM"
    print_message $GREEN "✓ Disk Space: ${DISK_GB}GB available"
}

# Check FreeSurfer license
check_license() {
    if [ ! -f "./license.txt" ]; then
        print_message $RED "ERROR: FreeSurfer license not found at ./license.txt"
        print_message $YELLOW "Please obtain a FreeSurfer license and place it in the project root."
        print_message $BLUE "Register at: https://surfer.nmr.mgh.harvard.edu/registration.html"
        exit 1
    fi
    print_message $GREEN "✓ FreeSurfer license found"
}

# Check sudo privileges
check_sudo() {
    if ! sudo -n true 2>/dev/null; then
        print_message $BLUE "Docker requires sudo privileges. Please enter your password:"
        sudo -v
        if [[ $? -ne 0 ]]; then
            print_message $RED "ERROR: Cannot obtain sudo privileges."
            exit 1
        fi
    fi
    print_message $GREEN "✓ Sudo privileges confirmed"
}

# Check Docker installation
check_docker() {
    if ! command -v docker &> /dev/null; then
        print_message $RED "ERROR: Docker is not installed."
        print_message $YELLOW "Please install Docker first: https://docs.docker.com/engine/install/"
        exit 1
    fi
    
    # Check if Docker daemon is accessible
    if ! sudo docker info &> /dev/null; then
        print_message $RED "ERROR: Docker daemon is not running or accessible."
        
        # Try to determine the Docker service name
        if systemctl list-unit-files | grep -q "docker.service"; then
            print_message $YELLOW "Try: sudo systemctl start docker"
        elif systemctl list-unit-files | grep -q "docker.socket"; then
            print_message $YELLOW "Try: sudo systemctl start docker.socket"
        elif command -v snap &> /dev/null && snap list | grep -q docker; then
            print_message $YELLOW "Docker appears to be installed via Snap."
            print_message $YELLOW "Try: sudo snap start docker"
        else
            print_message $YELLOW "Please start the Docker daemon manually."
        fi
        exit 1
    fi
    
    # Check if user can access Docker without sudo
    if docker info &> /dev/null 2>&1; then
        print_message $GREEN "✓ Docker is installed and accessible"
        DOCKER_NEEDS_SUDO=false
    else
        print_message $YELLOW "⚠ Docker requires sudo (user not in docker group)"
        print_message $BLUE "To fix this permanently:"
        print_message $BLUE "  sudo usermod -aG docker $USER"
        print_message $BLUE "  newgrp docker  # or logout/login"
        print_message $GREEN "✓ Docker is accessible via sudo"
        DOCKER_NEEDS_SUDO=true
    fi
}

# Check session type for stability
check_session() {
    # Check both current environment and parent process environment for screen/tmux
    local in_screen=false
    local in_tmux=false
    
    # Check current environment variables
    if [[ -n "$STY" ]] || [[ -n "$SCREEN_SESSION" ]]; then
        in_screen=true
    fi
    
    if [[ -n "$TMUX" ]] || [[ -n "$TMUX_SESSION" ]]; then
        in_tmux=true
    fi
    
    # Check if parent process is screen or tmux (for sudo case)
    if ! $in_screen && ! $in_tmux; then
        local parent_processes=$(ps -o comm= -p $PPID 2>/dev/null | head -1)
        if [[ "$parent_processes" =~ screen|tmux ]]; then
            in_screen=true
        fi
        
        # Also check the process tree
        if pstree -p $$ 2>/dev/null | grep -q -E "(screen|tmux)"; then
            in_screen=true
        fi
    fi
    
    if ! $in_screen && ! $in_tmux; then
        print_message $YELLOW "WARNING: Not running in screen or tmux session."
        print_message $YELLOW "For SSH stability, consider running:"
        print_message $YELLOW "  screen -S precon_setup && ./setup.sh"
        echo
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Global variable to track sudo requirement
DOCKER_NEEDS_SUDO=true

# Main setup function
main() {
    print_message $BLUE "=== Precon All Docker Setup ==="
    echo
    
    # Run all checks
    check_system
    check_license
    check_docker
    check_sudo
    check_session
    
    echo
    print_message $BLUE "=== Build Configuration ==="
    print_message $YELLOW "This Docker build process may take several hours and requires:"
    print_message $YELLOW "• 20GB+ disk space for caching large dependencies"
    print_message $YELLOW "• Stable internet connection"
    print_message $YELLOW "• FreeSurfer, FSL, ANTs (~15GB downloads)"
    echo
    
    print_message $BLUE "Choose build method:"
    echo "1) CACHED BUILD (Recommended): Pre-download dependencies, then build"
    echo "2) DIRECT BUILD: Build directly without caching (less reliable)"
    echo
    
    while true; do
        read -p "Enter choice (1 or 2): " -n 1 -r
        echo
        case $REPLY in
            1)
                BUILD_METHOD="cached"
                break
                ;;
            2)
                BUILD_METHOD="direct"
                break
                ;;
            *)
                print_message $RED "Please enter 1 or 2"
                ;;
        esac
    done
    
    echo
    print_message $BLUE "=== Starting Build Process ==="
    
    if [[ "$BUILD_METHOD" == "cached" ]]; then
        print_message $BLUE "Step 1/3: Pre-downloading dependencies..."
        if [ -x "./scripts/predownload-dependencies.sh" ]; then
            ./scripts/predownload-dependencies.sh
        else
            print_message $RED "ERROR: predownload-dependencies.sh not found or not executable"
            exit 1
        fi
        
        print_message $BLUE "Step 2/3: Generating cached Dockerfile..."
        ./scripts/generate_dockerfile.sh cached
        
        print_message $BLUE "Step 3/3: Building Docker image..."
    else
        print_message $BLUE "Step 1/2: Generating direct build Dockerfile..."
        ./scripts/generate_dockerfile.sh direct
        
        print_message $BLUE "Step 2/2: Building Docker image..."
    fi
    
    # Build using docker-compose
    cd scripts/
    if [[ "$DOCKER_NEEDS_SUDO" == "true" ]]; then
        print_message $BLUE "Building with sudo..."
        DOCKER_BUILDKIT=1 sudo docker-compose build precon_all
    else
        print_message $BLUE "Building without sudo..."
        DOCKER_BUILDKIT=1 docker-compose build precon_all
    fi
    
    echo
    print_message $GREEN "=== Build Complete! ==="
    print_message $GREEN "Docker container 'precon_all_container' is ready to use."
    
    # Provide usage instructions
    print_message $BLUE "=== Usage Instructions ==="
    if [[ "$DOCKER_NEEDS_SUDO" == "true" ]]; then
        print_message $BLUE "To run interactively:"
        print_message $BLUE "  cd scripts && sudo docker-compose run precon_all"
        print_message $BLUE ""
        print_message $BLUE "To run precon_all on your data:"
        print_message $BLUE "  sudo docker-compose run precon_all surfing_safari.sh -i my_T1.nii.gz -r precon_all -a masks"
    else
        print_message $BLUE "To run interactively:"
        print_message $BLUE "  cd scripts && docker-compose run precon_all"
        print_message $BLUE ""
        print_message $BLUE "To run precon_all on your data:"
        print_message $BLUE "  docker-compose run precon_all surfing_safari.sh -i my_T1.nii.gz -r precon_all -a masks"
    fi
    
    print_message $BLUE ""
    print_message $BLUE "Data directories:"
    print_message $BLUE "  • Input data: ../data/"
    print_message $BLUE "  • Output: ../output/"
    print_message $BLUE "  • FreeSurfer license: ../license.txt"
}

# Run main function
main
