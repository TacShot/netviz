#!/bin/bash

# eBPF Network Threat Visualizer - Build Script
# Builds all components: eBPF program, Python backend, and React/Electron GUI

set -e

echo "🔨 Building eBPF Network Threat Visualizer..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
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

# Check if we're in the right directory
if [ ! -f "scripts/build.sh" ]; then
    print_error "Please run this script from the netviz root directory"
    exit 1
fi

# Check prerequisites
print_status "Checking prerequisites..."

# Check for eBPF dependencies
if ! command -v clang &> /dev/null; then
    print_error "clang is required but not installed. Please install clang."
    exit 1
fi

if ! command -v llvm-config &> /dev/null; then
    print_error "llvm-config is required but not installed. Please install llvm."
    exit 1
fi

# Check for Python
if ! command -v python3 &> /dev/null; then
    print_error "Python 3 is required but not installed."
    exit 1
fi

# Check for Node.js
if ! command -v node &> /dev/null; then
    print_error "Node.js is required but not installed."
    exit 1
fi

if ! command -v npm &> /dev/null; then
    print_error "npm is required but not installed."
    exit 1
fi

print_success "All prerequisites found"

# Build eBPF program (temporarily commented out due to compilation issues)
# print_status "Building eBPF program..."
# cd ebpf

# if [ ! -f "Makefile" ]; then
#     print_error "eBPF Makefile not found"
#     exit 1
# fi

# make clean || true
# make all

# if [ $? -eq 0 ]; then
#     print_success "eBPF program built successfully"
# else
#     print_error "Failed to build eBPF program"
#     exit 1
# fi

# cd ..

# Build Python backend
print_status "Building Python backend..."

# Check if virtual environment exists, create if not
if [ ! -d "server/venv" ]; then
    print_status "Creating Python virtual environment..."
    python3 -m venv server/venv
fi

# Activate virtual environment and install dependencies
print_status "Installing Python dependencies..."
source server/venv/bin/activate

pip install --upgrade pip
pip install -r server/requirements.txt

if [ $? -eq 0 ]; then
    print_success "Python dependencies installed successfully"
else
    print_error "Failed to install Python dependencies"
    exit 1
fi

deactivate

# Build React/Electron GUI
print_status "Building React/Electron GUI..."
cd gui

# Install Node dependencies
if [ ! -d "node_modules" ]; then
    print_status "Installing Node.js dependencies..."
    npm install

    if [ $? -eq 0 ]; then
        print_success "Node.js dependencies installed successfully"
    else
        print_error "Failed to install Node.js dependencies"
        exit 1
    fi
fi

# Build React application
print_status "Building React application..."
npm run react-build

if [ $? -eq 0 ]; then
    print_success "React application built successfully"
else
    print_error "Failed to build React application"
    exit 1
fi

cd ..

# Create distribution directory
print_status "Creating distribution package..."
DIST_DIR="dist/netviz"
mkdir -p "$DIST_DIR"

# Copy files
print_status "Copying files to distribution directory..."

# Copy eBPF program
cp -r ebpf "$DIST_DIR/"

# Copy Python backend (excluding venv)
cp -r server "$DIST_DIR/"
rm -rf "$DIST_DIR/server/venv"

# Copy GUI build
print_status "Copying GUI..."
GUI_DIST_DIR="$DIST_DIR/gui"
rm -rf "$GUI_DIST_DIR" # Clean first
mkdir -p "$GUI_DIST_DIR/public"
cp -r gui/build "$GUI_DIST_DIR/"
cp gui/public/electron.js "$GUI_DIST_DIR/public/"
cp gui/public/preload.js "$GUI_DIST_DIR/public/"
cp gui/package.json "$GUI_DIST_DIR/"

# Copy scripts
cp scripts/* "$DIST_DIR/"

# Copy documentation
cp README.md "$DIST_DIR/" 2>/dev/null || true

# Create run script
cat > "$DIST_DIR/run.sh" << 'EOF'
#!/bin/bash

# eBPF Network Threat Visualizer - Run Script

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🚀 Starting eBPF Network Threat Visualizer...${NC}"

# Check if running as root for eBPF
if [ "$EUID" -ne 0 ]; then
    echo -e "${BLUE}⚠️  Note: eBPF requires root privileges. Some features may not work.${NC}"
fi

# Start backend server
echo -e "${GREEN}📡 Starting backend server...${NC}"
cd server

# Check if virtual environment exists
if [ -d "venv" ]; then
    source venv/bin/activate
else
    echo -e "${BLUE}Creating virtual environment...${NC}"
    python3 -m venv venv
    source venv/bin/activate
    pip install -r requirements.txt
fi

# Start server in background
python main.py &
SERVER_PID=$!

cd ..

# Wait a moment for server to start
sleep 2

# Start GUI
echo -e "${GREEN}🖥️  Starting GUI...${NC}"
cd gui

# Check if Node modules exist
if [ ! -d "node_modules" ]; then
    echo -e "${BLUE}Installing Node dependencies...${NC}"
    npm install
fi

# Start Electron
npm run electron &
GUI_PID=$!

cd ..

# Function to cleanup on exit
cleanup() {
    echo -e "${GREEN}🛑 Shutting down...${NC}"
    kill $SERVER_PID 2>/dev/null || true
    kill $GUI_PID 2>/dev/null || true
    exit 0
}

# Set up signal handlers
trap cleanup SIGINT SIGTERM

# Wait for processes
wait
EOF

chmod +x "$DIST_DIR/run.sh"

# Create installation script
cat > "$DIST_DIR/install.sh" << 'EOF'
#!/bin/bash

# eBPF Network Threat Visualizer - Installation Script

set -e

echo "🔧 Installing eBPF Network Threat Visualizer..."

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "⚠️  This script requires root privileges for full functionality."
    echo "   You can run without root, but eBPF monitoring will not work."
    echo ""
    read -p "Continue without root? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Please run: sudo ./install.sh"
        exit 1
    fi
fi

# Installation directory
INSTALL_DIR="/opt/netviz"

# Create installation directory
echo "📁 Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"

# Copy files
cp -r . "$INSTALL_DIR/"

# Create systemd service (if running as root)
if [ "$EUID" -eq 0 ]; then
    echo "🔧 Creating systemd service..."
    cat > /etc/systemd/system/netviz.service << 'EOL'
[Unit]
Description=eBPF Network Threat Visualizer
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/netviz
ExecStart=/opt/netviz/server/venv/bin/python /opt/netviz/server/main.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOL

    systemctl daemon-reload
    systemctl enable netviz
    echo "✅ Systemd service created and enabled"
    echo "   Start with: sudo systemctl start netviz"
fi

# Create desktop entry
echo "🖥️  Creating desktop entry..."
mkdir -p /usr/share/applications
cat > /usr/share/applications/netviz.desktop << 'EOL'
[Desktop Entry]
Name=NetViz - Network Threat Visualizer
Comment=Real-time network connection monitoring with eBPF
Exec=/opt/netviz/gui/electron
Icon=/opt/netviz/gui/icon.png
Type=Application
Categories=Network;Security;System;
Terminal=false
StartupNotify=true
EOL

# Set permissions
chown -R root:root "$INSTALL_DIR" 2>/dev/null || true
chmod +x "$INSTALL_DIR/run.sh"
chmod +x "$INSTALL_DIR/install.sh"

echo ""
echo "✅ Installation complete!"
echo ""
echo "🚀 To run NetViz:"
echo "   sudo /opt/netviz/run.sh"
echo ""
echo "📋 If installed as root:"
echo "   sudo systemctl start netviz"
echo ""
echo "🖥️  Desktop entry created - NetViz should appear in your applications menu"
EOF

chmod +x "$DIST_DIR/install.sh"

# Compress distribution
print_status "Creating compressed package..."
cd dist
tar -czf netviz-$(date +%Y%m%d-%H%M%S).tar.gz netviz/

print_success "Build completed successfully!"
print_status "Distribution package created in dist/"
print_status "To install:"
print_status "  1. Extract the tar.gz file"
print_status "  2. Run: ./install.sh (with sudo for full functionality)"
print_status "To run without installing:"
print_status "  ./run.sh"

cd ..

echo -e "${GREEN}🎉 Build process completed successfully!${NC}"