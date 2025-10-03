#!/bin/bash
# SCRIPT: ASUS_GU605C_SETUP.sh
# DESCRIPTION: Automated installation of Linux Kernel 6.15.11, NVIDIA drivers,
# and ASUS control utilities (asusctl/supergfxctl) on Ubuntu 24.04 LTS.
# WARNING: SECURE BOOT MUST BE DISABLED IN UEFI/BIOS BEFORE RUNNING.

# --- 1. CONFIGURATION AND ERROR HANDLING ---
# Enable immediate exit on command failure, prevent unset variables, and detect errors in pipelines.
set -euo pipefail

# User configuration
USER_NAME=$(whoami)
NVIDIA_DRIVER_VERSION="570" # Select a driver version compatible with RTX 50 series
KERNEL_VERSION="6.15"
KERNEL_FULL_VERSION="6.15.11"
MAINLINE_URL="https://kernel.ubuntu.com/mainline/v${KERNEL_VERSION}"

# Temporary directories managed by the cleanup trap
KERNEL_TMP_DIR="/tmp/kernel_install_$USER"
ASUS_TMP_DIR="/tmp/asus_compile_$USER"


# Logging function
log_step() {
    local message="$1"
    # Print the message with INFO tag and blue color
    echo -e "\n\033[1;34m[INFO]\033\033[0m"
    echo "Failure occurred in function: ${FUNCNAME[1]:-main context}"
    echo "Failed command: '$last_command'"
    echo "Error on line: $line"
    echo "--- CHECK LOGS AND REVIEW FAILURE CONTEXT ---"
}
trap 'error_trap' ERR

# Cleanup function (Runs on EXIT signal, regardless of success or failure)
cleanup() {
    local rv=$? # Capture the final exit status of the script
    log_step "Starting final cleanup routine..."
    
    # Check and remove temporary kernel directory
    if; then
        rm -rf "$KERNEL_TMP_DIR"
        log_step "Removed temporary kernel directory: $KERNEL_TMP_DIR"
    fi
    
    # Check and remove temporary ASUS compilation directory
    if; then
        rm -rf "$ASUS_TMP_DIR"
        log_step "Removed temporary ASUS compilation directory: $ASUS_TMP_DIR"
    fi

    if [ "$rv" -ne 0 ]; then
        log_step "Script finished with ERRORS (Exit Code $rv)."
    else
        log_step "Script finished successfully (Exit Code 0). Please REBOOT NOW."
    fi
    
    # Exit with the captured status code
    exit "$rv"
}
trap 'cleanup' EXIT

# Initial root check and re-execution with sudo
if]; then
    if command -v sudo &> /dev/null; then
        log_step "Script not running as root. Rerunning with sudo."
        # Use exec to replace the current shell process with the sudo command
        exec sudo "$0" "$@"
    else
        echo "Please run this script as root or with sudo."
        exit 1
    fi
fi

# Set $USER_NAME back to the invoking user's actual username for non-sudo operations (like usermod)
if]; then
    USER_NAME="$SUDO_USER"
else
    USER_NAME=$(whoami)
fi

# --- 2. SYSTEM PREPARATION AND DEPENDENCIES ---

log_step "Stage 1: System Preparation and Core Dependencies Installation."
log_step "Enabling required repositories: restricted and multiverse."
sudo add-apt-repository restricted multiverse -y
sudo apt update
sudo apt install -y wget dpkg git build-essential curl ca-certificates libpci-dev libsysfs-dev libudev-dev libboost-dev libgtk-3-dev libglib2.0-dev libseat-dev

# Full system upgrade before kernel install (optional, but recommended)
log_step "Performing system full upgrade."
sudo apt full-upgrade -y

# --- 3. KERNEL 6.15.11 INSTALLATION ---

log_step "Stage 2: Installing Mainline Linux Kernel ${KERNEL_FULL_VERSION}."
mkdir -p "$KERNEL_TMP_DIR"
cd "$KERNEL_TMP_DIR"

# Download the four required DEB packages for 6.15.11 (amd64)
log_step "Downloading kernel packages from ${MAINLINE_URL}."
wget -c "${MAINLINE_URL}/amd64/linux-headers-${KERNEL_FULL_VERSION}-*-generic_*.deb"
wget -c "${MAINLINE_URL}/amd64/linux-headers-${KERNEL_FULL_VERSION}_*_all.deb"
wget -c "${MAINLINE_URL}/amd64/linux-image-unsigned-${KERNEL_FULL_VERSION}-*-generic_*.deb"
wget -c "${MAINLINE_URL}/amd64/linux-modules-${KERNEL_FULL_VERSION}-*-generic_*.deb"

log_step "Installing Linux Kernel ${KERNEL_FULL_VERSION}."
sudo dpkg -i --force-depends *.deb
sudo apt install -f -y # Fixes any dependency issues after manual dpkg

log_step "Updating GRUB configuration to recognize new kernel."
sudo update-grub

# --- 4. NVIDIA GRAPHICS STACK INTEGRATION ---

log_step "Stage 3: NVIDIA Driver Installation (DKMS dependency on ${KERNEL_FULL_VERSION})."

log_step "Purging potentially conflicting NVIDIA drivers."
sudo apt-get remove --purge '^nvidia-.*' |

| true # Use |
| true to prevent script exit if no packages match
sudo apt autoremove

log_step "Adding the official graphics-drivers PPA for recent driver access."
sudo add-apt-repository ppa:graphics-drivers/ppa -y
sudo apt update

log_step "Installing recommended NVIDIA driver (version ${NVIDIA_DRIVER_VERSION}). DKMS compilation begins now."
sudo apt install -y "nvidia-driver-${NVIDIA_DRIVER_VERSION}" nvidia-settings

log_step "Applying workaround for GDM/Wayland conflict (Flashing Cursor Fix)."
GDM_RULES_FILE="/lib/udev/rules.d/61-gdm.rules"
if grep -q 'DRIVER=="nvidia", RUN+="/usr/lib/gdm3/gdm-disable-wayland"' "$GDM_RULES_FILE"; then
    sudo sed -i '/DRIVER=="nvidia", RUN+="/usr/lib/gdm3/gdm-disable-wayland"/c\#DRIVER=="nvidia", RUN+="/usr/lib/gdm3/gdm-disable-wayland"' "$GDM_RULES_FILE"
    log_step "GDM Wayland disabling rule commented out."
else
    log_step "Wayland disabling rule for NVIDIA not found or already commented out."
fi

# --- 5. ASUS CONTROL PLANE COMPILATION (asusctl and supergfxctl) ---

log_step "Stage 4: Installing Rust toolchain and compiling ASUS Control Utilities."

# Ensure PATH includes cargo binaries for the root session
export PATH="/root/.cargo/bin:$PATH"

log_step "Verifying Rust installation for compilation."
if! command -v rustc &> /dev/null; then # Corrected: added space after 'if'
    log_step "Rust toolchain is not fully configured or installed. Re-running rustup."
    # Install rust again, this time as root for consistency in the script environment
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source /root/.cargo/env
fi

mkdir -p "$ASUS_TMP_DIR"
cd "$ASUS_TMP_DIR"

log_step "Cloning and compiling supergfxctl."
git clone https://gitlab.com/asus-linux/supergfxctl.git
cd supergfxctl
make && sudo make install

log_step "Enabling and starting supergfxd service."
sudo systemctl enable supergfxd.service --now

cd "$ASUS_TMP_DIR"
log_step "Cloning and building asusctl."
git clone https://gitlab.com/asus-linux/asusctl.git
cd asusctl
make && sudo make install

log_step "Setting user permissions for asusctl/supergfxctl usage for user: $USER_NAME"
# Add the invoking user to the 'users' group
sudo usermod -a -G users "$USER_NAME"

# --- 6. CRITICAL HARDWARE FIRMWARE FIXES (CIRRUS AUDIO) ---

log_step "Stage 5: Deploying Cirrus Audio Firmware Fix."
cd "$ASUS_TMP_DIR"

log_step "Cloning linux-firmware repository."
git clone https://gitlab.com/kernel-firmware/linux-firmware.git
cd linux-firmware

FIRMWARE_TMP_DIR=$(mktemp -d)
log_step "Staging and copying cirrus firmware files to /lib/firmware."
make install DESTDIR="$FIRMWARE_TMP_DIR"
sudo cp -r "$FIRMWARE_TMP_DIR/lib/firmware/cirrus" /lib/firmware
rm -rf "$FIRMWARE_TMP_DIR"

# Final cleanup handled by the EXIT trap