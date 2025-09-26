#!/bin/bash

# Generate Dockerfile that uses pre-downloaded cache
# This script creates a Dockerfile that uses cached dependencies

set -e  # Exit on error

echo "Generating cached build Dockerfile..."

# Check if cache directory exists
if [ ! -d "./cache" ]; then
    echo "ERROR: Cache directory not found!"
    echo "Please run './scripts/predownload-dependencies.sh' first."
    exit 1
fi

# Check for required cache files
REQUIRED_FILES=("freesurfer.tar.gz" "fsl.tar.gz" "ants.zip" "miniconda.sh")
MISSING_FILES=()

for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "./cache/$file" ]; then
        MISSING_FILES+=("$file")
    fi
done

if [ ${#MISSING_FILES[@]} -gt 0 ]; then
    echo "ERROR: Missing cache files:"
    printf ' - %s\n' "${MISSING_FILES[@]}"
    echo "Please run './scripts/predownload-dependencies.sh' first."
    exit 1
fi

cat <<'EOF' > ./scripts/precon_all_dockerfile
FROM debian:bullseye-slim

# Set non-interactive frontend
ENV DEBIAN_FRONTEND=noninteractive
ENV FS_LICENSE_ACCEPTED=Yes

# Install system dependencies
RUN apt-get update -qq && apt-get install -y -q --no-install-recommends \
    wget curl unzip git ca-certificates \
    build-essential tcsh bc tar libgomp1 \
    python3-pip python3-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy pre-downloaded files from host cache
COPY ../cache/freesurfer.tar.gz /tmp/
COPY ../cache/fsl.tar.gz /tmp/
COPY ../cache/ants.zip /tmp/
COPY ../cache/miniconda.sh /tmp/

# Install Miniconda from cache
RUN echo "Installing Miniconda from cache..." && \
    bash /tmp/miniconda.sh -b -p /opt/miniconda-latest && \
    rm /tmp/miniconda.sh

# Set conda PATH and install packages
ENV PATH=/opt/miniconda-latest/bin:$PATH

RUN conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main && \
    conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r

RUN conda update -q conda && \
    conda install -y -c conda-forge mamba && \
    mamba install -y -c conda-forge nipype notebook && \
    conda clean -a

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
    # Handle different possible FSL directory structures
    if [ -d "/opt/fsl_temp" ]; then mv /opt/fsl_temp /opt/fsl; fi

# Install ANTs from cache
RUN echo "Installing ANTs from cache..." && \
    mkdir -p /usr/local/sbin && \
    unzip -q /tmp/ants.zip -d /usr/local/sbin && \
    rm /tmp/ants.zip

# Download and install Connectome Workbench (small download)
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

# Create non-root user
RUN useradd -m -s /bin/bash nonroot

# Set environment variables
ENV FSLDIR=/opt/fsl
ENV FREESURFER_HOME=/opt/freesurfer
ENV ANTSPATH=/usr/local/sbin/ants/bin
ENV PCP_PATH=/opt/precon_all
ENV PATH=/opt/miniconda-latest/bin:$ANTSPATH:$FSLDIR/bin:$FREESURFER_HOME/bin:$PCP_PATH/bin:/opt/workbench/bin_linux64:$PATH

# Copy data into the container (if exists)
# Note: This step is optional - data directory will be mounted via docker-compose
# COPY ../data /opt/precon_all/

# Set proper permissions
RUN chown -R nonroot:nonroot /opt/precon_all

# Switch to non-root user
USER nonroot
WORKDIR /home/nonroot

# Default command
#CMD ["/bin/bash"]
EOF

echo "✓ Cached build Dockerfile created successfully!"
echo "Cache contents:"
ls -lh ./cache/
echo "Total cache size: $(du -sh ./cache | cut -f1)"
