#!/bin/bash

set -euo pipefail

# Constants
LZ4_VERSION="1.10.0"
BLOCK_SIZE=$((32 * 1024))  # 32KB in bytes
LZ4_INSTALL_DIR="/usr/local"

# Function for logging
log() {
    logger -t "compressed-device-setup" "$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Function for error handling
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Function to list all available devices
list_devices() {
    echo "Available devices:"
    echo "----------------"
    lsblk -ndo NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,UUID | while read -r dev_name dev_size dev_type mount_point fs_type uuid; do
        echo "Device: /dev/$dev_name"
        echo "  Size: $dev_size"
        echo "  Type: $dev_type"
        echo "  Mounted on: ${mount_point:-Not mounted}"
        [ -n "$fs_type" ] && echo "  Filesystem: $fs_type"
        [ -n "$uuid" ] && echo "  UUID: $uuid"
        echo ""
    done
}

# Function to detect OS and package manager
detect_os_and_pkg_manager() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        if command -v apt-get &> /dev/null; then
            PKG_MANAGER="apt-get"
        elif command -v yum &> /dev/null; then
            PKG_MANAGER="yum"
        else
            error_exit "Unsupported package manager. Please install dependencies manually."
        fi
    else
        error_exit "Unable to detect OS"
    fi
    log "Detected OS: $OS, using package manager: $PKG_MANAGER"
}

# Function to install dependencies
install_dependencies() {
    log "Installing dependencies..."
    if [ "$PKG_MANAGER" = "apt-get" ]; then
        apt-get update || error_exit "Failed to update package lists"
        apt-get install -y wget build-essential || error_exit "Failed to install dependencies"
    elif [ "$PKG_MANAGER" = "yum" ]; then
        yum update -y || error_exit "Failed to update package lists"
        yum groupinstall -y "Development Tools" || error_exit "Failed to install development tools"
        yum install -y wget || error_exit "Failed to install wget"
    fi
}

# Function to install LZ4
install_lz4() {
    log "Installing LZ4 $LZ4_VERSION..."
    wget "https://github.com/lz4/lz4/archive/v$LZ4_VERSION.tar.gz" || error_exit "Failed to download LZ4 $LZ4_VERSION"
    tar xzvf "v$LZ4_VERSION.tar.gz" || error_exit "Failed to extract LZ4 $LZ4_VERSION"
    cd "lz4-$LZ4_VERSION" || error_exit "Failed to change directory to lz4-$LZ4_VERSION"
    make PREFIX="$LZ4_INSTALL_DIR" || error_exit "Failed to compile LZ4 $LZ4_VERSION"
    make PREFIX="$LZ4_INSTALL_DIR" install || error_exit "Failed to install LZ4 $LZ4_VERSION"
    cd .. && rm -rf "lz4-$LZ4_VERSION" "v$LZ4_VERSION.tar.gz"
    
    # Update library cache and set LD_LIBRARY_PATH
    ldconfig || error_exit "Failed to update shared library cache"
    export LD_LIBRARY_PATH="${LZ4_INSTALL_DIR}/lib:${LD_LIBRARY_PATH:-}"

    lz4_version=$("$LZ4_INSTALL_DIR/bin/lz4" --version | head -n 1)
    log "Installed LZ4 version: $lz4_version"
    if [[ $lz4_version != *"v$LZ4_VERSION"* ]]; then
        error_exit "LZ4 $LZ4_VERSION installation failed or incorrect version installed"
    fi
}

# Function to create setup script
create_setup_script() {
    log "Creating setup script..."
    cat << EOF > /usr/local/sbin/setup_compressed_device.sh
#!/bin/bash

set -euo pipefail

# Constants
LZ4_INSTALL_DIR="$LZ4_INSTALL_DIR"
BLOCK_SIZE=$BLOCK_SIZE

# Ensure correct LZ4 version is used
export LD_LIBRARY_PATH="\$LZ4_INSTALL_DIR/lib:\$LD_LIBRARY_PATH"

log() {
    logger -t "compressed-device" "\$1"
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - \$1"
}

error_exit() {
    log "ERROR: \$1"
    exit 1
}

# Get device path
DEVICE="\${1:-}"
[ -z "\$DEVICE" ] && error_exit "No device specified. Usage: \$0 <device>"

# Create a directory for compressed files
MOUNT_POINT="/mnt/ext4_volume/compressed"
mkdir -p "\$MOUNT_POINT"

# Create a test file to demonstrate compression
log "Creating a test file to demonstrate compression..."
dd if=/dev/zero of="\$MOUNT_POINT/testfile" bs=1M count=100

# Compress the test file using LZ4
log "Compressing the test file using LZ4..."
lz4 "\$MOUNT_POINT/testfile" "\$MOUNT_POINT/testfile.lz4" || error_exit "Failed to compress the test file"

log "Compressed file created at \$MOUNT_POINT/testfile.lz4"
EOF

    chmod +x /usr/local/sbin/setup_compressed_device.sh || error_exit "Failed to make setup script executable"
}

# Function to update system-wide environment
update_system_environment() {
    log "Updating system-wide environment..."
    
    # Check if /etc/environment.d exists, if not create it
    if [ ! -d "/etc/environment.d" ]; then
        mkdir -p /etc/environment.d || error_exit "Failed to create /etc/environment.d directory"
    fi
    
    echo "LD_LIBRARY_PATH=$LZ4_INSTALL_DIR/lib:\$LD_LIBRARY_PATH" > /etc/environment.d/lz4.conf || error_exit "Failed to create lz4.conf"
    log "Added LD_LIBRARY_PATH to /etc/environment.d/lz4.conf"
    
    # Also update /etc/environment for systems that don't use environment.d
    if [ -f "/etc/environment" ]; then
        grep -qxF "LD_LIBRARY_PATH=$LZ4_INSTALL_DIR/lib:\$LD_LIBRARY_PATH" /etc/environment || echo "LD_LIBRARY_PATH=$LZ4_INSTALL_DIR/lib:\$LD_LIBRARY_PATH" >> /etc/environment
        log "Updated /etc/environment"
    else
        echo "LD_LIBRARY_PATH=$LZ4_INSTALL_DIR/lib:\$LD_LIBRARY_PATH" > /etc/environment
        log "Created /etc/environment"
    fi
}

# Main execution
main() {
    # Check if script is run as root
    [[ $EUID -ne 0 ]] && error_exit "This script must be run as root"

    detect_os_and_pkg_manager
    install_dependencies
    install_lz4
    create_setup_script
    update_system_environment

    # List devices and check for the mounted ext4 volume
    list_devices

    # Automatically select the device mounted at /mnt/ext4_volume
    USER_DEVICE=$(lsblk -ndo NAME,MOUNTPOINT | awk '$2=="/mnt/ext4_volume" {print "/dev/"$1}')
    if [ -z "$USER_DEVICE" ]; then
        error_exit "Could not find device mounted at /mnt/ext4_volume"
    fi
    log "Automatically selected device: $USER_DEVICE"

    # Call the setup script directly
    log "Setting up compressed device..."
    /usr/local/sbin/setup_compressed_device.sh "$USER_DEVICE" || error_exit "Failed to set up compressed device"

    log "Setup complete. The compressed file using LZ4 v$LZ4_VERSION with ${BLOCK_SIZE}B page size has been created."
    log "Device: $USER_DEVICE"
    log "Please review the setup and ensure everything is correct."
}

main "$@"