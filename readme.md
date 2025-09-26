# Precon All Docker Setup

Automated Docker container setup for neuroimaging processing pipeline including FreeSurfer, FSL, ANTs, and Connectome Workbench.

## System Requirements

- **OS**: Linux (x86_64 architecture only)
- **RAM**: 16GB+ recommended (minimum 8GB)
- **Storage**: 50GB+ free disk space
- **Software**: Docker, sudo privileges
- **Network**: Stable internet connection for downloads

> **Note**: ARM64 support is planned for future releases.

## Quick Start

1. **Clone and navigate to the repository**
   ```bash
   git clone https://github.com/IMTEL-Master/pca-setup
   cd pca-setup
   ```
2. **Give execution permission to shell files**
  ```bash
  sudo find "$(pwd)" -type f -name "*.sh" -exec chmod +x {} +
  ```

3. **Recommended: enter a GNU screen or tmux session**
  ```bash
  tmux new
  # or
  screen -S setup-precon
  ```

4. **Run the setup script**
   ```bash
   sudo -E ./setup.sh
   ```
  > -E persists the environment and does not create a new one due to the sudo. This way the script catches that you are in a tmux or screen session.

5. **Follow the interactive prompts to choose your build method**

## Build Methods

### Method 1: Cached Build (Recommended)
- Pre-downloads all large dependencies (~20GB)
- More reliable for unstable connections
- Faster rebuilds if needed
- Better for SSH/remote sessions

### Method 2: Direct Build
- Downloads during Docker build
- Less disk space initially required
- Single-step process
- May fail on connection issues

## File Structure

```
pca-setup/
├── setup.sh                 # Main setup script
├── README.md                # This file
├── data/                    # Your neuroimaging data
├── output/                  # Processing output directory
├── license.txt              # FreeSurfer license (optional)
├── cache/                   # Downloaded dependencies (created by script)
└── scripts/
    ├── docker-compose.yml
    ├── predownload-dependencies.sh
    ├── precon_all_docker_cached.sh
    └── precon_all_docker_bake.sh
```

## Included Software

| Software | Version | Purpose |
|----------|---------|---------|
| FreeSurfer | 7.4.1 | Cortical reconstruction |
| FSL | Latest | Brain analysis tools |
| ANTs | 2.6.2 | Image registration |
| Connectome Workbench | 2.1.0 | Connectome analysis |
| Miniconda | Latest | Python environment |
| Nipype | Latest | Pipeline framework |

## Usage

### Running the Container

```bash
# Navigate to scripts directory
cd scripts

# Start the container
sudo docker-compose run precon_all

# Or run in background
sudo docker-compose up -d
```

## Using precon_all
To use precon_all you have two options. Either make a species structure, or perform single Subject Processing:

# 1. Organize your data
mkdir -p myproject/masks
cp brain_mask.nii.gz data/masks/
cp left_hem.nii.gz data/masks/
cp right_hem.nii.gz data/masks/
cp sub_cort.nii.gz data/masks/
cp non_cort.nii.gz data/masks/

# 2. Run pipeline
cd myproject
```bash
surfing_safari.sh -i subject_T1.nii.gz -r precon_all -a masks
```
The other option is Batch Processing with Standard Template, dor established species (e.g., pig):
```bash
surfing_safari.sh -i subject_T1.nii.gz -r precon_all -a pig
```

For more information on precon_all and troubleshooting, check out: 
[Precon all repository](https://github.com/IMTEL-Master/precon_all)

### Accessing Your Data

- Place input data in the `data/` directory
- Processed outputs will appear in the `output/` directory
- Both directories are automatically mounted in the container

### FreeSurfer License

If you have a FreeSurfer license:
1. Place `license.txt` in the root directory
2. The setup will automatically mount it in the container

## Troubleshooting

### Common Issues

1. **Download failures**: Use the cached build method for better reliability
2. **Out of disk space**: Ensure 30GB+ free space before starting
3. **Memory issues**: Close other applications, ensure 16GB+ RAM
4. **Permission errors**: Ensure your user has sudo privileges

### SSH Sessions

For remote builds over SSH, use screen or tmux:
```bash
screen -S precon_setup
./setup.sh
# Press Ctrl+A, then D to detach
# Later: screen -r precon_setup to reattach
```

### Logs and Debugging

```bash
# View container logs
sudo docker-compose logs precon_all

# Check container status
sudo docker-compose ps

# Enter running container
sudo docker exec -it precon_all_container bash
```

### Cleanup

```bash
# Remove containers
sudo docker-compose down

# Remove images (to rebuild from scratch)
sudo docker rmi $(sudo docker images -q "*precon*")

# Clean cache (saves 20GB)
rm -rf cache/
```

## Environment Variables

The container sets up the following environment variables:

- `FREESURFER_HOME`: `/opt/freesurfer`
- `SUBJECTS_DIR`: `/output`
- `FSLDIR`: `/opt/fsl`
- `ANTSPATH`: `/usr/local/sbin/ants/bin`
- `PCP_PATH`: `/opt/precon_all`

## Architecture Support

Currently supported:
- ✅ Linux x86_64

Planned for future releases:
- ⏳ Linux ARM64 (Apple Silicon, ARM servers)
- ⏳ macOS support

## Contributing

To add ARM64 support or other improvements:

1. Architecture detection is handled in `setup.sh` - modify the `check_system()` function
2. Download URLs may need ARM64 variants in the download scripts
3. Docker base images may need multi-arch support

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review Docker logs for specific errors
3. Ensure all system requirements are met
4. Consider using the cached build method for reliability

## License

This setup script is provided as-is. Individual software packages (FreeSurfer, FSL, etc.) have their own licensing terms.
