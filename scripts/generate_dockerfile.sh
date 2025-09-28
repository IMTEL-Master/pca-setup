#!/bin/bash

# Unified Dockerfile generator that supports both cached and direct builds
# Usage: ./generate_dockerfile.sh [cached|direct]

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Default to cached build
BUILD_TYPE=${1:-cached}

# Validate build type
if [[ "$BUILD_TYPE" != "cached" && "$BUILD_TYPE" != "direct" ]]; then
    print_message $RED "ERROR: Build type must be 'cached' or 'direct'"
    print_message $BLUE "Usage: $0 [cached|direct]"
    exit 1
fi

print_message $BLUE "Generating ${BUILD_TYPE} build Dockerfile..."

# Check for cached build prerequisites
if [[ "$BUILD_TYPE" == "cached" ]]; then
    if [ ! -d "./cache" ]; then
        print_message $RED "ERROR: Cache directory not found!"
        print_message $YELLOW "Run: ./scripts/predownload-dependencies.sh first"
        exit 1
    fi
    
    REQUIRED_FILES=("freesurfer.tar.gz" "fsl.tar.gz" "ants.zip" "miniconda.sh")
    MISSING_FILES=()
    
    for file in "${REQUIRED_FILES[@]}"; do
        if [ ! -f "./cache/$file" ]; then
            MISSING_FILES+=("$file")
        fi
    done
    
    if [ ${#MISSING_FILES[@]} -gt 0 ]; then
        print_message $RED "ERROR: Missing cache files:"
        printf ' - %s\n' "${MISSING_FILES[@]}"
        exit 1
    fi
fi

# Check for FreeSurfer license
if [ ! -f "./license.txt" ]; then
    print_message $RED "ERROR: FreeSurfer license not found at ./license.txt"
    exit 1
fi

# Generate unified Dockerfile
cat > ./scripts/precon_all_dockerfile << EOF
FROM ubuntu:22.04

# Build arguments
ARG BUILD_TYPE=${BUILD_TYPE}

# Set non-interactive frontend
ENV DEBIAN_FRONTEND=noninteractive
ENV FS_LICENSE_ACCEPTED=Yes

# Install system dependencies including graphics libraries for Connectome Workbench
RUN apt-get update -qq && apt-get install -y -q --no-install-recommends \\
    wget curl unzip git ca-certificates \\
    build-essential tcsh bc tar libgomp1 \\
    python3-pip python3-dev \\
    libglu1-mesa-dev libgl1-mesa-dev libxmu6 libxi6 \\
    libglib2.0-0 libxext6 libsm6 libxrender1 libfontconfig1 \\
    && rm -rf /var/lib/apt/lists/*

# Create non-root user early
RUN useradd -m -s /bin/bash nonroot

EOF

# Add build-specific sections
if [[ "$BUILD_TYPE" == "cached" ]]; then
    cat >> ./scripts/precon_all_dockerfile << 'EOF'
# === CACHED BUILD SECTION ===
# Copy pre-downloaded files from host cache
COPY cache/freesurfer.tar.gz /tmp/
COPY cache/fsl.tar.gz /tmp/
COPY cache/ants.zip /tmp/
COPY cache/miniconda.sh /tmp/

# Install Miniconda from cache
RUN echo "Installing Miniconda from cache..." && \
    bash /tmp/miniconda.sh -b -p /opt/miniconda-latest && \
    rm /tmp/miniconda.sh

# Install FreeSurfer from cache
RUN echo "Installing FreeSurfer from cache..." && \
    mkdir -p /opt && \
    tar -xzf /tmp/freesurfer.tar.gz -C /opt && \
    rm /tmp/freesurfer.tar.gz

# Install FSL from cache
RUN echo "Installing FSL from cache..." && \
    mkdir -p /opt && \
    tar -xzf /tmp/fsl.tar.gz -C /opt && \
    rm /tmp/fsl.tar.gz && \
    if [ -d "/opt/fsl_temp" ]; then mv /opt/fsl_temp /opt/fsl; fi

# Patch FSL shebangs to use fslpython
RUN FSL_BIN_DIR=/opt/fsl/bin && \
    for f in $(grep -rl '^#!.*python' $FSL_BIN_DIR); do \
        sed -i '1s|.*|#!/opt/fsl/fslpython|' "$f"; \
    done

# Install ANTs from cache
RUN echo "Installing ANTs from cache..." && \
    mkdir -p /usr/local/sbin && \
    unzip -q /tmp/ants.zip -d /usr/local/sbin && \
    rm /tmp/ants.zip

EOF
else
    cat >> ./scripts/precon_all_dockerfile << 'EOF'
# === DIRECT BUILD SECTION ===
# Set working directory for downloads
WORKDIR /tmp

# Download and install Miniconda
RUN echo "Downloading Miniconda..." && \
    wget -q --show-progress --progress=bar:force:noscroll \
        "https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh" \
        -O miniconda.sh && \
    bash miniconda.sh -b -p /opt/miniconda-latest && \
    rm miniconda.sh

# Download and install FreeSurfer
RUN echo "Downloading FreeSurfer (this may take a while)..." && \
    wget -q --show-progress --progress=bar:force:noscroll \
        --retry-connrefused --waitretry=5 --read-timeout=20 --timeout=15 -t 5 \
        "https://surfer.nmr.mgh.harvard.edu/pub/dist/freesurfer/7.4.1/freesurfer-linux-centos7_x86_64-7.4.1.tar.gz" \
        -O freesurfer.tar.gz && \
    tar -xzf freesurfer.tar.gz -C /opt && \
    rm freesurfer.tar.gz

# Download and install FSL
RUN echo "Downloading and installing FSL..." && \
    wget -q --show-progress --progress=bar:force:noscroll \
        "https://fsl.fmrib.ox.ac.uk/fsldownloads/fslconda/releases/getfsl.sh" \
        -O getfsl.sh && \
    chmod +x getfsl.sh && \
    FSLDIR="/opt/fsl" ./getfsl.sh --skip_registration --no_self_update && \
    rm getfsl.sh

# Download and install ANTs
RUN echo "Downloading ANTs..." && \
    wget -q --show-progress --progress=bar:force:noscroll \
        "https://github.com/ANTsX/ANTs/releases/download/v2.6.2/ants-2.6.2-ubuntu-22.04-X64-gcc.zip" \
        -O ants.zip && \
    mkdir -p /usr/local/sbin && \
    unzip -q ants.zip -d /usr/local/sbin && \
    rm ants.zip

EOF
fi

# Add common post-installation section
cat >> ./scripts/precon_all_dockerfile << 'EOF'
# === COMMON POST-INSTALLATION ===

# Set conda PATH
ENV PATH=/opt/miniconda-latest/bin:$PATH

# Install conda packages (suppress ToS warnings on newer conda versions)
RUN conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main && \
    conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r

RUN conda config --set channel_priority flexible && \
    conda update -q conda && \
    conda install -y -c conda-forge mamba && \
    mamba install -y -c conda-forge nipype notebook && \
    conda clean -a

# Fix FSL compatibility for precon_all (handles modern FSL structure)
RUN echo "Creating fslpython compatibility symlink..." && \
    if [ -f "/opt/fsl/bin/python" ] && [ ! -f "/opt/fsl/fslpython" ]; then \
        ln -s /opt/fsl/bin/python /opt/fsl/fslpython; \
        chmod +x /opt/fsl/fslpython; \
        echo "Successfully created /opt/fsl/fslpython -> /opt/fsl/bin/python"; \
    else \
        echo "fslpython already exists or python not found in expected location"; \
        ls -la /opt/fsl/fslpython 2>/dev/null || echo "fslpython not found"; \
        ls -la /opt/fsl/bin/python 2>/dev/null || echo "python not found in /opt/fsl/bin/"; \
    fi

# Download and install Connectome Workbench
RUN echo "Downloading Connectome Workbench..." && \
    wget -q --show-progress --progress=bar:force:noscroll \
        "https://www.humanconnectome.org/storage/app/media/workbench/workbench-linux64-v2.1.0.zip" \
        -O /tmp/workbench.zip && \
    unzip -q /tmp/workbench.zip -d /opt/ && \
    rm /tmp/workbench.zip && \
    chmod +x /opt/workbench/bin_linux64/*

# Clone precon_all repository
RUN echo "Cloning precon_all repository..." && \
    git clone https://github.com/neurabenn/precon_all.git /opt/precon_all

# Copy FreeSurfer license
COPY license.txt /opt/freesurfer/license.txt

# Discover and set up correct paths
RUN echo "Discovering installation paths..." && \
    # Find FreeSurfer directory
    FREESURFER_DIR=$(find /opt -maxdepth 2 -name "freesurfer*" -type d | head -1) && \
    if [ -z "$FREESURFER_DIR" ]; then FREESURFER_DIR="/opt/freesurfer"; fi && \
    echo "FreeSurfer found at: $FREESURFER_DIR" && \
    # Find ANTs directory
    ANTS_BASE=$(find /usr/local/sbin -maxdepth 2 -name "ants-*" -type d | head -1) && \
    if [ -n "$ANTS_BASE" ]; then \
        ANTS_BIN_DIR="$ANTS_BASE/bin"; \
    else \
        ANTS_BIN_DIR="/usr/local/sbin/ants/bin"; \
    fi && \
    echo "ANTs bin found at: $ANTS_BIN_DIR" && \
    # Create symlinks for consistent paths
    ln -sf "$FREESURFER_DIR" /opt/freesurfer && \
    mkdir -p /usr/local/sbin/ants && \
    if [ "$ANTS_BIN_DIR" != "/usr/local/sbin/ants/bin" ]; then \
        ln -sf "$ANTS_BIN_DIR" /usr/local/sbin/ants/bin; \
    fi

# Set environment variables with discovered paths
ENV FSLDIR=/opt/fsl
ENV FREESURFER_HOME=/opt/freesurfer
ENV ANTSPATH=/usr/local/sbin/ants/bin
ENV PCP_PATH=/opt/precon_all
ENV PATH=/opt/miniconda-latest/bin:/opt/precon_all/bin:/opt/workbench/bin_linux64:/opt/freesurfer/bin:/usr/local/sbin/ants/bin:/opt/fsl/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Verify installations
RUN echo "Verifying installations..." && \
    python3 --version && \
    ls -la /opt/freesurfer/bin/mris_convert && \
    ls -la /usr/local/sbin/ants/bin/ && \
    ls -la /opt/fsl/bin/bet && \
    ls -la /opt/workbench/bin_linux64/wb_command && \
    ls -la /opt/precon_all/bin/surfing_safari.sh

# Set proper permissions
RUN chown -R nonroot:nonroot /opt/precon_all && \
    chmod +x /opt/precon_all/bin/*

RUN ln -s /opt/precon_all/bin /opt/precon_allbin

# Switch to non-root user
USER nonroot
WORKDIR /data

EOF

print_message $GREEN "✓ Unified Dockerfile created successfully!"
print_message $BLUE "Build type: ${BUILD_TYPE}"

if [[ "$BUILD_TYPE" == "cached" ]]; then
    print_message $BLUE "Cache contents:"
    ls -lh ./cache/ 2>/dev/null || echo "Cache directory empty"
fi

print_message $YELLOW "To build: cd scripts && docker-compose up --build"
