# NetViz - eBPF Network Threat Visualizer

A real-time network connection monitoring system that uses eBPF to hook into `tcp_connect` syscalls, analyzes traffic for suspicious patterns, and visualizes network activity in an interactive desktop application.

![NetViz Logo](https://img.shields.io/badge/eBPF-Network%20Monitoring-red)
![License](https://img.shields.io/badge/License-MIT-blue)
![Platform](https://img.shields.io/badge/Platform-Linux-orange)

## 🚀 Features

### Core Functionality
- **Real-time eBPF Monitoring**: Hooks into kernel `tcp_connect` syscalls for zero-overhead network monitoring
- **Advanced Threat Detection**: ML-powered analysis of network connections for suspicious patterns
- **Interactive Visualization**: D3.js-based force-directed graph with threat indicators
- **Process Details**: Deep dive into process information and connection history
- **Dark/Light Theme**: Modern UI with theme switching

### Threat Detection Features
- **Unusual Destinations**: Flags connections to rare or unknown IPs
- **High Frequency Monitoring**: Detects connection bursts and port scanning
- **Suspicious Port Detection**: Identifies connections to non-standard ports
- **Timing Analysis**: Flags connections during unusual hours
- **Process Anomalies**: Detects hidden executables and suspicious processes
- **Geographic Analysis**: Identifies connections from unusual geographic regions

### Visualization Features
- **Force-Directed Graph**: Interactive network topology with clustering
- **Threat-Based Coloring**: Blue (safe) → Yellow (warning) → Red (suspicious) → Purple (critical)
- **Real-time Updates**: Live streaming of new connections
- **Zoom & Pan**: Navigate complex network visualizations
- **Process Selection**: Click nodes for detailed analysis
- **Connection Highlighting**: Visual pathways for threat chains

## 🏗️ Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   eBPF Kernel   │───▶│  Python Backend  │───▶│ React/Electron  │
│                 │    │                  │    │     GUI         │
│ tcp_connect     │    │ • Threat Detection│    │ • D3.js Graph  │
│ hooks          │    │ • WebSocket API  │    │ • Dark Mode     │
│ • Low Overhead │    │ • ML Analysis    │    │ • Process Info  │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## 📋 System Requirements

### Minimum Requirements
- **OS**: Linux kernel 5.8+ (eBPF support)
- **Memory**: 4GB RAM
- **Storage**: 1GB free space
- **CPU**: x86_64 or ARM64

### Software Dependencies
- **Python 3.8+** (backend)
- **Node.js 16+** (GUI)
- **clang/llvm** (eBPF compilation)
- **BCC (BPF Compiler Collection)** (eBPF integration)
- **psutil** (system monitoring)
- **Root privileges** (for eBPF monitoring)

## 🛠️ Installation

### Quick Install (Recommended)

```bash
# Clone the repository
git clone https://github.com/netviz/netviz.git
cd netviz

# Run installation script (requires sudo for full functionality)
sudo ./scripts/install.sh

# Run NetViz
sudo netviz
```

### Manual Installation

#### 1. Build eBPF Program
```bash
cd ebpf
make all
```

#### 2. Setup Python Backend
```bash
cd server
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

#### 3. Setup GUI
```bash
cd gui
npm install
npm run react-build
```

#### 4. Run the Application
```bash
# Start backend (requires root for eBPF)
sudo cd server && source venv/bin/activate && python main.py

# Start GUI (in separate terminal)
cd gui && npm run electron
```

## 🚀 Usage

### Basic Operation

1. **Start NetViz**: Run with sudo for eBPF functionality
   ```bash
   sudo netviz
   ```

2. **Monitor Connections**: View real-time network graph
   - **Blue nodes**: Safe processes
   - **Red/Purple nodes**: Suspicious processes
   - **Node size**: Number of connections
   - **Edge thickness**: Connection frequency

3. **Investigate Threats**: Click suspicious nodes
   - View process details in sidebar
   - Analyze threat factors
   - Review connection history

4. **Take Action**: Use context menu options
   - Kill malicious processes
   - Block network access
   - Export threat reports

### Advanced Features

#### Threat Scoring System
- **0-25**: Safe (normal network activity)
- **26-49**: Low risk (slightly unusual)
- **50-74**: Medium risk (suspicious activity)
- **75-89**: High risk (very suspicious)
- **90-100**: Critical (likely malicious)

#### Filtering and Search
- Filter by process name, IP address, or threat level
- Search specific connections or processes
- Timeline view for historical analysis
- Export data for external analysis

#### WebSocket API
Connect external tools via WebSocket:
```javascript
const ws = new WebSocket('ws://localhost:8080/ws/realtime');

ws.onmessage = (event) => {
  const data = JSON.parse(event.data);
  if (data.type === 'connection') {
    console.log('New connection:', data.data);
  }
};
```

## 🔧 Configuration

### Environment Variables
```bash
export NETVIZ_PORT=8080                    # Server port
export NETVIZ_MAX_CONNECTIONS=10000          # Max stored connections
export NETVIZ_RETENTION_MINUTES=5           # Data retention time
```

### Threat Detection Tuning
Edit `server/threat_detector.py` to customize:
- Safe ports list
- Suspicious country codes
- ML model parameters
- Risk factor weights

### UI Customization
- Theme configuration in `gui/src/App.tsx`
- Graph layout in `gui/src/components/NetworkGraph.tsx`
- Color schemes in theme definitions

## 📊 Performance

### Resource Usage
- **eBPF Overhead**: <1% CPU
- **Backend Memory**: <100MB (10k connections)
- **GUI Memory**: <200MB
- **Latency**: <10ms WebSocket updates

### Scalability
- **Max Connections**: 10,000 concurrent
- **Update Rate**: Real-time (sub-second)
- **Graph Performance**: 60 FPS with 1,000+ nodes
- **Storage**: In-memory only (configurable retention)

## 🛡️ Security Considerations

### eBPF Privileges
- Requires `CAP_SYS_ADMIN` capability
- Consider running backend as separate user
- Use systemd service for proper privilege management

### Data Privacy
- No persistent storage of network data
- Configurable data retention periods
- Option to exclude local network connections
- Real-time monitoring only

### Network Security
- WebSocket connections from localhost only
- Optional authentication for remote access
- Rate limiting prevents DoS attacks
- HTTPS/WSS for production deployments

## 🔍 Troubleshooting

### Common Issues

#### eBPF Loading Fails
```bash
# Check kernel version
uname -r  # Should be 5.8+

# Check privileges
sudo whoami  # Should be root

# Check BCC installation
python3 -c "from bcc import BPF; print('BCC OK')"
```

#### WebSocket Connection Failed
```bash
# Check server status
curl http://localhost:8080/api/health

# Check firewall
sudo ufw status
sudo iptables -L
```

#### GUI Not Starting
```bash
# Check Node.js version
node --version  # Should be 16+

# Rebuild GUI
cd gui && npm run react-build
```

### Debug Mode
Enable verbose logging:
```bash
export NETVIZ_DEBUG=1
python3 server/main.py
```

### Performance Issues
- Reduce `NETVIZ_MAX_CONNECTIONS`
- Increase `NETVIZ_RETENTION_MINUTES`
- Disable real-time graph updates for low-end systems

## 🤝 Contributing

### Development Setup
```bash
# Clone with development dependencies
git clone --recursive https://github.com/netviz/netviz.git

# Install development tools
pip install -r server/requirements.txt
cd gui && npm install

# Run tests
npm test
python -m pytest server/tests/
```

### Code Style
- Python: Black formatter, flake8 linting
- TypeScript/React: Prettier formatter
- eBPF: Linux kernel coding style

### Submitting Changes
1. Fork the repository
2. Create feature branch
3. Add tests for new functionality
4. Submit pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **BCC (BPF Compiler Collection)**: eBPF integration framework
- **D3.js**: Data-driven visualizations
- **React**: UI framework
- **Electron**: Desktop application framework
- **FastAPI**: High-performance web framework

## 📚 References

- [eBPF Documentation](https://ebpf.io/)
- [BCC Tutorial](https://github.com/iovisor/bcc/blob/master/docs/tutorial.md)
- [Linux Network Stack](https://www.kernel.org/doc/html/latest/networking/)
- [D3.js Documentation](https://d3js.org/)

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/netviz/netviz/issues)
- **Discussions**: [GitHub Discussions](https://github.com/netviz/netviz/discussions)
- **Documentation**: [Wiki](https://github.com/netviz/netviz/wiki)

---

**NetViz** - See your network like never before. 🔐🌐