# NetViz - eBPF Network Threat Visualizer Instructions

This document provides instructions on how to set up, build, and run the NetViz application.

## Project Overview

NetViz is an eBPF-based network threat visualizer that monitors network connections and identifies potential threats in real-time. It consists of three main components:
- **eBPF Program:** For low-level network monitoring.
- **Python Backend:** Processes eBPF data, performs threat detection, and serves data via WebSockets.
- **React/Electron GUI:** A graphical user interface for visualizing network activity and detected threats.

## 1. Development Setup and Run

To set up your development environment and run NetViz in development mode, use the provided `run_dev.sh` script. This script automates dependency installation and starts both the backend and frontend.

1.  **Make the script executable (if not already):**
    ```bash
    chmod +x run_dev.sh
    ```
2.  **Run the application in development mode:**
    ```bash
    ./run_dev.sh
    ```
    **Note on eBPF and Root Privileges:**
    The eBPF network monitoring component requires root privileges.
    -   If you run `./run_dev.sh` without `sudo`, the script will attempt to start the Python backend with `sudo` (you will be prompted for your password). If successful, eBPF monitoring will be enabled.
    -   Alternatively, you can run the entire script with `sudo` (e.g., `sudo ./run_dev.sh`) to avoid a separate password prompt for the backend.

    The script will:
    -   Create and activate a Python virtual environment in `server/venv`.
    -   Install Python dependencies from `server/requirements.txt`.
    -   Install Node.js dependencies in `gui/node_modules`.
    -   Start the Python backend server (with root privileges if eBPF is enabled).
    -   Start the Electron GUI, which will connect to the backend.

    Press `Ctrl+C` in the terminal to stop both the backend and frontend processes.

## 2. Building a Production Distribution

To create a self-contained, distributable package of the NetViz application, use the `scripts/build.sh` script. This script compiles all components and packages them into a `dist` directory.

1.  **Make the build script executable (if not already):**
    ```bash
    chmod +x scripts/build.sh
    ```
2.  **Run the build process:**
    ```bash
    ./scripts/build.sh
    ```
    This will:
    -   Check for necessary build tools (clang, python3, node, npm).
    -   Build the Python backend and install its dependencies.
    -   Build the React application for the GUI.
    -   Create a `dist/netviz` directory containing all application components.
    -   Generate `run.sh` and `install.sh` scripts within the `dist/netviz` directory.
    -   Create a compressed tarball (`.tar.gz`) of the `dist/netviz` directory.

    The final distributable package will be located in the `dist` folder.

## 3. Running from a Production Distribution

If you have a built distribution (e.g., from the `dist` folder or an extracted tarball), you can run the application using its `run.sh` script.

1.  **Navigate to the distributed application directory:**
    ```bash
    cd dist/netviz/ # Or wherever you extracted the tarball
    ```
2.  **Make the run script executable (if not already):**
    ```bash
    chmod +x run.sh
    ```
3.  **Run the application:**
    ```bash
    ./run.sh
    ```
    **Note:** For full eBPF functionality, you might need to run this with `sudo`. The script will provide a warning if not run as root.

## 4. System-Wide Installation

For a system-wide installation, including desktop entries and systemd services, use the `scripts/install.sh` script. This script is designed for a more permanent setup on various Linux distributions.

1.  **Make the install script executable (if not already):**
    ```bash
    chmod +x scripts/install.sh
    ```
2.  **Run the installation script (usually with sudo):**
    ```bash
    sudo ./scripts/install.sh
    ```
    Follow the on-screen prompts. This script will:
    -   Detect your Linux distribution.
    -   Install system-level dependencies (e.g., Python, Node.js, clang, eBPF tools).
    -   Copy application files to `/opt/netviz`.
    -   Set up Python and Node.js environments within the installation directory.
    -   Create a desktop entry for the GUI.
    -   Optionally create a systemd service for the backend.
    -   Create a command-line shortcut (`netviz`).

    After installation, you can typically launch NetViz from your applications menu or via the `netviz` command in the terminal.
