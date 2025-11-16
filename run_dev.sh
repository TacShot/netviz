#!/bin/bash

set -e

# Colors for output
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Starting eBPF Network Threat Visualizer in Development Mode...${NC}"

# --- Python Backend Setup ---
echo -e "${GREEN}🐍 Setting up Python backend...${NC}"
if [ ! -d "server/venv" ]; then
    echo -e "${BLUE}Creating Python virtual environment...${NC}"
    python3 -m venv server/venv
fi

source server/venv/bin/activate
echo -e "${BLUE}Installing/updating Python dependencies...${NC}"
pip install -r server/requirements.txt

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
python main.py &
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
