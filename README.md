## Comprehensive Installation Guide: Ubuntu 24.04 on ASUS ROG Zephyrus GU605C
The installation of Ubuntu 24.04 LTS on modern, high-performance laptops like the ASUS ROG Zephyrus GU605C (2025 model) presents significant challenges due to hardware components that exceed the support capabilities of the distribution's default kernel stack. This guide details the necessity of an expedited, custom installation path, focusing on kernel 6.15.11, proprietary NVIDIA drivers, and bespoke control software, delivered through a professional-grade, error-resilient Bash script.

# 1. Introduction to the ASUS GU605C Compatibility Challenge
# 1.1 Hardware Overview and Linux Compatibility Status

The Zephyrus GU605C incorporates bleeding-edge components, including an Intel Core Ultra processor (likely 14th generation or newer) and a powerful NVIDIA GeForce RTX 50 Series Laptop GPU. Linux support for such recent hardware is often delayed, relying on rapid development in the mainline kernel rather than the stable, slower-moving Long-Term Support (LTS) kernels distributed by Canonical.   

Critical Deficiencies of Kernel 6.8

Ubuntu 24.04 LTS (Noble Numbat) ships standardly with Linux kernel 6.8. This kernel version is documented as being insufficient for a fully functional deployment on the GU605C. The documented issues include:   

Non-Functional Wireless Connectivity: The Intel BE201 Wi-Fi 7 adapter, a key component, frequently fails to initialize or recognize networks, rendering wireless unusable without a separate adapter.   
Impaired Audio Output: The laptop's Cirrus Logic sound amplifier (such as the CS35L56 found in related models ) often lacks necessary ACPI properties, leading to extremely low volume or tinny sound quality.   
System Power Management Failures: Users report that the system fails to properly shut down or reboot, often stalling at a "Reached Target: System Power Off" screen, which is frequently preceded by correctable PCIe errors logged in the system messages.   
The Kernel Requirement

To mitigate these critical deficiencies, a kernel newer than the default 6.8 is mandatory. Functionality improvements for the 14th generation Intel components, particularly audio stability, are noted to begin around kernel 6.9 and above. The user's specific request for kernel 6.15.11 is strategically sound, as migrating to a more recent mainline kernel is the most direct path to acquiring the latest hardware compatibility patches necessary for the entire hardware suite.   

1.2 The Interdependency Challenge

A standard sequential installation approach is insufficient for this hardware configuration, as the proprietary components introduce critical dependencies that must be resolved in a specific order:

The Kernel/Driver Nexus: The NVIDIA proprietary graphics driver uses Dynamic Kernel Module Support (DKMS) to compile kernel modules tailored to the active kernel. If the proprietary driver is installed before the custom 6.15.11 kernel is fully installed and its headers are present, the DKMS build will fail, potentially leading to a non-functional graphical boot state (black screen with a flashing cursor). Therefore, the custom kernel must be installed, configured, and ready    

before the NVIDIA driver installation commences.

Control Plane Dependency: Essential laptop-specific controls—including GPU switching, fan curves, and keyboard RGB management—are handled by the open-source asusctl and supergfxctl utilities. These utilities require a modern kernel (version 6.1.x or greater is the minimum threshold) and must be compiled from source on Ubuntu-based systems, requiring extensive development dependencies.   
This fragile dependency chain necessitates a highly robust installation script. By manually integrating a mainline kernel and compiling core utilities from source, the installation steps move outside of Canonical's standard testing environment (HWE or GA kernel stacks). This increases the fragility of the build process, making comprehensive error trapping a vital safeguard against multi-system failure modes, ensuring that failure at one step does not corrupt the entire operating system.   

2. Architecture of the Robust Installation Script (Error Handling and State Management)
Installing critical, low-level components like kernels and proprietary drivers requires an installation script with professional-grade error architecture to ensure operational integrity and provide forensic diagnostic information upon failure.

2.1 Bash Scripting Standards for Integrity

The script is secured by mandatory Bash options that enforce rigorous command execution integrity :   

set -e (errexit): This is the cornerstone of reliability. It commands the script to exit immediately if any command returns a non-zero exit status, thereby preventing subsequent steps from executing in an inconsistent or failed state.   
set -u: This prevents operations on unset variables, thereby avoiding potentially cryptic or destructive null operations.

set -o pipefail: This ensures that errors within command pipelines (commands chained with |) are correctly reported. If any command in the chain fails, the entire pipeline is considered failed, triggering the script's exit mechanism.

2.2 Comprehensive Error Trapping and Cleanup

Since an atomic rollback for kernel and driver installations is fundamentally impossible (unlike a database transaction) , the error handling strategy focuses on guaranteed resource cleanup and precise failure reporting.   

Table 2: Bash Error Handling Architecture

Directive/Trap	Syntax	Function in Script Integrity	Failure Response
Errexit	set -e	Ensures immediate script termination upon command failure.	Triggers ERROR_TRAP and ultimately CLEANUP.
Pipefail	set -o pipefail	Ensures robust error checking even within chained commands.	Triggers ERROR_TRAP and terminates the script.
Cleanup Routine	trap cleanup EXIT	Executes critical state reset (temp file removal) and exit code reporting.	
Always runs, regardless of success or failure.
Error Reporter	trap error_trap ERR	Logs command, line number, and context of the immediate failure.	
Stops execution and provides diagnostic guidance.
  
The cleanup Function (EXIT Trap)

The trap cleanup EXIT command ensures that a dedicated cleanup function executes every time the script terminates, whether successfully or due to an error. This function is essential for state management, specifically handling the guaranteed removal of temporary directories used for kernel downloads and source compilation (e.g.,    

/tmp/kernel_install). It also captures the final exit status (rv=$?) before finalizing the script's execution.

The error_trap Function (ERR Trap)

The trap error_trap ERR is defined to execute immediately when a non-zero exit status is detected by set -e. This function acts as a critical Failure Reporter. Instead of a silent exit, the trap prints the line number (   

$LINENO), the exact command that failed ($BASH_COMMAND), and the execution context ($FUNCNAME). This detailed diagnostic information is paramount. If the script fails during a complex DKMS compilation, the user is provided with the exact failure point, enabling them to boot into a recovery mode (via GRUB advanced options) and manually purge the failing package set, thereby reverting the system to the known stable state that existed before the attempted upgrade.   

3. Stage 1: Core System and Kernel Upgrade
This stage establishes the essential environment and installs the required 6.15.11 kernel, which serves as the foundational requirement for all subsequent proprietary installations.

3.1 System Preparation and Dependency Installation

The system must be prepared by ensuring access to proprietary software. The restricted and multiverse repositories are required to download NVIDIA drivers and certain firmware packages.   

Bash
log_step "Enabling required repositories: restricted and multiverse."
sudo add-apt-repository restricted multiverse -y
log_step "Updating system packages and installing core dependencies."
sudo apt update && sudo apt full-upgrade -y
sudo apt install -y wget dpkg build-essential git
The installation of build-essential and git is mandatory here as they are prerequisites for both the custom kernel installation and the later compilation of asusctl and supergfxctl from source.   

3.2 Linux Kernel 6.15.11 Installation (Manual Mainline Method)

Since kernel 6.15.11 is not available in the standard Ubuntu 24.04 repositories , the system must pull the necessary files directly from the official Ubuntu Mainline Kernel PPA archive via    

wget. The process requires downloading four specific DEB packages tailored for the AMD64 architecture: the generic headers, the architecture-agnostic headers, the unsigned image (the kernel binary itself), and the modules package.   

The approach avoids the often problematic use of PPAs for kernel installation, instead relying on direct file download and local installation using dpkg. The specific structure of the mainline kernel package names is critical for a successful download.

Bash
# Example Kernel 6.15.11 structure derived from research
KERNEL_VERSION="6.15"
KERNEL_FULL_VERSION="6.15.11"
KERNEL_RELEASE="061511"
MAINLINE_URL="https://kernel.ubuntu.com/mainline/v${KERNEL_VERSION}"
KERNEL_TMP_DIR="/tmp/kernel_install"

log_step "Downloading Linux Kernel ${KERNEL_FULL_VERSION} packages."
mkdir -p "$KERNEL_TMP_DIR"
cd "$KERNEL_TMP_DIR"

wget -c "${MAINLINE_URL}/amd64/linux-headers-${KERNEL_FULL_VERSION}-*-generic*.deb"
wget -c "${MAINLINE_URL}/amd64/linux-headers-${KERNEL_FULL_VERSION}_*all.deb"
wget -c "${MAINLINE_URL}/amd64/linux-image-unsigned-${KERNEL_FULL_VERSION}-*-generic*.deb"
wget -c "${MAINLINE_URL}/amd64/linux-modules-${KERNEL_FULL_VERSION}-*-generic*.deb"

log_step "Installing Linux Kernel ${KERNEL_FULL_VERSION} via dpkg."
sudo dpkg -i *.deb
After installing the packages, the script must ensure that the GRUB bootloader is updated to recognize the new kernel and place it in the boot menu for selection.

Bash
log_step "Updating GRUB configuration."
sudo update-grub
4. Stage 2: NVIDIA Graphics Stack Integration
This stage focuses on integrating the proprietary NVIDIA driver, which is essential for performance on the ROG Zephyrus GU605C. This step must only proceed after the custom 6.15.11 kernel has been installed.

4.1 Driver Cleanup and PPA Setup

Previous or conflicting drivers must be systematically purged to ensure a clean DKMS compilation environment. Removing residual packages is crucial for stability.   

Bash
log_step "Purging conflicting NVIDIA drivers."
sudo apt-get remove --purge '^nvidia-.*' |

| true # Continues if no NVIDIA drivers are found
sudo apt autoremove
The recommended method for installing newer NVIDIA drivers compatible with the RTX 50 series hardware involves leveraging the PPA maintained by the Ubuntu Graphics Drivers team. This repository provides access to driver versions (such as the 570 series) that explicitly support the latest GPU architectures.   

Bash
log_step "Adding the official graphics-drivers PPA."
sudo add-apt-repository ppa:graphics-drivers/ppa -y
sudo apt update
4.2 NVIDIA Driver Installation and Mitigation

For new hardware like the RTX 50 series, a recent driver package is required (e.g., nvidia-driver-570 or the latest stable available). The installation of this package automatically triggers DKMS to compile the necessary proprietary kernel modules against all installed kernel headers, including the newly installed 6.15.11 version.   

Bash
# Note: Driver 570 series is used as an example for the RTX 50 Series.
NVIDIA_DRIVER_VERSION="570"
log_step "Installing recommended NVIDIA driver (version ${NVIDIA_DRIVER_VERSION})."
sudo apt install -y "nvidia-driver-${NVIDIA_DRIVER_VERSION}" nvidia-settings
A common failure mode immediately following proprietary NVIDIA driver installation on Ubuntu is a graphical boot failure, often manifesting as a black screen with a flashing cursor, related to conflicts between the proprietary driver and the display manager (GDM) attempting to use Wayland. A pre-emptive fix involves modifying the GDM udev rules to ensure Wayland is explicitly disabled when the proprietary NVIDIA driver is active.   

Bash
log_step "Applying workaround for GDM/Wayland conflict (Flashing Cursor fix)."
# Comment out the line in 61-gdm.rules that disables Wayland for Nvidia drivers
# This sometimes allows the system to fall back correctly to Xorg/GDM
GDM_RULES_FILE="/lib/udev/rules.d/61-gdm.rules"
if grep -q 'DRIVER=="nvidia", RUN+="/usr/lib/gdm3/gdm-disable-wayland"' "$GDM_RULES_FILE"; then
    sudo sed -i '/DRIVER=="nvidia", RUN+="/usr/lib/gdm3/gdm-disable-wayland"/c\#DRIVER=="nvidia", RUN+="/usr/lib/gdm3/gdm-disable-wayland"' "$GDM_RULES_FILE"
    log_step "Successfully commented out Wayland disabling rule for NVIDIA."
else
    log_step "Wayland disabling rule for NVIDIA not found or already commented out."
fi
It must be noted that for proprietary DKMS modules to successfully load, especially those tied to Secure Boot policies, UEFI Secure Boot must be disabled in the system BIOS prior to running this script. Failure to disable Secure Boot will prevent the unsigned NVIDIA modules from loading, resulting in a boot failure regardless of the script's success.   

5. Stage 3: ASUS Control Plane Compilation and Service Setup
To effectively utilize the laptop's specific hardware features, the dedicated Linux control utilities asusctl and supergfxctl must be installed. Since pre-compiled binaries are not officially supported for Ubuntu , compilation from source is required.   

5.1 Installing the Rust Toolchain

Both asusctl and supergfxctl are Rust projects. The required Rust toolchain must be installed before compilation can proceed.   

Bash
log_step "Installing Rust toolchain (required for asusctl/supergfxctl compilation)."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
# Ensure cargo binaries are in PATH for current session
export PATH="$HOME/.cargo/bin:$PATH"
5.2 Source Compilation and Deployment

A specific set of development libraries is required for the compilation process to link successfully with system components such as PCI devices and the kernel API.   

Bash
log_step "Installing essential build dependencies for ASUS control tools."
sudo apt install -y cmake pkg-config libpci-dev libsysfs-dev libudev-dev libboost-dev libgtk-3-dev libglib2.0-dev libseat-dev
The compilation process is performed sequentially, starting with the core graphics switching daemon, supergfxctl.

supergfxctl and asusctl Installation

Supergfxctl manages the complex GPU switching mechanisms (Hybrid, iGPU, or MUX dGPU modes). Once compiled and installed, its service (   

supergfxd.service) must be enabled and started using systemctl.   

Asusctl provides control over essential functions like fan speed, power profiles, charge limits, and keyboard RGB/backlight.   

Bash
ASUS_TMP_DIR="/tmp/asus_compile"
mkdir -p "$ASUS_TMP_DIR"
cd "$ASUS_TMP_DIR"

log_step "Cloning and building supergfxctl."
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

log_step "Setting user permissions for asusctl/supergfxctl usage."
# Add the current user to the 'users' group to enable command execution without sudo
sudo usermod -a -G users $USER
The user must refresh their session (most easily accomplished via a system reboot) to ensure the user group change is applied and the control services are correctly running in the new kernel environment.

6. Stage 4: Critical Hardware Firmware and System Fixes
This final stage addresses specific deficiencies inherent to this model, particularly the audio system.

6.1 Resolving Cirrus Audio Issues

The low volume and poor sound quality experienced on the GU605C are traced to the Cirrus Logic amplifier requiring specific firmware and configuration data, which is often missing in standard Linux installations. Although Kernel 6.7+ brought a new framework for Cirrus amps, newer models like the GU605C may still require manual firmware deployment.   

The solution involves cloning the upstream linux-firmware repository and copying the specific cirrus configuration files into the system's firmware path (/lib/firmware).   

Bash
log_step "Installing specific Cirrus audio firmware for volume fix."
cd "$ASUS_TMP_DIR"
git clone https://gitlab.com/kernel-firmware/linux-firmware.git
cd linux-firmware

# Note: rdfind and make may need installation if not present, though build-essential usually covers 'make'.
# sudo apt install -y rdfind # dnf specific command, not needed for apt setup

FIRMWARE_TMP_DIR=$(mktemp -d)
log_step "Copying Cirrus firmware to /lib/firmware."
# Using 'make install' to stage files, then copying specific directory
make install DESTDIR="$FIRMWARE_TMP_DIR"
sudo cp -r "$FIRMWARE_TMP_DIR/lib/firmware/cirrus" /lib/firmware
rm -rf "$FIRMWARE_TMP_DIR"
6.2 Addressing Persistent Issues (Contextual Notes)

Even after installing kernel 6.15.11, two issues might persist due to ongoing upstream development required for such new hardware:

Intel BE201 Wi-Fi 7 Status: Although the driver for the Intel BE201 card is present in modern kernels (6.11+), documented kernel bugs related to its initialization and functionality are known and are being addressed by kernel maintainers. The system may recognize the device but still exhibit unreliable or non-functional network discovery until a future kernel patch is applied. The user should be prepared to use a temporary external Wi-Fi adapter until full upstream support arrives.   
System Shutdown/Reboot Failure: The inability of the GU605C to properly shut down or reboot, often associated with PCIe error spamming, is likely a deep ACPI/BIOS incompatibility specific to the platform. While the newer kernel improves stability, a definitive scripted fix is not currently available, and this issue typically requires a future kernel or BIOS update for resolution.   

The overall success of this installation approach is summarized in the hardware compatibility matrix below:

Table 1: ASUS GU605C Hardware Compatibility Matrix

Component	Default Ubuntu 24.04 Status (Kernel 6.8)	6.15.11 Kernel + Custom Fix Status	Required Action/Fix
Linux Kernel	
Insufficient support; required kernel >=6.9 	Stable/Optimized (DKMS ready)	
Manual Mainline Installation 
NVIDIA RTX 50 Series	
Difficult installation; boot failure risk 	Functional (via DKMS build against 6.15.11)	
Proprietary PPA Driver Install (e.g., 570 series) 
Cirrus Audio Amp	
Low volume, amp not initialized 	Functional full volume	
Manual Cirrus Firmware Deployment 
Fan/Power/RGB Control	
Non-functional (no kernel module) 	Functional	
asusctl & supergfxctl Source Compile 
Intel BE201 Wi-Fi 7	
Non-functional (known kernel bug) 	Driver present, but may be unreliable/buggy	
Await future kernel/firmware patch 
System Shutdown/Reboot	
Fails to power off, PCIe errors logged 	Improved stability, but may persist	
Ongoing upstream kernel/BIOS fix required 
  
7. The Complete Installation Script (ASUS_GU605C_SETUP.sh)
The following script encapsulates the required steps with robust error handling.

Bash
#!/bin/bash
# SCRIPT: ASUS_GU605C_SETUP.sh
# DESCRIPTION: Automated installation of Linux Kernel 6.15.11, NVIDIA drivers,
# and ASUS control utilities (asusctl/supergfxctl) on Ubuntu 24.04 LTS.
# WARNING: SECURE BOOT MUST BE DISABLED IN UEFI/BIOS BEFORE RUNNING.

# --- 1. CONFIGURATION AND ERROR HANDLING ---
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
    echo -e "\n\033[1;34m[INFO]\033\033\033\033; then
        rm -rf "$KERNEL_TMP_DIR"
        log_step "Removed temporary kernel directory: $KERNEL_TMP_DIR"
    fi
    if; then
        rm -rf "$ASUS_TMP_DIR"
        log_step "Removed temporary ASUS compilation directory: $ASUS_TMP_DIR"
    fi
    if [ "$rv" -eq 0 ]; then
        log_step "\033; then
    if command -v sudo &> /dev/null; then
        log_step "Script not running as root. Rerunning with sudo."
        exec sudo "$0" "$@"
    else
        echo "Please run this script as root or with sudo."
        exit 1
    fi
fi

# Set $USER back to the invoking user's actual username for non-sudo operations
if; then
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

| true
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
fi

# --- 5. ASUS CONTROL PLANE COMPILATION (asusctl and supergfxctl) ---

log_step "Stage 4: Installing Rust toolchain and compiling ASUS Control Utilities."

# Ensure PATH includes cargo binaries for the root session
export PATH="/root/.cargo/bin:$PATH"

log_step "Verifying Rust installation for compilation."
if! command -v rustc &> /dev/null; then
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

# Final cleanup handled by the trap
8. Verification Command References
Upon successful script execution, a system reboot is mandatory. After the system restarts into the new 6.15.11 kernel, the user must execute the following commands to confirm that all required components are functioning correctly:

Verify Kernel Version:
This command must confirm that the system is running the intended mainline kernel, confirming the successful installation of the four DEB packages.

Bash
uname -r
# Expected output: 6.15.11-061511-generic (or similar structure)
Verify NVIDIA Driver Status:
This confirms that the DKMS modules for the proprietary driver successfully compiled against kernel 6.15.11 and that the NVIDIA GPU is initialized and ready.

Bash
nvidia-smi
# Expected output: GPU details, driver version, and functional CUDA status.
Verify GPU Switching Control (supergfxctl):
This confirms the supergfxd service is running and GPU switching modes are available, essential for battery management and performance.

Bash
supergfxctl -m
# Expected output: Current graphics mode (e.g., Hybrid, iGPU Only, or AsusMuxDgpu)
Verify ASUS Control Utility (asusctl):
This confirms the utility responsible for power profiles and fan control is operational, validating the source compilation process.

Bash
asusctl profile -p
# Expected output: Current power profile (e.g., Performance, Balanced, Silent)
Bash
asusctl fan -q
# Expected output: Fan curve configuration status