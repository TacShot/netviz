#!/bin/bash

# eBPF Network Threat Visualizer - Installation Script

set -e

echo "🔧 Installing eBPF Network Threat Visualizer..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_warning "This script works best with root privileges."
    print_warning "Without root, eBPF monitoring will not function."
    echo ""
    read -p "Continue without root? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Please run with sudo: sudo ./install.sh"
        exit 1
    fi
fi

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
    rm -rf "$INSTALL_DIR"
fi

# Create installation directory
print_status "Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"

# Copy files (from current directory structure)
print_status "Copying application files..."

# Copy eBPF program
if [ -d "ebpf" ]; then
    cp -r ebpf "$INSTALL_DIR/"
    print_status "✓ eBPF program copied"
fi

# Copy server
if [ -d "server" ]; then
    cp -r server "$INSTALL_DIR/"
    print_status "✓ Server backend copied"
fi

# Copy GUI
if [ -d "gui" ]; then
    cp -r gui "$INSTALL_DIR/"
    print_status "✓ GUI application copied"
fi

# Copy scripts
if [ -d "scripts" ]; then
    cp -r scripts "$INSTALL_DIR/"
    print_status "✓ Scripts copied"
fi

# Copy documentation
if [ -f "README.md" ]; then
    cp README.md "$INSTALL_DIR/"
    print_status "✓ Documentation copied"
fi

# Setup Python environment
print_status "Setting up Python environment..."
cd "$INSTALL_DIR/server"

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install Python dependencies
if [ -f "requirements.txt" ]; then
    pip install --upgrade pip
    pip install -r requirements.txt
    print_success "✓ Python dependencies installed"
else
    print_warning "requirements.txt not found"
fi

deactivate

# Setup Node.js environment
cd "$INSTALL_DIR/gui"
if [ -f "package.json" ]; then
    print_status "Installing Node.js dependencies..."
    npm install
    print_success "✓ Node.js dependencies installed"
else
    print_warning "package.json not found"
fi

# Create systemd service (if running as root)
if [ "$EUID" -eq 0 ]; then
    print_status "Creating systemd service..."
    cat > /etc/systemd/system/netviz.service << 'EOL'
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
EOL

    systemctl daemon-reload
    print_success "✓ Systemd service created"
else
    print_warning "Skipping systemd service (not running as root)"
fi

# Create desktop entry
print_status "Creating desktop entry..."
mkdir -p /usr/share/applications

# Create icon placeholder (if no icon exists)
if [ ! -f "$INSTALL_DIR/gui/icon.png" ]; then
    print_status "Creating default icon..."
    # Create a simple text-based icon placeholder
    cat > "$INSTALL_DIR/gui/icon.svg" << 'ICON_EOF'
<svg width="256" height="256" xmlns="http://www.w3.org/2000/svg">
  <rect width="256" height="256" fill="#0d1117"/>
  <text x="128" y="128" text-anchor="middle" dominant-baseline="middle" font-family="Arial" font-size="64" fill="#58a6ff">🌐</text>
  <text x="128" y="180" text-anchor="middle" dominant-baseline="middle" font-family="Arial" font-size="20" fill="#c9d1d9">NetViz</text>
</svg>
ICON_EOF
    # Convert to PNG if rsvg-convert is available
    if command -v rsvg-convert &> /dev/null; then
        rsvg-convert "$INSTALL_DIR/gui/icon.svg" -o "$INSTALL_DIR/gui/icon.png"
    else
        ln -sf icon.svg "$INSTALL_DIR/gui/icon.png"
    fi
fi

# Create desktop entry
cat > /usr/share/applications/netviz.desktop << 'EOL'
[Desktop Entry]
Name=NetViz - Network Threat Visualizer
Comment=Real-time network connection monitoring with eBPF
Exec=/opt/netviz/gui/start.sh
Icon=/opt/netviz/gui/icon.png
Type=Application
Categories=Network;Security;System;
Terminal=false
StartupNotify=true
EOL

print_success "✓ Desktop entry created"

# Create startup script
print_status "Creating startup script..."
cat > "$INSTALL_DIR/gui/start.sh" << 'EOL'
#!/bin/bash

# NetViz GUI Startup Script

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Check if server is running
if ! pgrep -f "python.*main.py" > /dev/null; then
    echo "Starting NetViz server..."
    cd ../server
    source venv/bin/activate
    python main.py &
    SERVER_PID=$!
    echo "Server started (PID: $SERVER_PID)"
    cd ../gui
fi

# Wait a moment for server to start
sleep 2

# Start Electron
if [ -f "package.json" ] && [ -d "node_modules" ]; then
    if command -v npm &> /dev/null; then
        npm run electron
    else
        echo "Error: npm not found"
        exit 1
    fi
else
    echo "Error: Node.js dependencies not installed"
    exit 1
fi
EOL

chmod +x "$INSTALL_DIR/gui/start.sh"

# Create main run script
print_status "Creating main run script..."
cat > "$INSTALL_DIR/run.sh" << 'EOL'
#!/bin/bash

# eBPF Network Threat Visualizer - Main Run Script

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo "🚀 Starting eBPF Network Threat Visualizer..."
echo ""

# Check privileges
if [ "$EUID" -ne 0 ]; then
    echo "⚠️  Warning: Not running as root"
    echo "   eBPF monitoring will not work without root privileges"
    echo "   Run with 'sudo $0' for full functionality"
    echo ""
fi

# Function to cleanup on exit
cleanup() {
    echo ""
    echo "🛑 Shutting down NetViz..."

    # Kill server process
    pkill -f "python.*main.py" 2>/dev/null || true

    # Kill any remaining NetViz processes
    pkill -f "netviz" 2>/dev/null || true

    exit 0
}

# Set up signal handlers
trap cleanup SIGINT SIGTERM

# Start backend server
echo "📡 Starting backend server..."
cd server

# Check and setup virtual environment
if [ -d "venv" ]; then
    source venv/bin/activate
else
    echo "❌ Error: Python virtual environment not found"
    echo "   Please run the installation script first"
    exit 1
fi

# Start server
python main.py &
SERVER_PID=$!
echo "   Server PID: $SERVER_PID"

cd ..

# Wait for server to initialize
echo "   Waiting for server to start..."
sleep 3

# Check if server started successfully
if ! kill -0 $SERVER_PID 2>/dev/null; then
    echo "❌ Error: Server failed to start"
    echo "   Check logs for error messages"
    exit 1
fi

# Start GUI
echo "🖥️  Starting GUI..."
cd gui

# Use the startup script
if [ -f "start.sh" ]; then
    ./start.sh
else
    echo "❌ Error: GUI startup script not found"
    cleanup
    exit 1
fi
EOL

chmod +x "$INSTALL_DIR/run.sh"

# Set permissions
if [ "$EUID" -eq 0 ]; then
    chown -R root:root "$INSTALL_DIR"
    print_success "✓ File permissions set"
fi

# Create symlink for easy access
if [ "$EUID" -eq 0 ]; then
    ln -sf "$INSTALL_DIR/run.sh" /usr/local/bin/netviz
    print_success "✓ Command-line shortcut created: /usr/local/bin/netviz"
fi

print_success "Installation completed successfully!"
echo ""
echo -e "${BLUE}🚀 To run NetViz:${NC}"
if [ "$EUID" -eq 0 ]; then
    echo "   sudo netviz"
    echo "   or: sudo $INSTALL_DIR/run.sh"
else
    echo "   $INSTALL_DIR/run.sh"
    echo "   (Limited functionality without root)"
fi
echo ""
if [ "$EUID" -eq 0 ]; then
    echo -e "${BLUE}🔧 Service Management:${NC}"
    echo "   sudo systemctl start netviz   # Start service"
    echo "   sudo systemctl stop netviz    # Stop service"
    echo "   sudo systemctl enable netviz   # Enable on boot"
    echo ""
    echo -e "${BLUE}🖥️  GUI:${NC}"
    echo "   NetViz should appear in your applications menu"
fi

print_success "Installation complete!"