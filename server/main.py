#!/usr/bin/env python3
"""
eBPF Network Threat Visualizer - Main Server
FastAPI server with WebSocket support for real-time network monitoring
"""

import asyncio
import os
import sys
import logging
import signal
from pathlib import Path
from typing import Dict, List, Optional

from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import uvicorn

# Add server directory to Python path for imports
sys.path.insert(0, str(Path(__file__).parent))

from ebpf_loader import EBPFLoader
from connection_handler import ConnectionHandler
from threat_detector import ThreatDetector
from websocket_handler import WebSocketHandler

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class NetworkMonitorServer:
    """Main server class for network threat visualization"""

    def __init__(self):
        self.app = FastAPI(
            title="eBPF Network Threat Visualizer",
            description="Real-time network connection monitoring with threat detection",
            version="1.0.0"
        )

        # Configuration
        self.port = int(os.environ.get('NETVIZ_PORT', 8080))
        self.max_connections = int(os.environ.get('NETVIZ_MAX_CONNECTIONS', 10000))
        self.retention_minutes = int(os.environ.get('NETVIZ_RETENTION_MINUTES', 5))

        # Initialize components
        self.ebpf_loader: Optional[EBPFLoader] = None
        self.connection_handler: Optional[ConnectionHandler] = None
        self.threat_detector: Optional[ThreatDetector] = None
        self.websocket_handler: Optional[WebSocketHandler] = None

        # Setup FastAPI
        self.setup_middleware()
        self.setup_routes()

        # Shutdown flag
        self.shutdown_event = asyncio.Event()

    def setup_middleware(self):
        """Setup CORS and other middleware"""
        self.app.add_middleware(
            CORSMiddleware,
            allow_origins=["http://localhost:3000"],  # Electron dev server
            allow_credentials=True,
            allow_methods=["*"],
            allow_headers=["*"],
        )

    def setup_routes(self):
        """Setup API routes"""

        @self.app.get("/")
        async def root():
            return {"message": "eBPF Network Threat Visualizer API"}

        @self.app.get("/api/health")
        async def health_check():
            """Health check endpoint"""
            return {
                "status": "healthy",
                "ebpf_loaded": self.ebpf_loader.is_loaded() if self.ebpf_loader else False,
                "websocket_clients": len(self.websocket_handler.clients) if self.websocket_handler else 0
            }

        @self.app.get("/api/connections")
        async def get_connections(limit: int = 1000):
            """Get recent network connections"""
            if not self.connection_handler:
                raise HTTPException(status_code=503, detail="Connection handler not initialized")

            connections = await self.connection_handler.get_recent_connections(limit)
            return {"connections": connections, "total": len(connections)}

        @self.app.get("/api/processes/{pid}")
        async def get_process_details(pid: int):
            """Get detailed information about a specific process"""
            if not self.connection_handler:
                raise HTTPException(status_code=503, detail="Connection handler not initialized")

            process_info = await self.connection_handler.get_process_details(pid)
            if not process_info:
                raise HTTPException(status_code=404, detail="Process not found")

            return process_info

        @self.app.get("/api/stats")
        async def get_statistics():
            """Get connection and threat statistics"""
            if not self.connection_handler or not self.threat_detector:
                raise HTTPException(status_code=503, detail="Services not initialized")

            conn_stats = await self.connection_handler.get_statistics()
            threat_stats = self.threat_detector.get_statistics()

            return {
                "connections": conn_stats,
                "threats": threat_stats,
                "uptime": asyncio.get_event_loop().time() - self.start_time if hasattr(self, 'start_time') else 0
            }

        @self.app.websocket("/ws/realtime")
        async def websocket_endpoint(websocket: WebSocket):
            """Real-time WebSocket connection for live network monitoring"""
            if not self.websocket_handler:
                await websocket.close(code=503, reason="WebSocket handler not initialized")
                return

            await self.websocket_handler.handle_client(websocket)

    async def initialize(self):
        """Initialize all server components"""
        try:
            logger.info("Initializing eBPF Network Threat Visualizer...")

            # Initialize threat detector first
            self.threat_detector = ThreatDetector()
            logger.info("Threat detector initialized")

            # Initialize connection handler
            self.connection_handler = ConnectionHandler(
                max_connections=self.max_connections,
                retention_minutes=self.retention_minutes,
                threat_detector=self.threat_detector
            )
            logger.info("Connection handler initialized")

            # Initialize WebSocket handler
            self.websocket_handler = WebSocketHandler(
                connection_handler=self.connection_handler
            )
            logger.info("WebSocket handler initialized")

            # Initialize and load eBPF program
            self.ebpf_loader = EBPFLoader(
                connection_handler=self.connection_handler
            )

            success = await self.ebpf_loader.load_and_attach()
            if not success:
                logger.error("Failed to load eBPF program. Running without network monitoring.")
                # Continue without eBPF for GUI testing

            # Record start time
            self.start_time = asyncio.get_event_loop().time()

            logger.info("Server initialization complete")

        except Exception as e:
            logger.error(f"Failed to initialize server: {e}")
            raise

    async def shutdown(self):
        """Graceful shutdown of server components"""
        logger.info("Shutting down server...")

        self.shutdown_event.set()

        # Shutdown eBPF program
        if self.ebpf_loader:
            await self.ebpf_loader.cleanup()

        # Shutdown WebSocket handler
        if self.websocket_handler:
            await self.websocket_handler.cleanup()

        logger.info("Server shutdown complete")

    async def run(self):
        """Run the server"""
        await self.initialize()

        # Setup signal handlers
        def signal_handler(signum, frame):
            logger.info(f"Received signal {signum}, initiating shutdown...")
            asyncio.create_task(self.shutdown())

        signal.signal(signal.SIGINT, signal_handler)
        signal.signal(signal.SIGTERM, signal_handler)

        # Run uvicorn server
        config = uvicorn.Config(
            app=self.app,
            host="127.0.0.1",
            port=self.port,
            log_level="info"
        )

        server = uvicorn.Server(config)

        try:
            logger.info(f"Starting server on http://127.0.0.1:{self.port}")
            await server.serve()
        except Exception as e:
            logger.error(f"Server error: {e}")
        finally:
            await self.shutdown()

async def main():
    """Main entry point"""
    server = NetworkMonitorServer()
    await server.run()

if __name__ == "__main__":
    asyncio.run(main())