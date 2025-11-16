#!/bin/bash

set -e

# Colors for output
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Starting eBPF Network Threat Visualizer in Development Mode...${NC}"

# Check for root privileges for eBPF
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}⚠️  Warning: Not running as root. eBPF network monitoring will NOT function without sudo.${NC}"
    echo -e "${YELLOW}   Attempting to start backend with sudo for eBPF functionality. You may be prompted for a password.${NC}"
    RUN_AS_ROOT=false
else
    echo -e "${GREEN}✓ Running as root. eBPF network monitoring will be enabled.${NC}"
    RUN_AS_ROOT=true
fi

# --- Python Backend Setup ---
echo -e "${GREEN}🐍 Setting up Python backend...${NC}"
if [ ! -d "server/venv" ]; then
    echo -e "${BLUE}Creating Python virtual environment...${NC}"
    python3 -m venv server/venv --system-site-packages
fi

source server/venv/bin/activate
echo -e "${BLUE}Installing/updating Python dependencies...${NC}"
pip install -r server/requirements.txt

# --- Check for BCC system dependency ---
echo -e "${GREEN}🔎 Checking for eBPF (BCC) system dependency...${NC}"
if ! python -c "import bcc" &> /dev/null; then
    echo -e "${RED}❌ Error: Python 'bcc' module not found.${NC}"
    echo -e "${YELLOW}This project requires the BCC tools for eBPF, which must be installed at the system level.${NC}"
    echo -e "${YELLOW}Please run the system installation script to install it:${NC}"
    echo -e "  ${CYAN}sudo ./scripts/install.sh${NC}"
    echo -e "${YELLOW}After the installation, re-run this script.${NC}"
    exit 1
else
    echo -e "${GREEN}✓ Python 'bcc' module found.${NC}"
fi

# --- Node.js GUI Setup ---
echo -e "${GREEN}💻 Setting up Node.js GUI...${NC}"
cd gui
if [ ! -d "node_modules" ]; then
    echo -e "${BLUE}Installing Node.js dependencies...${NC}"
    npm install
fi
cd ..

# --- Run Application ---
echo -e "${GREEN}📡 Starting backend server...${NC}"
cd server
VENV_PYTHON=$(pwd)/venv/bin/python
if $RUN_AS_ROOT; then
    "$VENV_PYTHON" main.py & # Already root, no need for sudo
else
    # Not running as root, so use sudo for the backend
    # First, prompt for password and refresh sudo timestamp
    echo -e "${BLUE}Authenticating for backend server...${NC}"
    sudo -v # This will prompt for password and block until entered
    # Now run the backend with sudo in the background
    sudo "$VENV_PYTHON" main.py &
fi
SERVER_PID=$!
cd ..

# Wait a moment for server to start
sleep 2

echo -e "${GREEN}🖥️  Starting GUI in dev mode...${NC}"
cd gui
npm run electron-start &
GUI_PID=$!
cd ..

# --- Cleanup ---
cleanup() {
    echo -e "${GREEN}🛑 Shutting down...${NC}"
    kill $SERVER_PID 2>/dev/null || true
    # concurrently, which is started by npm run electron-start, should handle its children
    kill $GUI_PID 2>/dev/null || true
    exit 0
}

trap cleanup SIGINT SIGTERM

echo -e "${BLUE}✅ Application is running. Press Ctrl+C to stop.${NC}"
wait
