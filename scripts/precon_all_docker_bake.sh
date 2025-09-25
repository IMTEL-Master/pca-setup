#!/bin/bash

# Generate Dockerfile for direct build (no caching)
# This downloads all dependencies during Docker build

set -e  # Exit on error

echo "Generating direct build Dockerfile..."

cat <<'EOF' > precon_all_dockerfile
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

# Set working directory for downloads
WORKDIR /tmp

# Download and install Miniconda
RUN echo "Downloading Miniconda..." && \
    wget -q --show-progress --progress=bar:force:noscroll \
        "https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh" \
        -O miniconda.sh && \
    bash miniconda.sh -b -p /opt/miniconda-latest && \
    rm miniconda.sh

# Set conda PATH and accept ToS
ENV PATH=/opt/miniconda-latest/bin:$PATH
RUN conda config --set always_yes yes --set changeps1 no && \
    conda update -q conda && \
    conda install -y -c conda-forge mamba && \
    mamba install -y -c conda-forge nipype notebook && \
    conda clean -a

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

# Download and install Connectome Workbench
RUN echo "Downloading Connectome Workbench..." && \
    wget -q --show-progress --progress=bar:force:noscroll \
        "https://www.humanconnectome.org/storage/app/media/workbench/workbench-linux64-v2.1.0.zip" \
        -O workbench.zip && \
    unzip -q workbench.zip -d /opt/ && \
    rm workbench.zip && \
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
COPY data /opt/precon_all/ 2>/dev/null || echo "No data directory found, skipping..."

# Set proper permissions
RUN chown -R nonroot:nonroot /opt/precon_all

# Switch to non-root user
USER nonroot
WORKDIR /home/nonroot

# Default command
CMD ["/bin/bash"]
EOF

echo "✓ Direct build Dockerfile created successfully!"
echo "This will download all dependencies during the Docker build process."
