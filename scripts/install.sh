#!/bin/bash

# eBPF Network Threat Visualizer - Multi-Distribution Installation Script
# Supports: NixOS, Archlinux, Ubuntu, Debian, Catchy OS

set -e

echo "🌐 eBPF Network Threat Visualizer - Multi-Distribution Installer"
echo "================================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Global variables
DETECTED_DISTRO=""
DISTRO_ID=""
PKG_MANAGER_CHOICE=""
PASSWORD=""
CURRENT_STEP=1
TOTAL_STEPS=8

# Print functions
print_step() {
    echo -e "${BLUE}[STEP $CURRENT_STEP/$TOTAL_STEPS]${NC} $1"
}

print_status() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_progress() {
    local current=$1
    local total=$2
    local percent=$((current * 100 / total))
    local filled=$((percent / 2))
    local empty=$((50 - filled))

    printf "\r${YELLOW}[PROGRESS]${NC} ["
    printf "%*s" $filled | tr ' ' '█'
    printf "%*s" $empty | tr ' ' '░'
    printf "] %d%% (%d/%d)" $percent $current $total
}

# Cleanup function
cleanup() {
    if [ -n "$PASSWORD" ]; then
        unset PASSWORD
    fi
}

# Set trap for cleanup
trap cleanup EXIT INT TERM

# Distribution detection
detect_distro() {
    print_step "Detecting Linux distribution"

    local distro_patterns=(
        "nixos:NixOS"
        "arch:Arch Linux"
        "ubuntu:Ubuntu"
        "debian:Debian"
        "catchy:Catchy OS"
    )

    # Primary detection via /etc/os-release
    if [ -f /etc/os-release ]; then
        local os_id=$(grep "^ID=" /etc/os-release | cut -d= -f2 | tr -d '"' | tr '[:upper:]' '[:lower:]')
        local os_name=$(grep "^PRETTY_NAME=" /etc/os-release | cut -d= -f2 | tr -d '"')

        for pattern in "${distro_patterns[@]}"; do
            local id="${pattern%%:*}"
            local name="${pattern##*:}"

            if [[ "$os_id" == *"$id"* ]]; then
                DETECTED_DISTRO="$name"
                DISTRO_ID="$id"
                print_success "Detected: $DETECTED_DISTRO ($os_name)"
                return 0
            fi
        done
    fi

    # Secondary detection via /etc/lsb-release
    if [ -f /etc/lsb-release ]; then
        local lsb_distro=$(grep "^DISTRIB_ID=" /etc/lsb-release | cut -d= -f2 | tr '[:upper:]' '[:lower:]')

        for pattern in "${distro_patterns[@]}"; do
            local id="${pattern%%:*}"
            local name="${pattern##*:}"

            if [[ "$lsb_distro" == *"$id"* ]]; then
                DETECTED_DISTRO="$name"
                DISTRO_ID="$id"
                print_success "Detected: $DETECTED_DISTRO (via lsb-release)"
                return 0
            fi
        done
    fi

    # Tertiary detection via package manager
    if command -v nix-env >/dev/null 2>&1; then
        DETECTED_DISTRO="NixOS"
        DISTRO_ID="nixos"
        print_success "Detected: NixOS (via nix-env)"
        return 0
    elif command -v pacman >/dev/null 2>&1; then
        DETECTED_DISTRO="Arch Linux"
        DISTRO_ID="arch"
        print_success "Detected: Arch Linux (via pacman)"
        return 0
    elif command -v apt-get >/dev/null 2>&1; then
        if [ -f /etc/debian_version ]; then
            DETECTED_DISTRO="Debian"
            DISTRO_ID="debian"
        else
            DETECTED_DISTRO="Ubuntu"
            DISTRO_ID="ubuntu"
        fi
        print_success "Detected: $DETECTED_DISTRO (via apt-get)"
        return 0
    fi

    print_error "Unable to detect supported Linux distribution"
    echo "Supported distributions: NixOS, Arch Linux, Ubuntu, Debian, Catchy OS"
    return 1
}

# Confirm distribution with user
confirm_distro() {
    echo ""
    echo -e "${BLUE}Detected Distribution:${NC} $DETECTED_DISTRO"
    echo ""
    read -p "Continue with this distro? (Y/n): " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        print_success "Confirmed: $DETECTED_DISTRO"
        return 0
    else
        echo ""
        echo "Select your distribution manually:"
        echo "1) NixOS"
        echo "2) Arch Linux"
        echo "3) Ubuntu"
        echo "4) Debian"
        echo "5) Catchy OS"
        echo ""

        while true; do
            read -p "Enter choice (1-5): " choice
            case $choice in
                1) DETECTED_DISTRO="NixOS"; DISTRO_ID="nixos"; break;;
                2) DETECTED_DISTRO="Arch Linux"; DISTRO_ID="arch"; break;;
                3) DETECTED_DISTRO="Ubuntu"; DISTRO_ID="ubuntu"; break;;
                4) DETECTED_DISTRO="Debian"; DISTRO_ID="debian"; break;;
                5) DETECTED_DISTRO="Catchy OS"; DISTRO_ID="catchy"; break;;
                *) print_error "Invalid choice. Please enter 1-5.";;
            esac
        done
        print_success "Selected: $DETECTED_DISTRO"
    fi
}

# Package manager mappings
declare -A PKG_MANAGERS=(
    ["nixos"]="nix-env"
    ["arch"]="user_choice"
    ["ubuntu"]="apt-get"
    ["debian"]="apt-get"
    ["catchy"]="user_choice"
)

declare -A PKG_INSTALL_CMDS=(
    ["nixos"]="nix-env -iA"
    ["arch_pacman"]="pacman -S --noconfirm"
    ["arch_yay"]="yay -S --noconfirm"
    ["ubuntu"]="apt-get install -y"
    ["debian"]="apt-get install -y"
    ["catchy_pacman"]="pacman -S --noconfirm"
    ["catchy_yay"]="yay -S --noconfirm"
)

# Package name mappings
declare -A PACKAGE_MAPPINGS=(
    # Core dependencies
    ["python3_nixos"]="python3"
    ["python3_arch"]="python"
    ["python3_arch_aur"]="python"
    ["python3_ubuntu"]="python3"
    ["python3_debian"]="python3"
    ["python3_catchy"]="python"
    ["python3_catchy_aur"]="python"

    ["nodejs_nixos"]="nodejs"
    ["nodejs_arch"]="nodejs"
    ["nodejs_arch_aur"]="nodejs-lts"
    ["nodejs_ubuntu"]="nodejs"
    ["nodejs_debian"]="nodejs"
    ["nodejs_catchy"]="nodejs"
    ["nodejs_catchy_aur"]="nodejs-lts"

    ["clang_nixos"]="clang"
    ["clang_arch"]="clang"
    ["clang_arch_aur"]="clang"
    ["clang_ubuntu"]="clang"
    ["clang_debian"]="clang"
    ["clang_catchy"]="clang"
    ["clang_catchy_aur"]="clang"

    # eBPF/BCC packages
    ["bcc_nixos"]="bcc"
    ["bcc_arch"]="bcc-tools"
    ["bcc_arch_aur"]="python-bcc"
    ["bcc_ubuntu"]="python3-bcc"
    ["bcc_debian"]="python3-bcc"
    ["bcc_catchy"]="bcc-tools"
    ["bcc_catchy_aur"]="python-bcc"

    ["build-tools_nixos"]="stdenv"
    ["build-tools_arch"]="base-devel"
    ["build-tools_arch_aur"]="base-devel"
    ["build-tools_ubuntu"]="build-essential"
    ["build-tools_debian"]="build-essential"
    ["build-tools_catchy"]="base-devel"
    ["build-tools_catchy_aur"]="base-devel"

    ["libbpf_nixos"]="libbpf"
    ["libbpf_arch"]="libbpf"
    ["libbpf_arch_aur"]="libbpf"
    ["libbpf_ubuntu"]="libbpf-dev"
    ["libbpf_debian"]="libbpf-dev"
    ["libbpf_catchy"]="libbpf"
    ["libbpf_catchy_aur"]="libbpf"

    ["elfutils_nixos"]="elfutils"
    ["elfutils_arch"]="elfutils"
    ["elfutils_arch_aur"]="elfutils"
    ["elfutils_ubuntu"]="elfutils-libelf-dev"
    ["elfutils_debian"]="elfutils-libelf-dev"
    ["elfutils_catchy"]="elfutils"
    ["elfutils_catchy_aur"]="elfutils"

    # Kernel headers for eBPF compilation
    ["kernel-headers_nixos"]="linuxHeaders"
    ["kernel-headers_arch"]="linux-headers"
    ["kernel-headers_arch_aur"]="linux-headers"
    ["kernel-headers_ubuntu"]="linux-headers-generic"
    ["kernel-headers_debian"]="linux-headers-amd64"
    ["kernel-headers_catchy"]="linux-headers"
    ["kernel-headers_catchy_aur"]="linux-headers"
)

# Get package name for distro and manager choice
get_package_name() {
    local package=$1
    local distro=$2
    local manager_choice=$3

    if [[ "$distro" == "arch" || "$distro" == "catchy" ]]; then
        if [[ "$manager_choice" == "yay" ]]; then
            echo "${PACKAGE_MAPPINGS["${package}_${distro}_aur"]}"
        else
            echo "${PACKAGE_MAPPINGS["${package}_${distro}"]}"
        fi
    else
        echo "${PACKAGE_MAPPINGS["${package}_${distro}"]}"
    fi
}

# Password collection and validation
collect_password() {
    print_step "Collecting sudo password"

    echo "This installer requires sudo privileges for package installation."
    read -s -p "Enter sudo password: " PASSWORD
    echo ""

    # Validate password
    if echo "$PASSWORD" | sudo -S whoami >/dev/null 2>&1; then
        print_success "Password verified. Proceeding with installation..."
        return 0
    else
        print_error "Invalid password. Please run the script again."
        exit 1
    fi
}

# Check if sudo is needed
check_sudo_needed() {
    # Check if we're already root
    if [ "$EUID" -eq 0 ]; then
        return 1 # No sudo needed
    fi

    # Check if any of the operations require sudo
    local packages_needed=()

    # Check for missing dependencies
    if ! command -v python3 >/dev/null 2>&1; then
        packages_needed+=("python3")
    fi

    if ! command -v node >/dev/null 2>&1; then
        packages_needed+=("nodejs")
    fi

    if ! command -v clang >/dev/null 2>&1; then
        packages_needed+=("clang")
    fi

    if [ ${#packages_needed[@]} -gt 0 ]; then
        return 0 # Sudo needed for package installation
    fi

    return 1 # No sudo needed
}

# Validate prerequisites
validate_prerequisites() {
    print_step "Validating system prerequisites"

    # Kernel version check (eBPF requires Linux 4.4+)
    local kernel_version=$(uname -r | cut -d. -f1-2)
    if command -v bc >/dev/null 2>&1; then
        if [[ $(echo "$kernel_version < 4.4" | bc -l) -eq 1 ]]; then
            print_error "eBPF requires Linux kernel 4.4 or higher. Current: $kernel_version"
            exit 1
        fi
    else
        if [[ "$kernel_version" < "4.4" ]]; then
            print_error "eBPF requires Linux kernel 4.4 or higher. Current: $kernel_version"
            exit 1
        fi
    fi
    print_success "✓ Kernel version: $kernel_version (compatible)"

    # Disk space check (minimum 1GB free)
    local available_space=$(df / | awk 'NR==2 {print $4}')
    if [[ $available_space -lt 1048576 ]]; then  # 1GB in KB
        print_error "Insufficient disk space. Minimum 1GB required, $((available_space/1024))MB available"
        exit 1
    fi
    print_success "✓ Disk space: $((available_space/1024))MB available"

    # Network connectivity check
    if ping -c 1 google.com &>/dev/null; then
        print_success "✓ Network connectivity: OK"
    else
        print_warning "⚠ No network connectivity detected. Package installation may fail."
    fi

    # Architecture check
    local arch=$(uname -m)
    if [[ "$arch" == "x86_64" ]]; then
        print_success "✓ Architecture: $arch (supported)"
    else
        print_warning "⚠ Architecture: $arch (not officially supported)"
    fi
}

# Check installed dependencies
check_dependencies() {
    print_step "Checking system dependencies"

    local dependencies=("python3" "node" "clang" "pip" "npm")
    local found=0
    local missing=()

    echo ""
    for dep in "${dependencies[@]}"; do
        if command -v "$dep" >/dev/null 2>&1; then
            local version=$($dep --version 2>/dev/null | head -n1 || echo "version unknown")
            print_success "✓ $dep available ($version)"
            ((found++))
        else
            print_warning "❌ $dep missing - will install"
            missing+=("$dep")
        fi
    done

    echo ""
    echo "Found $found of ${#dependencies[@]} required dependencies."
    echo "Missing: ${#missing[@]} packages need to be installed."

    if [ ${#missing[@]} -gt 0 ]; then
        echo ""
        echo "Missing packages will be installed:"
        for missing_dep in "${missing[@]}"; do
            echo "  - $missing_dep"
        done
        echo ""
        read -p "Install missing dependencies? (Y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            return 0
        else
            print_status "Installation cancelled by user"
            exit 0
        fi
    fi

    return 0
}

# Package manager selection for Arch/Catchy
select_package_manager() {
    if [[ "$DISTRO_ID" != "arch" && "$DISTRO_ID" != "catchy" ]]; then
        return 0
    fi

    print_step "Choose package manager for $DETECTED_DISTRO"
    echo ""
    echo "1) pacman (official repositories only)"
    echo "2) yay (AUR support for more packages)"
    echo ""

    while true; do
        read -p "Enter choice (1-2): " choice
        case $choice in
            1)
                PKG_MANAGER_CHOICE="pacman"
                print_success "Selected: pacman"
                break
                ;;
            2)
                PKG_MANAGER_CHOICE="yay"
                print_success "Selected: yay"

                # Check if yay is installed
                if ! command -v yay >/dev/null 2>&1; then
                    print_warning "yay not found. Installation of yay is required."
                    read -p "Install yay first? (Y/n): " -n 1 -r
                    echo
                    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                        install_yay
                    else
                        print_warning "Falling back to pacman"
                        PKG_MANAGER_CHOICE="pacman"
                    fi
                fi
                break
                ;;
            *)
                print_error "Invalid choice. Please enter 1 or 2."
                ;;
        esac
    done
}

# Install yay for Arch/Catchy
install_yay() {
    print_status "Installing yay AUR helper..."

    if ! command -v git >/dev/null 2>&1; then
        print_status "Installing git first..."
        echo "$PASSWORD" | sudo -S pacman -S --noconfirm git
    fi

    if ! command -v base-devel >/dev/null 2>&1; then
        print_status "Installing base-devel..."
        echo "$PASSWORD" | sudo -S pacman -S --noconfirm base-devel
    fi

    # Create temp directory for yay installation
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"

    print_status "Cloning yay..."
    git clone https://aur.archlinux.org/yay.git

    cd yay
    print_status "Building and installing yay..."
    echo "$PASSWORD" | sudo -S makepkg -si --noconfirm

    # Cleanup
    cd /
    rm -rf "$temp_dir"

    if command -v yay >/dev/null 2>&1; then
        print_success "✓ yay installed successfully"
    else
        print_error "Failed to install yay"
        PKG_MANAGER_CHOICE="pacman"
    fi
}

# Update package cache
update_package_cache() {
    print_step "Updating package caches"

    local install_cmd=""

    case "$DISTRO_ID" in
        "arch"|"catchy")
            if [[ "$PKG_MANAGER_CHOICE" == "yay" ]]; then
                install_cmd="yay -Syu --noconfirm"
            else
                install_cmd="sudo pacman -Syu --noconfirm"
            fi
            ;;
        "ubuntu"|"debian")
            install_cmd="echo \"$PASSWORD\" | sudo -S apt-get update"
            ;;
        "nixos")
            print_status "NixOS doesn't require explicit cache updates"
            return 0
            ;;
        *)
            print_error "Unsupported distro for package cache update"
            return 1
            ;;
    esac

    print_status "Updating packages..."
    if eval "$install_cmd"; then
        print_success "✓ Package cache updated"
    else
        print_warning "⚠ Package cache update failed (continuing)"
    fi
}

# Install packages with error handling
install_packages() {
    local packages=("$@")
    local install_cmd=""
    local manager_suffix=""

    case "$DISTRO_ID" in
        "arch"|"catchy")
            manager_suffix="_${PKG_MANAGER_CHOICE}"
            ;;
        *)
            manager_suffix=""
            ;;
    esac

    install_cmd="${PKG_INSTALL_CMDS["${DISTRO_ID}${manager_suffix}"]}"

    if [ -z "$install_cmd" ]; then
        print_error "No install command found for $DISTRO_ID"
        return 1
    fi

    for package in "${packages[@]}"; do
        local package_name=$(get_package_name "$package" "$DISTRO_ID" "$PKG_MANAGER_CHOICE")

        if [ -z "$package_name" ]; then
            print_warning "⚠ No package name mapping for $package on $DETECTED_DISTRO"
            continue
        fi

        print_status "Installing $package_name..."

        # Construct the full install command
        local full_install_cmd="$install_cmd $package_name"

        # Add sudo password for non-yay commands
        if [[ "$PKG_MANAGER_CHOICE" != "yay" ]]; then
            full_install_cmd="echo \"$PASSWORD\" | sudo -S $install_cmd $package_name"
        fi

        if eval "$full_install_cmd"; then
            print_success "✓ $package_name installed"
        else
            print_error "❌ Failed to install $package_name"
            handle_package_install_error "$package_name" "$DISTRO_ID"
        fi
    done
}

# Handle package installation errors
handle_package_install_error() {
    local package_name=$1
    local distro_id=$2

    echo ""
    echo "Choose recovery option for $package_name:"
    echo "1) Try alternative package name"
    echo "2) Show manual installation instructions"
    echo "3) Continue without this package (limited functionality)"
    echo "4) Stop installation"
    echo ""

    while true; do
        read -p "Choose option (1-4): " choice
        case $choice in
            1)
                print_status "Trying alternative package names..."
                try_alternative_packages "$package_name" "$distro_id"
                break
                ;;
            2)
                show_manual_instructions "$package_name" "$distro_id"
                break
                ;;
            3)
                print_warning "Continuing without $package_name (limited functionality)"
                break
                ;;
            4)
                print_status "Installation stopped by user"
                exit 1
                ;;
            *)
                print_error "Invalid choice. Please enter 1-4."
                ;;
        esac
    done
}

# Try alternative package names
try_alternative_packages() {
    local package_name=$1
    local distro_id=$2

    local alternatives=()

    case "$package_name" in
        "python3")
            alternatives=("python" "python3.11" "python3.10")
            ;;
        "nodejs")
            alternatives=("node" "node-lts")
            ;;
        "clang")
            alternatives=("llvm" "clang-15" "clang-14")
            ;;
        *)
            print_warning "No known alternatives for $package_name"
            return 1
            ;;
    esac

    for alt_pkg in "${alternatives[@]}"; do
        print_status "Trying alternative: $alt_pkg"

        if [[ "$PKG_MANAGER_CHOICE" == "yay" ]]; then
            if yay -S --noconfirm "$alt_pkg" 2>/dev/null; then
                print_success "✓ Alternative $alt_pkg installed successfully"
                return 0
            fi
        else
            if echo "$PASSWORD" | sudo -S ${PKG_INSTALL_CMDS["${distro_id}_${PKG_MANAGER_CHOICE}"]} "$alt_pkg" 2>/dev/null; then
                print_success "✓ Alternative $alt_pkg installed successfully"
                return 0
            fi
        fi
    done

    print_warning "No alternatives worked for $package_name"
    return 1
}

# Show manual installation instructions
show_manual_instructions() {
    local package_name=$1
    local distro_id=$2

    echo ""
    echo -e "${YELLOW}Manual Installation Instructions for $package_name:${NC}"
    echo ""

    case "$distro_id" in
        "arch"|"catchy")
            echo "For pacman:"
            echo "  sudo pacman -S $package_name"
            echo ""
            echo "For yay (if available):"
            echo "  yay -S $package_name"
            ;;
        "ubuntu"|"debian")
            echo "  sudo apt-get update"
            echo "  sudo apt-get install $package_name"
            ;;
        "nixos")
            echo "  sudo nix-env -iA nixpkgs.$package_name"
            ;;
        *)
            echo "Consult your distribution's package manager documentation"
            ;;
    esac

    echo ""
    echo "After manual installation, run this script again."
    echo ""

    read -p "Press Enter to continue..."
}

# Continue with the rest of the installation (file copying, etc.)
continue_application_installation() {
    print_step "Installing NetViz application files"

    # Installation directory
    INSTALL_DIR="/opt/netviz"

    # Check for existing installation
    if [ -d "$INSTALL_DIR" ]; then
        print_warning "Existing installation found at $INSTALL_DIR"
        read -p "Remove and reinstall? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Installation cancelled"
            exit 1
        fi
        echo "$PASSWORD" | sudo -S rm -rf "$INSTALL_DIR"
    fi

    # Create installation directory
    print_status "Installing to $INSTALL_DIR..."
    echo "$PASSWORD" | sudo -S mkdir -p "$INSTALL_DIR"

    # Copy files (from current directory structure)
    print_status "Copying application files..."

    # Copy eBPF program
    if [ -d "ebpf" ]; then
        echo "$PASSWORD" | sudo -S cp -r ebpf "$INSTALL_DIR/"
        print_status "✓ eBPF program copied"
    fi

    # Copy server
    if [ -d "server" ]; then
        echo "$PASSWORD" | sudo -S cp -r server "$INSTALL_DIR/"
        print_status "✓ Server backend copied"
    fi

    # Copy GUI
    if [ -d "gui" ]; then
        echo "$PASSWORD" | sudo -S cp -r gui "$INSTALL_DIR/"
        print_status "✓ GUI application copied"
    fi

    # Copy scripts
    if [ -d "scripts" ]; then
        echo "$PASSWORD" | sudo -S cp -r scripts "$INSTALL_DIR/"
        print_status "✓ Scripts copied"
    fi

    # Copy documentation
    if [ -f "README.md" ]; then
        echo "$PASSWORD" | sudo -S cp README.md "$INSTALL_DIR/"
        print_status "✓ Documentation copied"
    fi

    # Setup Python environment
    setup_python_environment

    # Setup Node.js environment
    setup_nodejs_environment

    # Create system integration
    create_system_integration

    # Validate installation
    validate_installation
}

# Setup Python environment
setup_python_environment() {
    print_step "Setting up Python environment"

    print_status "Setting up Python environment..."
    echo "$PASSWORD" | sudo -S cd "$INSTALL_DIR/server" 2>/dev/null || cd "$INSTALL_DIR/server"

    # Create virtual environment
    print_status "Creating Python virtual environment..."
    echo "$PASSWORD" | sudo -S python3 -m venv venv
    echo "$PASSWORD" | sudo -S bash -c "source venv/bin/activate && pip install --upgrade pip"

    # Install Python dependencies
    if [ -f "requirements.txt" ]; then
        print_status "Installing Python dependencies..."
        echo "$PASSWORD" | sudo -S bash -c "source venv/bin/activate && pip install -r requirements.txt"
        print_success "✓ Python dependencies installed"
    else
        print_warning "requirements.txt not found"
    fi
}

# Setup Node.js environment
setup_nodejs_environment() {
    print_step "Setting up Node.js environment"

    echo "$PASSWORD" | sudo -S cd "$INSTALL_DIR/gui" 2>/dev/null || cd "$INSTALL_DIR/gui"

    if [ -f "package.json" ]; then
        print_status "Installing Node.js dependencies..."
        echo "$PASSWORD" | sudo -S bash -c "npm install"
        print_success "✓ Node.js dependencies installed"
    else
        print_warning "package.json not found"
    fi
}

# Create system integration (desktop entry, systemd service)
create_system_integration() {
    print_step "Creating system integration"

    create_desktop_entry
    create_startup_scripts
    set_permissions

    if [ "$EUID" -eq 0 ] || [ -n "$PASSWORD" ]; then
        create_systemd_service
        create_symlinks
    fi
}

# Create desktop entry
create_desktop_entry() {
    print_status "Creating desktop entry..."

    # Create desktop applications directory
    echo "$PASSWORD" | sudo -S mkdir -p /usr/share/applications

    # Create icon placeholder (if no icon exists)
    if [ ! -f "$INSTALL_DIR/gui/icon.png" ]; then
        print_status "Creating default icon..."
        # Create a simple text-based icon placeholder
        echo "$PASSWORD" | sudo -S bash -c "cat > '$INSTALL_DIR/gui/icon.svg' << 'ICON_EOF'
<svg width=\"256\" height=\"256\" xmlns=\"http://www.w3.org/2000/svg\">
  <rect width=\"256\" height=\"256\" fill=\"#0d1117\"/>
  <text x=\"128\" y=\"128\" text-anchor=\"middle\" dominant-baseline=\"middle\" font-family=\"Arial\" font-size=\"64\" fill=\"#58a6ff\">🌐</text>
  <text x=\"128\" y=\"180\" text-anchor=\"middle\" dominant-baseline=\"middle\" font-family=\"Arial\" font-size=\"20\" fill=\"#c9d1d9\">NetViz</text>
</svg>
ICON_EOF"

        # Convert to PNG if rsvg-convert is available
        if command -v rsvg-convert &> /dev/null; then
            echo "$PASSWORD" | sudo -S bash -c "rsvg-convert '$INSTALL_DIR/gui/icon.svg' -o '$INSTALL_DIR/gui/icon.png'"
        else
            echo "$PASSWORD" | sudo -S bash -c "ln -sf icon.svg '$INSTALL_DIR/gui/icon.png'"
        fi
    fi

    # Create desktop entry
    echo "$PASSWORD" | sudo -S bash -c "cat > /usr/share/applications/netviz.desktop << 'EOL'
[Desktop Entry]
Name=NetViz - Network Threat Visualizer
Comment=Real-time network connection monitoring with eBPF
Exec=/opt/netviz/gui/start.sh
Icon=/opt/netviz/gui/icon.png
Type=Application
Categories=Network;Security;System;
Terminal=false
StartupNotify=true
EOL"

    print_success "✓ Desktop entry created"
}

# Create startup scripts
create_startup_scripts() {
    print_status "Creating startup script..."

    # Create GUI startup script
    echo "$PASSWORD" | sudo -S bash -c "cat > '$INSTALL_DIR/gui/start.sh' << 'EOL'
#!/bin/bash

# NetViz GUI Startup Script

SCRIPT_DIR=\"\$( cd \"\$( dirname \"\${BASH_SOURCE[0]}\" )\" && pwd )\"
cd \"\$SCRIPT_DIR\"

# Check if server is running
if ! pgrep -f \"python.*main.py\" > /dev/null; then
    echo \"Starting NetViz server...\"
    cd ../server
    source venv/bin/activate
    python main.py &
    SERVER_PID=\$!
    echo \"Server started (PID: \$SERVER_PID)\"
    cd ../gui
fi

# Wait a moment for server to start
sleep 2

# Start Electron
if [ -f \"package.json\" ] && [ -d \"node_modules\" ]; then
    if command -v npm &> /dev/null; then
        npm run electron
    else
        echo \"Error: npm not found\"
        exit 1
    fi
else
    echo \"Error: Node.js dependencies not installed\"
    exit 1
fi
EOL"

    echo "$PASSWORD" | sudo -S chmod +x "$INSTALL_DIR/gui/start.sh"

    # Create main run script
    print_status "Creating main run script..."

    echo "$PASSWORD" | sudo -S bash -c "cat > '$INSTALL_DIR/run.sh' << 'EOL'
#!/bin/bash

# eBPF Network Threat Visualizer - Main Run Script

SCRIPT_DIR=\"\$( cd \"\$( dirname \"\${BASH_SOURCE[0]}\" )\" && pwd )\"
cd \"\$SCRIPT_DIR\"

echo \"🚀 Starting eBPF Network Threat Visualizer...\"
echo \"\"

# Check privileges
if [ \"\$EUID\" -ne 0 ]; then
    echo \"⚠️  Warning: Not running as root\"
    echo \"   eBPF monitoring will not work without root privileges\"
    echo \"   Run with 'sudo \$0' for full functionality\"
    echo \"\"
fi

# Function to cleanup on exit
cleanup() {
    echo \"\"
    echo \"🛑 Shutting down NetViz...\"

    # Kill server process
    pkill -f \"python.*main.py\" 2>/dev/null || true

    # Kill any remaining NetViz processes
    pkill -f \"netviz\" 2>/dev/null || true

    exit 0
}

# Set up signal handlers
trap cleanup SIGINT SIGTERM

# Start backend server
echo \"📡 Starting backend server...\"

# Check and setup virtual environment
if [ -d \"server/venv\" ]; then
    source server/venv/bin/activate
else
    echo \"❌ Error: Python virtual environment not found\"
    echo \"   Please run the installation script first\"
    exit 1
fi

# Start server
cd server
python main.py &
SERVER_PID=\$!
echo \"   Server PID: \$SERVER_PID\"

cd ..

# Wait for server to initialize
echo \"   Waiting for server to start...\"
sleep 3

# Check if server started successfully
if ! kill -0 \$SERVER_PID 2>/dev/null; then
    echo \"❌ Error: Server failed to start\"
    echo \"   Check logs for error messages\"
    exit 1
fi

# Start GUI
echo \"🖥️  Starting GUI...\"
cd gui

# Use the startup script
if [ -f \"start.sh\" ]; then
    ./start.sh
else
    echo \"❌ Error: GUI startup script not found\"
    cleanup
    exit 1
fi
EOL"

    echo "$PASSWORD" | sudo -S chmod +x "$INSTALL_DIR/run.sh"
}

# Create systemd service
create_systemd_service() {
    print_status "Creating systemd service..."

    echo "$PASSWORD" | sudo -S bash -c "cat > /etc/systemd/system/netviz.service << 'EOL'
[Unit]
Description=eBPF Network Threat Visualizer Backend
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/netviz/server
ExecStart=/opt/netviz/server/venv/bin/python main.py
Restart=always
RestartSec=10
Environment=NETVIZ_PORT=8080

[Install]
WantedBy=multi-user.target
EOL"

    echo "$PASSWORD" | sudo -S systemctl daemon-reload
    print_success "✓ Systemd service created"
}

# Set permissions
set_permissions() {
    print_status "Setting file permissions..."
    echo "$PASSWORD" | sudo -S chown -R root:root "$INSTALL_DIR"
    print_success "✓ File permissions set"
}

# Create symlinks
create_symlinks() {
    print_status "Creating command-line shortcut..."
    echo "$PASSWORD" | sudo -S ln -sf "$INSTALL_DIR/run.sh" /usr/local/bin/netviz
    print_success "✓ Command-line shortcut created: /usr/local/bin/netviz"
}

# Validate installation
validate_installation() {
    print_step "Validating installation"

    # Test Python environment
    if [ -d "$INSTALL_DIR/server/venv" ]; then
        print_success "✓ Python virtual environment exists"

        # Test BCC module if possible
        if echo "$PASSWORD" | sudo -S bash -c "source '$INSTALL_DIR/server/venv/bin/activate' && python -c 'import bcc; print(\"✓ BCC module working\")' 2>/dev/null"; then
            print_success "✓ BCC module working"
        else
            print_warning "⚠ BCC module issue detected"
        fi
    else
        print_error "❌ Python virtual environment missing"
    fi

    # Test Node.js environment
    if [ -f "$INSTALL_DIR/gui/package.json" ] && [ -d "$INSTALL_DIR/gui/node_modules" ]; then
        print_success "✓ Node.js environment setup complete"
    else
        print_error "❌ Node.js environment issue detected"
    fi

    # Test desktop entry
    if [ -f "/usr/share/applications/netviz.desktop" ]; then
        print_success "✓ Desktop entry created"

        if command -v desktop-file-validate >/dev/null 2>&1; then
            if desktop-file-validate /usr/share/applications/netviz.desktop 2>/dev/null; then
                print_success "✓ Desktop entry valid"
            else
                print_warning "⚠ Desktop entry validation failed"
            fi
        fi
    fi

    # Test command-line shortcut
    if [ -L "/usr/local/bin/netviz" ]; then
        print_success "✓ Command-line shortcut created"
    fi

    # Test systemd service
    if [ -f "/etc/systemd/system/netviz.service" ]; then
        print_success "✓ Systemd service created"
    fi
}

# Display final summary
display_final_summary() {
    echo ""
    print_success "🎉 Installation completed successfully!"
    echo ""
    echo -e "${BLUE}🚀 To run NetViz:${NC}"
    if [ "$EUID" -eq 0 ] || [ -n "$PASSWORD" ]; then
        echo "   sudo netviz"
        echo "   or: sudo $INSTALL_DIR/run.sh"
    else
        echo "   $INSTALL_DIR/run.sh"
        echo "   (Limited functionality without root)"
    fi
    echo ""
    if [ "$EUID" -eq 0 ] || [ -n "$PASSWORD" ]; then
        echo -e "${BLUE}🔧 Service Management:${NC}"
        echo "   sudo systemctl start netviz   # Start service"
        echo "   sudo systemctl stop netviz    # Stop service"
        echo "   sudo systemctl enable netviz   # Enable on boot"
        echo ""
        echo -e "${BLUE}🖥️  GUI:${NC}"
        echo "   NetViz should appear in your applications menu"
        echo ""
    fi

    echo -e "${BLUE}📋 Installation Summary:${NC}"
    echo "   Distribution: $DETECTED_DISTRO"
    echo "   Package Manager: $([ "$PKG_MANAGER_CHOICE" = "" ] && echo "Default" || echo "$PKG_MANAGER_CHOICE")"
    echo "   Installation Directory: $INSTALL_DIR"
    echo ""

    print_success "Installation complete!"
}

# Main execution function
main() {
    # Step 1: Distribution detection and confirmation
    CURRENT_STEP=1
    if ! detect_distro; then
        exit 1
    fi

    confirm_distro

    # Step 2: Password collection (if needed)
    CURRENT_STEP=2
    if check_sudo_needed; then
        collect_password
    else
        print_status "Sudo not required - all dependencies available"
    fi

    # Step 3: Prerequisites validation
    CURRENT_STEP=3
    validate_prerequisites

    # Step 4: Package manager selection
    CURRENT_STEP=4
    select_package_manager

    # Step 5: Dependency checking and confirmation
    CURRENT_STEP=5
    check_dependencies

    # Step 6: Update package cache
    CURRENT_STEP=6
    update_package_cache

    # Step 7: Install core packages if needed
    CURRENT_STEP=7
    install_missing_packages

    # Step 8: Application installation
    CURRENT_STEP=8
    continue_application_installation

    # Display final summary
    display_final_summary
}

# Install missing packages
install_missing_packages() {
    print_step "Installing missing packages"

    local packages_to_install=()

    # Check for Python
    if ! command -v python3 >/dev/null 2>&1; then
        packages_to_install+=("python3")
    fi

    # Check for Node.js
    if ! command -v node >/dev/null 2>&1; then
        packages_to_install+=("nodejs")
    fi

    # Check for clang
    if ! command -v clang >/dev/null 2>&1; then
        packages_to_install+=("clang")
    fi

    # Check for pip
    if ! command -v pip >/dev/null 2>&1 && ! command -v pip3 >/dev/null 2>&1; then
        packages_to_install+=("pip")
    fi

    # Check for npm
    if ! command -v npm >/dev/null 2>&1; then
        packages_to_install+=("npm")
    fi

    # Always add eBPF dependencies for full functionality
    packages_to_install+=("bcc" "build-tools" "libbpf" "elfutils" "kernel-headers")

    if [ ${#packages_to_install[@]} -gt 0 ]; then
        echo "Packages to install: ${packages_to_install[*]}"
        install_packages "${packages_to_install[@]}"
    else
        print_success "✓ All required packages already available"
    fi
}

# Script execution starts here
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi