#!/usr/bin/env bash
# SCRIPT: ASUS_GU605C_SETUP.sh
# DESCRIPTION: Automated installation of Linux Kernel 6.15.11, NVIDIA drivers,
# and ASUS control utilities (asusctl/supergfxctl) on Ubuntu 24.04 LTS.
# WARNING: SECURE BOOT MUST BE DISABLED IN UEFI/BIOS BEFORE RUNNING.
# NOTE: Verify MAINLINE_URL and kernel availability before running.

# --- 1. CONFIGURATION AND ERROR HANDLING ---
set -euo pipefail
set -E    # allow ERR trap inheritance
shopt -s expand_aliases

# Track commands for better error messages
last_command=""
current_command=""
trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG

# User configuration
INVOKING_USER=$(whoami)
NVIDIA_DRIVER_VERSION="570"       # Select a driver version compatible with your GPU
KERNEL_VERSION="6.15"
KERNEL_FULL_VERSION="6.15.11"
MAINLINE_URL="https://kernel.ubuntu.com/~kernel-ppa/mainline/v${KERNEL_VERSION}"

# We will set USER_NAME after ensuring sudo/root context
USER_NAME=""

# Temporary directories (set later using USER_NAME)
KERNEL_TMP_DIR=""
ASUS_TMP_DIR=""

# --- Logging and error handling functions ---
log_step() {
    local message="$1"
    printf "\n\033[1;34m[INFO]\033[0m %s\n" "$message"
}

error_trap() {
    local exit_code=$?
    local lineno=${BASH_LINENO[0]:-"unknown"}
    printf "\n\033[1;31m[ERROR]\033[0m Command failed with exit code %d\n" "$exit_code"
    printf "Last command: %s\n" "${last_command:-unknown}"
    printf "Failed at line: %s\n" "$lineno"
    printf "Function context: %s\n" "${FUNCNAME[1]:-main}"
    printf "--- REVIEW FAILURE CONTEXT BEFORE REBOOTING ---\n"
    # Let cleanup trap handle final messages / removal
}

trap 'error_trap' ERR

# Cleanup function (runs on EXIT; always executed)
cleanup() {
    local rv=$?
    log_step "Starting final cleanup routine..."

    if [[ -n "${KERNEL_TMP_DIR:-}" && -d "$KERNEL_TMP_DIR" ]]; then
        rm -rf "$KERNEL_TMP_DIR" || true
        log_step "Removed temporary kernel directory: $KERNEL_TMP_DIR"
    fi

    if [[ -n "${ASUS_TMP_DIR:-}" && -d "$ASUS_TMP_DIR" ]]; then
        rm -rf "$ASUS_TMP_DIR" || true
        log_step "Removed temporary ASUS compilation directory: $ASUS_TMP_DIR"
    fi

    if [ "$rv" -ne 0 ]; then
        log_step "Script finished with ERRORS (Exit Code $rv). DO NOT REBOOT YET."
    else
        log_step "Script finished successfully (Exit Code 0). Please REBOOT NOW to load the new kernel."
    fi

    exit "$rv"
}
trap 'cleanup' EXIT

# --- 0. ROOT CHECK and re-exec with sudo if needed ---
if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
        log_step "Script not running as root. Re-running with sudo..."
        exec sudo bash "$0" "$@"
    else
        echo "Please run this script as root or with sudo."
        exit 1
    fi
fi

# Now we are root: determine the invoking (non-root) user for later ops
if [ -n "${SUDO_USER-}" ] && [ "${SUDO_USER}" != "root" ]; then
    USER_NAME="$SUDO_USER"
else
    USER_NAME="$(whoami)"
fi

# Set temporary directories (use invoking user's name to avoid collisions)
KERNEL_TMP_DIR="/tmp/kernel_install_${USER_NAME}"
ASUS_TMP_DIR="/tmp/asus_compile_${USER_NAME}"

# --- 2. SYSTEM PREPARATION AND DEPENDENCIES ---
log_step "Stage 1: System Preparation and Core Dependencies Installation."
log_step "Enabling required repositories: restricted and multiverse."
# add-apt-repository may require 'software-properties-common'
apt update
apt install -y software-properties-common || true
add-apt-repository "restricted" || true
add-apt-repository "multiverse" || true
apt update

log_step "Installing build and runtime dependencies."
apt install -y wget dpkg git build-essential curl ca-certificates libpci-dev libudev-dev \
    libboost-dev libgtk-3-dev libglib2.0-dev libseat-dev pkg-config || true

log_step "Performing system full upgrade (recommended)."
apt full-upgrade -y || true

# --- 3. KERNEL ${KERNEL_FULL_VERSION} INSTALLATION ---
log_step "Stage 2: Installing Mainline Linux Kernel ${KERNEL_FULL_VERSION}."
mkdir -p "$KERNEL_TMP_DIR"
cd "$KERNEL_TMP_DIR"

log_step "Fetching list of available .deb files from ${MAINLINE_URL}/amd64/"
# Attempt to parse available .deb links for the exact kernel full version
# NOTE: MAINLINE_URL path may differ depending on kernel archive structure; verify before running.
deb_urls=$(curl -s "${MAINLINE_URL}/amd64/" 2>/dev/null \
    | grep -oP 'href="[^"]+\.deb"' \
    | sed -E 's/href="//;s/"$//' \
    | grep "${KERNEL_FULL_VERSION}" || true)

if [ -z "$deb_urls" ]; then
    log_step "Could not find .deb files automatically. Please verify MAINLINE_URL (${MAINLINE_URL}) and the kernel version."
    log_step "Aborting kernel download stage."
else
    log_step "Found kernel package links; downloading..."
    while read -r relpath; do
        # If relpath is absolute (starts with http), use it; else prefix with BASE
        if [[ "$relpath" =~ ^https?:// ]]; then
            url="$relpath"
        else
            url="${MAINLINE_URL}/amd64/${relpath}"
        fi
        log_step "Downloading: $url"
        wget -c --tries=3 --timeout=20 "$url" || log_step "Warning: failed to download $url"
    done <<< "$deb_urls"
fi

log_step "Installing downloaded kernel packages (if any)."
if compgen -G "*.deb" >/dev/null; then
    dpkg -i --force-depends ./*.deb || true
    apt install -f -y || true
    update-grub || true
else
    log_step "No .deb packages found in $KERNEL_TMP_DIR; skipping dpkg install."
fi

# --- 4. NVIDIA GRAPHICS STACK INTEGRATION ---
log_step "Stage 3: NVIDIA Driver Installation (DKMS dependency on ${KERNEL_FULL_VERSION})."

log_step "Purging potentially conflicting NVIDIA packages (if present)."
# allow failure if nothing matches
apt-get remove --purge -y '^nvidia-.*' || true
apt autoremove -y || true

log_step "Adding the official graphics-drivers PPA for recent driver access."
add-apt-repository ppa:graphics-drivers/ppa -y || true
apt update

log_step "Installing recommended NVIDIA driver (version ${NVIDIA_DRIVER_VERSION})."
apt install -y "nvidia-driver-${NVIDIA_DRIVER_VERSION}" nvidia-settings || true

log_step "Applying workaround for GDM/Wayland conflict (Flashing Cursor Fix)."
GDM_RULES_FILE="/lib/udev/rules.d/61-gdm.rules"
if [ -f "$GDM_RULES_FILE" ] && grep -q 'DRIVER==\"nvidia\", RUN+=' "$GDM_RULES_FILE"; then
    sed -i '/DRIVER==\"nvidia\", RUN+=/s/^/#/' "$GDM_RULES_FILE" || true
    log_step "GDM Wayland disabling rule commented out (if present)."
else
    log_step "Wayland disabling rule for NVIDIA not found or already commented out."
fi

# --- 5. ASUS CONTROL PLANE COMPILATION (asusctl and supergfxctl) ---
log_step "Stage 4: Installing Rust toolchain and compiling ASUS Control Utilities."

# If building as root, ensure root has rust in PATH; prefer installing rustup for the invoking user.
# We will install rustup for the invoking user if it does not exist.
if ! command -v rustc >/dev/null 2>&1; then
    log_step "Rust not found in environment. Installing rustup (for root)."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y || true
    # load cargo for this session (root)
    if [ -f "/root/.cargo/env" ]; then
        # shellcheck disable=SC1090
        source /root/.cargo/env || true
    fi
else
    log_step "Rust found: $(rustc --version || true)"
fi

mkdir -p "$ASUS_TMP_DIR"
cd "$ASUS_TMP_DIR"

log_step "Cloning and compiling supergfxctl."
if [ -d supergfxctl ]; then rm -rf supergfxctl; fi
git clone https://gitlab.com/asus-linux/supergfxctl.git || true
if [ -d supergfxctl ]; then
    cd supergfxctl
    if make && make install; then
        log_step "supergfxctl compiled and installed."
    else
        log_step "supergfxctl build/install failed. Continuing to next steps."
    fi
    cd "$ASUS_TMP_DIR"
else
    log_step "supergfxctl clone failed; skipping build."
fi

log_step "Enabling and starting supergfxd service (if available)."
if systemctl list-unit-files | grep -q supergfxd; then
    systemctl enable supergfxd.service --now || true
fi

log_step "Cloning and building asusctl."
if [ -d asusctl ]; then rm -rf asusctl; fi
git clone https://gitlab.com/asus-linux/asusctl.git || true
if [ -d asusctl ]; then
    cd asusctl
    if make && make install; then
        log_step "asusctl compiled and installed."
    else
        log_step "asusctl build/install failed. Continuing."
    fi
    cd "$ASUS_TMP_DIR"
else
    log_step "asusctl clone failed; skipping build."
fi

log_step "Setting user permissions for asusctl/supergfxctl usage for user: $USER_NAME"
# Add the invoking user to the 'users' group (group must exist)
if getent group users >/dev/null; then
    usermod -aG users "$USER_NAME" || true
else
    log_step "Group 'users' does not exist on this system; skipping usermod."
fi

# --- 6. CRITICAL HARDWARE FIRMWARE FIXES (CIRRUS AUDIO) ---
log_step "Stage 5: Deploying Cirrus Audio Firmware Fix."

cd "$ASUS_TMP_DIR"
if [ -d linux-firmware ]; then rm -rf linux-firmware; fi
git clone https://gitlab.com/kernel-firmware/linux-firmware.git || true

if [ -d linux-firmware ]; then
    cd linux-firmware
    FIRMWARE_TMP_DIR=$(mktemp -d)
    log_step "Staging and copying cirrus firmware files to /lib/firmware (via make install)."
    make install DESTDIR="$FIRMWARE_TMP_DIR" || true
    if [ -d "${FIRMWARE_TMP_DIR}/lib/firmware/cirrus" ]; then
        cp -r "${FIRMWARE_TMP_DIR}/lib/firmware/cirrus" /lib/firmware || true
        log_step "Cirrus firmware copied to /lib/firmware/cirrus."
    else
        log_step "Cirrus firmware not found in staged install; check linux-firmware repo contents."
    fi
    rm -rf "$FIRMWARE_TMP_DIR" || true
else
    log_step "linux-firmware clone failed; skipping firmware stage."
fi

log_step "Script completed main tasks. Final cleanup will run automatically."
# EXIT trap will run cleanup and print final messages
