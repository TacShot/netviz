"""
WebSocket Handler Module
Manages real-time data streaming to GUI clients
"""

import asyncio
import json
import logging
import time
import uuid
from typing import Dict, List, Any, Set
from datetime import datetime

import psutil
import websockets
from fastapi import WebSocket, WebSocketDisconnect

logger = logging.getLogger(__name__)

class WebSocketHandler:
    """Handles WebSocket connections for real-time network monitoring"""

    def __init__(self, connection_handler):
        self.connection_handler = connection_handler
        self.clients: Dict[str, WebSocket] = {}
        self.client_metadata: Dict[str, Dict[str, Any]] = {}
        self.running = True
        self.message_queue = asyncio.Queue()
        self.client_lock = asyncio.Lock()

        # Message rate limiting
        self.rate_limit = 100  # messages per second per client
        self.client_message_counts: Dict[str, List[float]] = {}

        # Statistics
        self.total_connections = 0
        self.messages_sent = 0
        self.start_time = time.time()

        # Background tasks
        self.background_tasks = []

    async def handle_client(self, websocket: WebSocket):
        """Handle a new WebSocket client connection"""
        client_id = str(uuid.uuid4())
        current_time = time.time()

        try:
            # Accept WebSocket connection
            await websocket.accept()

            # Add client to managed connections
            async with self.client_lock:
                self.clients[client_id] = websocket
                self.client_metadata[client_id] = {
                    'connected_at': current_time,
                    'last_ping': current_time,
                    'subscriptions': ['all'],
                    'last_message_time': current_time
                }
                self.client_message_counts[client_id] = []

            self.total_connections += 1
            logger.info(f"WebSocket client connected: {client_id}")

            # Send initial data to client
            await self.send_initial_data(client_id, websocket)

            # Send periodic updates
            update_task = asyncio.create_task(self.send_periodic_updates(client_id, websocket))
            self.background_tasks.append(update_task)

            # Handle client messages
            await self.handle_client_messages(client_id, websocket)

        except WebSocketDisconnect:
            logger.info(f"WebSocket client disconnected: {client_id}")
        except Exception as e:
            logger.error(f"Error handling WebSocket client {client_id}: {e}")
        finally:
            # Cleanup
            await self.cleanup_client(client_id)

    async def send_initial_data(self, client_id: str, websocket: WebSocket):
        """Send initial data to newly connected client"""
        try:
            # Send recent connections
            recent_connections = await self.connection_handler.get_recent_connections(limit=500)
            await self.send_message(client_id, websocket, {
                'type': 'initial_data',
                'data': {
                    'connections': recent_connections,
                    'server_info': {
                        'uptime': time.time() - self.start_time,
                        'total_connections': self.connection_handler.total_connections
                    }
                }
            })

            # Send current statistics
            stats = await self.connection_handler.get_statistics()
            await self.send_message(client_id, websocket, {
                'type': 'statistics',
                'data': stats
            })

        except Exception as e:
            logger.error(f"Error sending initial data to client {client_id}: {e}")

    async def send_periodic_updates(self, client_id: str, websocket: WebSocket):
        """Send periodic updates to client"""
        while client_id in self.clients and self.running:
            try:
                # Send statistics every 30 seconds
                await asyncio.sleep(30)

                if client_id not in self.clients:
                    break

                stats = await self.connection_handler.get_statistics()
                await self.send_message(client_id, websocket, {
                    'type': 'statistics',
                    'data': stats
                })

                # Send heartbeat/ping
                # await self.send_ping(client_id, websocket)

            except Exception as e:
                logger.error(f"Error sending periodic updates to client {client_id}: {e}")
                break

    async def handle_client_messages(self, client_id: str, websocket: WebSocket):
        """Handle incoming messages from client"""
        try:
            while client_id in self.clients and self.running:
                # Receive message with timeout
                try:
                    message = await asyncio.wait_for(websocket.receive_text(), timeout=1.0)
                except asyncio.TimeoutError:
                    continue

                # Parse and handle message
                try:
                    data = json.loads(message)
                    await self.process_client_message(client_id, websocket, data)
                except json.JSONDecodeError:
                    logger.warning(f"Invalid JSON from client {client_id}: {message}")
                    await self.send_error(client_id, websocket, "Invalid JSON format")

        except WebSocketDisconnect:
            pass  # Handled by outer try/except
        except Exception as e:
            logger.error(f"Error handling messages from client {client_id}: {e}")

    async def process_client_message(self, client_id: str, websocket: WebSocket, data: Dict[str, Any]):
        """Process incoming message from client"""
        message_type = data.get('type')

        if message_type == 'ping':
            await self.handle_ping(client_id, websocket, data)
        elif message_type == 'subscribe':
            await self.handle_subscribe(client_id, websocket, data)
        elif message_type == 'get_process_details':
            await self.handle_get_process_details(client_id, websocket, data)
        elif message_type == 'get_connections':
            await self.handle_get_connections(client_id, websocket, data)
        elif message_type == 'kill_process':
            await self.handle_kill_process(client_id, websocket, data)
        else:
            logger.warning(f"Unknown message type from client {client_id}: {message_type}")
            await self.send_error(client_id, websocket, f"Unknown message type: {message_type}")

    async def handle_ping(self, client_id: str, websocket: WebSocket, data: Dict[str, Any]):
        """Handle ping/pong for connection health"""
        async with self.client_lock:
            if client_id in self.client_metadata:
                self.client_metadata[client_id]['last_ping'] = time.time()

        await self.send_message(client_id, websocket, {
            'type': 'pong',
            'data': {'timestamp': time.time()}
        })

    async def handle_subscribe(self, client_id: str, websocket: WebSocket, data: Dict[str, Any]):
        """Handle subscription updates"""
        subscriptions = data.get('subscriptions', [])

        async with self.client_lock:
            if client_id in self.client_metadata:
                self.client_metadata[client_id]['subscriptions'] = subscriptions

        await self.send_message(client_id, websocket, {
            'type': 'subscription_updated',
            'data': {'subscriptions': subscriptions}
        })

    async def handle_get_process_details(self, client_id: str, websocket: WebSocket, data: Dict[str, Any]):
        """Handle request for process details"""
        try:
            pid = data.get('pid')
            if pid is None:
                await self.send_error(client_id, websocket, "Missing PID")
                return

            process_details = await self.connection_handler.get_process_details(int(pid))
            if process_details:
                await self.send_message(client_id, websocket, {
                    'type': 'process_details',
                    'data': process_details
                })
            else:
                await self.send_error(client_id, websocket, "Process not found")

        except Exception as e:
            logger.error(f"Error getting process details: {e}")
            await self.send_error(client_id, websocket, "Error getting process details")

    async def handle_get_connections(self, client_id: str, websocket: WebSocket, data: Dict[str, Any]):
        """Handle request for connections with optional filtering"""
        try:
            limit = data.get('limit', 1000)
            filters = data.get('filters', {})

            connections = await self.connection_handler.get_recent_connections(limit)

            # Apply filters if provided
            if filters:
                connections = self.apply_filters(connections, filters)

            await self.send_message(client_id, websocket, {
                'type': 'connections',
                'data': {
                    'connections': connections,
                    'total': len(connections)
                }
            })

        except Exception as e:
            logger.error(f"Error getting connections: {e}")
            await self.send_error(client_id, websocket, "Error getting connections")

    async def handle_kill_process(self, client_id: str, websocket: WebSocket, data: Dict[str, Any]):
        """Handle request to kill a process"""
        pid = data.get('data', {}).get('pid')
        if not pid:
            await self.send_error(client_id, websocket, "PID not provided for kill_process")
            return

        try:
            pid = int(pid)
            proc = psutil.Process(pid)
            
            # Terminate child processes first to avoid orphans
            children = proc.children(recursive=True)
            for child in children:
                try:
                    child.terminate()
                except psutil.NoSuchProcess:
                    continue # Child might have already been terminated

            # Wait for children to terminate
            gone, alive = psutil.wait_procs(children, timeout=3)
            for p in alive:
                try:
                    p.kill()
                except psutil.NoSuchProcess:
                    continue

            # Terminate the parent process
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except psutil.TimeoutExpired:
                proc.kill()


            logger.info(f"Process {pid} killed by client {client_id}")
            await self.send_message(client_id, websocket, {
                'type': 'process_killed',
                'data': {'pid': pid, 'status': 'success'}
            })

        except psutil.NoSuchProcess:
            logger.warning(f"Attempted to kill non-existent process {pid}")
            await self.send_error(client_id, websocket, f"Process with PID {pid} not found.")
        
        except psutil.AccessDenied:
            logger.error(f"Access denied when trying to kill process {pid}")
            await self.send_error(client_id, websocket, f"Access denied. Insufficient permissions to kill process {pid}.")

        except Exception as e:
            logger.error(f"Error killing process {pid}: {e}")
            await self.send_error(client_id, websocket, f"An unexpected error occurred while trying to kill process {pid}.")



    def apply_filters(self, connections: List[Dict[str, Any]], filters: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Apply filters to connection list"""
        filtered = connections

        if filters.get('suspicious_only'):
            filtered = [c for c in filtered if c.get('is_suspicious', False)]

        if filters.get('process_name'):
            process_name = filters['process_name'].lower()
            filtered = [c for c in filtered if process_name in c.get('process_name', '').lower()]

        if filters.get('min_threat_score'):
            min_score = filters['min_threat_score']
            filtered = [c for c in filtered if c.get('threat_score', 0) >= min_score]

        if filters.get('destination_ip'):
            dst_ip = filters['destination_ip']
            filtered = [c for c in filtered if dst_ip in c.get('dst_ip', '')]

        return filtered

    async def broadcast_connection(self, connection_event: Dict[str, Any]):
        """Broadcast new connection to all interested clients"""
        if not self.clients:
            return

        message = {
            'type': 'connection',
            'data': connection_event
        }

        # Send to all clients (could be optimized based on subscriptions)
        for client_id, websocket in list(self.clients.items()):
            await self.send_message(client_id, websocket, message)

    async def send_message(self, client_id: str, websocket: WebSocket, message: Dict[str, Any]):
        """Send message to specific client with rate limiting"""
        try:
            # Check rate limit
            if not self.check_rate_limit(client_id):
                logger.warning(f"Rate limiting client {client_id}")
                return

            # Send message
            message_json = json.dumps(message)
            await websocket.send_text(message_json)

            self.messages_sent += 1

            # Update last message time
            async with self.client_lock:
                if client_id in self.client_metadata:
                    self.client_metadata[client_id]['last_message_time'] = time.time()

        except Exception as e:
            logger.error(f"Error sending message to client {client_id}: {e}")
            # Remove client if connection is broken
            await self.cleanup_client(client_id)

    async def send_error(self, client_id: str, websocket: WebSocket, error_message: str):
        """Send error message to client"""
        await self.send_message(client_id, websocket, {
            'type': 'error',
            'data': {'error': error_message}
        })

    async def send_ping(self, client_id: str, websocket: WebSocket):
        """Send ping to check connection health"""
        await self.send_message(client_id, websocket, {
            'type': 'ping',
            'data': {'timestamp': time.time()}
        })

    def check_rate_limit(self, client_id: str) -> bool:
        """Check if client is within rate limits"""
        current_time = time.time()

        if client_id not in self.client_message_counts:
            self.client_message_counts[client_id] = []

        # Remove old messages (older than 1 second)
        self.client_message_counts[client_id] = [
            timestamp for timestamp in self.client_message_counts[client_id]
            if current_time - timestamp < 1.0
        ]

        # Check if under limit
        if len(self.client_message_counts[client_id]) < self.rate_limit:
            self.client_message_counts[client_id].append(current_time)
            return True

        return False

    async def cleanup_client(self, client_id: str):
        """Clean up disconnected client"""
        try:
            async with self.client_lock:
                if client_id in self.clients:
                    del self.clients[client_id]
                if client_id in self.client_metadata:
                    del self.client_metadata[client_id]
                if client_id in self.client_message_counts:
                    del self.client_message_counts[client_id]

            logger.info(f"Cleaned up client {client_id}")

        except Exception as e:
            logger.error(f"Error cleaning up client {client_id}: {e}")

    async def cleanup(self):
        """Clean up all WebSocket resources"""
        logger.info("Cleaning up WebSocket handler...")
        self.running = False

        # Cancel background tasks
        for task in self.background_tasks:
            task.cancel()

        # Close all client connections
        for client_id, websocket in list(self.clients.items()):
            try:
                await websocket.close()
            except:
                pass

        # Clear client data
        async with self.client_lock:
            self.clients.clear()
            self.client_metadata.clear()
            self.client_message_counts.clear()

        logger.info("WebSocket handler cleanup complete")

    def get_statistics(self) -> Dict[str, Any]:
        """Get WebSocket handler statistics"""
        return {
            'active_connections': len(self.clients),
            'total_connections': self.total_connections,
            'messages_sent': self.messages_sent,
            'uptime_seconds': time.time() - self.start_time,
            'messages_per_second': self.messages_sent / max(1, time.time() - self.start_time)
        }