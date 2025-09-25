#!/bin/bash

# Pre-download large dependencies for Docker build
# Run this script before building your Docker image

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

# Function to check if we're in screen/tmux
check_session() {
    if [[ -z "$STY" && -z "$TMUX" ]]; then
        print_message $YELLOW "WARNING: Not running in screen or tmux session."
        print_message $YELLOW "For SSH stability, consider running:"
        print_message $YELLOW "  screen -S precon_download && ./scripts/predownload-dependencies.sh"
        echo
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Function to format bytes
format_bytes() {
    local bytes=$1
    if [ $bytes -ge 1073741824 ]; then
        echo "$(($bytes / 1073741824))GB"
    elif [ $bytes -ge 1048576 ]; then
        echo "$(($bytes / 1048576))MB"
    elif [ $bytes -ge 1024 ]; then
        echo "$(($bytes / 1024))KB"
    else
        echo "${bytes}B"
    fi
}

# Function to download with retry and resume capability
download_with_retry() {
    local url=$1
    local output=$2
    local description=$3
    local max_attempts=5

    if [ -f "$output" ]; then
        local size=$(stat -c%s "$output" 2>/dev/null || echo 0)
        print_message $GREEN "✓ $description already downloaded ($(format_bytes $size))"
        return 0
    fi

    print_message $BLUE "Downloading $description..."
    print_message $YELLOW "URL: $url"

    for attempt in $(seq 1 $max_attempts); do
        print_message $BLUE "Attempt $attempt of $max_attempts..."

        # Use wget with resume (-c), timeout settings, and retry logic
        if wget -c \
            --timeout=30 \
            --tries=3 \
            --retry-connrefused \
            --waitretry=5 \
            --progress=bar:force:noscroll \
            --show-progress \
            "$url" -O "$output.tmp"; then

            mv "$output.tmp" "$output"
            local size=$(stat -c%s "$output" 2>/dev/null || echo 0)
            print_message $GREEN "✓ $description downloaded successfully! ($(format_bytes $size))"
            return 0
        else
            print_message $RED "Download attempt $attempt failed."
            if [ $attempt -lt $max_attempts ]; then
                print_message $YELLOW "Waiting 10 seconds before retry..."
                sleep 10
            fi
        fi
    done

    print_message $RED "ERROR: Failed to download $description after $max_attempts attempts."
    return 1
}

# Handle FSL installation
handle_fsl() {
    local fsl_cache="./cache/fsl.tar.gz"
    local fsl_installer="./cache/getfsl.sh"
    local host_fsl_dir="$HOME/fsl"

    if [ -f "$fsl_cache" ]; then
        local size=$(stat -c%s "$fsl_cache" 2>/dev/null || echo 0)
        print_message $GREEN "✓ FSL package already exists ($(format_bytes $size))"
        return 0
    fi

    # Check if FSL is already installed on host
    if [ -d "$host_fsl_dir" ]; then
        print_message $BLUE "Found existing FSL installation at $host_fsl_dir"
        print_message $BLUE "Packaging FSL for Docker use..."
        if tar -czf "$fsl_cache" -C "$(dirname "$host_fsl_dir")" "$(basename "$host_fsl_dir")" 2>/dev/null; then
            local size=$(stat -c%s "$fsl_cache" 2>/dev/null || echo 0)
            print_message $GREEN "✓ FSL packaged successfully! ($(format_bytes $size))"
            return 0
        else
            print_message $YELLOW "Failed to package existing FSL installation, will download fresh copy"
            rm -f "$fsl_cache"
        fi
    fi

    # Download installer if not exists
    if [ ! -f "$fsl_installer" ]; then
        print_message $BLUE "Downloading FSL installer..."
        wget -c --progress=bar:force:noscroll \
            "https://fsl.fmrib.ox.ac.uk/fsldownloads/fslconda/releases/getfsl.sh" \
            -O "$fsl_installer"
        chmod +x "$fsl_installer"
    fi

    # Run installer to temporary location
    print_message $BLUE "Installing FSL to temporary location for packaging..."
    local temp_fsl="/tmp/fsl_temp_$$"
    rm -rf "$temp_fsl"

    # Run installer non-interactively
    export FSLDIR="$temp_fsl"
    if bash "$fsl_installer" --skip_registration --no_self_update; then
        print_message $BLUE "Packaging FSL installation..."
        if tar -czf "$fsl_cache" -C "/tmp" "$(basename "$temp_fsl")"; then
            local size=$(stat -c%s "$fsl_cache" 2>/dev/null || echo 0)
            print_message $GREEN "✓ FSL installation packaged! ($(format_bytes $size))"
            rm -rf "$temp_fsl"
            return 0
        fi
    fi
    
    print_message $RED "ERROR: FSL installation/packaging failed"
    rm -rf "$temp_fsl"
    return 1
}

# Main function
main() {
    print_message $BLUE "=== Precon All Dependency Downloader ==="
    
    check_session
    
    print_message $BLUE "Creating cache directory..."
    mkdir -p ./cache
    
    # Check available disk space
    local available_gb=$(df -BG . | awk 'NR==2{gsub(/G/,"",$4); print $4}')
    if [[ $available_gb -lt 25 ]]; then
        print_message $YELLOW "WARNING: Low disk space (${available_gb}GB). Need ~20GB for downloads."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    print_message $BLUE "Available disk space: ${available_gb}GB"
    echo
    
    # Download dependencies
    print_message $BLUE "=== Downloading Dependencies ==="
    
    # Download FreeSurfer (largest file - ~9GB)
    download_with_retry \
        "https://surfer.nmr.mgh.harvard.edu/pub/dist/freesurfer/7.4.1/freesurfer-linux-centos7_x86_64-7.4.1.tar.gz" \
        "./cache/freesurfer.tar.gz" \
        "FreeSurfer 7.4.1"
    
    # Handle FSL installation
    print_message $BLUE "=== Processing FSL ==="
    handle_fsl
    
    # Download ANTs
    download_with_retry \
        "https://github.com/ANTsX/ANTs/releases/download/v2.6.2/ants-2.6.2-ubuntu-22.04-X64-gcc.zip" \
        "./cache/ants.zip" \
        "ANTs 2.6.2"
    
    # Download Miniconda
    download_with_retry \
        "https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh" \
        "./cache/miniconda.sh" \
        "Miniconda"
    
    echo
    print_message $GREEN "=== DOWNLOAD COMPLETE ==="
    print_message $BLUE "Cache contents:"
    ls -lh ./cache/
    echo
    local total_size=$(du -sh ./cache | cut -f1)
    print_message $GREEN "Total cache size: $total_size"
    
    echo
    print_message $BLUE "Next steps:"
    print_message $YELLOW "1. Run: ./scripts/precon_all_docker_cached.sh"
    print_message $YELLOW "2. Build: cd scripts && DOCKER_BUILDKIT=1 sudo docker-compose up --build"
    
    if [[ -n "$STY" || -n "$TMUX" ]]; then
        print_message $GREEN "You can safely disconnect from this session now."
    fi
}

# Run main function
main
