"""
Connection Handler Module
Processes and manages network connection events from eBPF
"""

import asyncio
import logging
import socket
import struct
import time
from collections import deque, defaultdict
from typing import Dict, List, Optional, Any, Set
from datetime import datetime, timedelta

import psutil

logger = logging.getLogger(__name__)

class ConnectionHandler:
    """Handles processing and storage of network connection events"""

    def __init__(self, max_connections: int = 10000, retention_minutes: int = 5, threat_detector=None):
        self.max_connections = max_connections
        self.retention_minutes = retention_minutes
        self.threat_detector = threat_detector
        self.websocket_handler: Optional['WebSocketHandler'] = None

        # In-memory storage for connections (sliding window)
        self.connections: Dict[str, Dict[str, Any]] = {}
        self.connection_queue = deque(maxlen=max_connections)

        # Process and IP statistics
        self.process_stats: Dict[int, Dict[str, Any]] = defaultdict(dict)
        self.ip_frequency: Dict[str, int] = defaultdict(int)
        self.connection_rates: Dict[int, List[float]] = defaultdict(list)

        # Thread safety
        self.lock = asyncio.Lock()

        # Statistics
        self.total_connections = 0
        self.start_time = time.time()

        # Known safe ports
        self.safe_ports = {80, 443, 22, 53, 25, 587, 993, 995, 21, 110, 143, 995, 8080, 8443}

    async def process_connection_event(self, event: Dict[str, Any]):
        """Process a single connection event from eBPF"""
        try:
            async with self.lock:
                # Generate unique connection ID
                conn_id = f"{event['timestamp']}_{event['pid']}_{event['saddr']}_{event['sport']}_{event['daddr']}_{event['dport']}"

                # Enrich event with additional information
                enriched_event = await self.enrich_connection_event(event)

                # Store connection
                self.connections[conn_id] = enriched_event
                self.connection_queue.append(conn_id)

                # Update statistics
                await self.update_statistics(enriched_event)

                # Perform threat analysis
                if self.threat_detector:
                    threat_score = self.threat_detector.analyze_connection(enriched_event)
                    enriched_event['threat_score'] = threat_score
                    enriched_event['is_suspicious'] = threat_score >= 50
                else:
                    enriched_event['threat_score'] = 0
                    enriched_event['is_suspicious'] = False

                self.total_connections += 1

                # Log new suspicious connection
                if enriched_event['is_suspicious']:
                    logger.info(f"Suspicious connection detected: PID={event['pid']}, Dst={self.format_ip(event['daddr'])}:{event['dport']}")

                # Broadcast the new connection event to all clients
                if self.websocket_handler:
                    logger.info(f"Broadcasting new connection: {enriched_event}")
                    await self.websocket_handler.broadcast_connection(enriched_event)

        except Exception as e:
            logger.error(f"Error processing connection event: {e}")

    async def enrich_connection_event(self, event: Dict[str, Any]) -> Dict[str, Any]:
        """Enrich connection event with additional process information"""
        try:
            pid = event['pid']
            enriched = event.copy()

            # Convert IP addresses to string format
            enriched['src_ip'] = self.format_ip(event['saddr'])
            enriched['dst_ip'] = self.format_ip(event['daddr'])
            enriched['protocol_str'] = 'TCP' if event['protocol'] == 6 else f"Protocol-{event['protocol']}"

            # Get detailed process information
            try:
                process = psutil.Process(pid)
                enriched['process_name'] = process.name()
                enriched['cmdline_full'] = ' '.join(process.cmdline())
                enriched['exe_path'] = process.exe()
                enriched['parent_pid'] = process.ppid()
                enriched['username'] = process.username()
                enriched['create_time'] = process.create_time()
                enriched['status'] = process.status()
            except psutil.NoSuchProcess:
                enriched['process_name'] = f"[terminated_pid:{pid}]"
                enriched['cmdline_full'] = event.get('cmdline', '')
                enriched['exe_path'] = 'Unknown'
                enriched['parent_pid'] = 0
                enriched['username'] = 'Unknown'
                enriched['create_time'] = 0
                enriched['status'] = 'terminated'
            except (psutil.AccessDenied, psutil.ZombieProcess):
                enriched['process_name'] = event.get('comm', f'[pid:{pid}]')
                enriched['cmdline_full'] = event.get('cmdline', '')
                enriched['exe_path'] = 'Unknown'
                enriched['parent_pid'] = 0
                enriched['username'] = 'Restricted'
                enriched['create_time'] = 0
                enriched['status'] = 'restricted'

            # Add geographic info if available (placeholder for now)
            enriched['country_code'] = 'Unknown'
            enriched['is_private'] = self.is_private_ip(event['daddr'])
            enriched['is_safe_port'] = event['dport'] in self.safe_ports

            return enriched

        except Exception as e:
            logger.error(f"Error enriching connection event: {e}")
            return event

    async def update_statistics(self, event: Dict[str, Any]):
        """Update internal statistics based on connection event"""
        current_time = time.time()

        # Update process statistics
        pid = event['pid']
        if pid not in self.process_stats:
            self.process_stats[pid] = {
                'name': event.get('comm', 'Unknown'),
                'connection_count': 0,
                'first_seen': current_time,
                'last_seen': current_time,
                'unique_destinations': set(),
                'suspicious_count': 0
            }

        stats = self.process_stats[pid]
        stats['connection_count'] += 1
        stats['last_seen'] = current_time
        stats['unique_destinations'].add(event['daddr'])
        if event.get('is_suspicious', False):
            stats['suspicious_count'] += 1

        # Update IP frequency
        self.ip_frequency[event['daddr']] += 1

        # Update connection rates (for rate-based threat detection)
        self.connection_rates[pid].append(current_time)
        # Keep only last 60 seconds for rate calculation
        self.connection_rates[pid] = [
            t for t in self.connection_rates[pid]
            if current_time - t <= 60
        ]

        # Cleanup old connections periodically
        if self.total_connections % 100 == 0:
            await self.cleanup_old_connections()

    async def cleanup_old_connections(self):
        """Remove connections older than retention period"""
        current_time = time.time()
        cutoff_time = current_time - (self.retention_minutes * 60)

        # Find old connections to remove
        old_connections = []
        for conn_id, event in self.connections.items():
            event_time = event['timestamp'] / 1_000_000_000  # Convert nanoseconds to seconds
            if event_time < cutoff_time:
                old_connections.append(conn_id)

        # Remove old connections
        for conn_id in old_connections:
            del self.connections[conn_id]

        logger.debug(f"Cleaned up {len(old_connections)} old connections")

    async def get_recent_connections(self, limit: int = 1000) -> List[Dict[str, Any]]:
        """Get most recent connections"""
        async with self.lock:
            # Get recent connection IDs
            recent_ids = list(self.connection_queue)[-limit:]

            # Return connection events
            connections = []
            for conn_id in recent_ids:
                if conn_id in self.connections:
                    connections.append(self.connections[conn_id])

            # Sort by timestamp (newest first)
            connections.sort(key=lambda x: x['timestamp'], reverse=True)
            return connections

    async def get_process_details(self, pid: int) -> Optional[Dict[str, Any]]:
        """Get detailed information about a specific process"""
        async with self.lock:
            if pid not in self.process_stats:
                return None

            stats = self.process_stats[pid].copy()

            # Convert set to list for JSON serialization
            stats['unique_destinations'] = list(stats['unique_destinations'])

            # Get all connections for this process
            process_connections = [
                conn for conn in self.connections.values()
                if conn['pid'] == pid
            ]

            # Sort by timestamp
            process_connections.sort(key=lambda x: x['timestamp'], reverse=True)

            # Calculate rate (connections per second in last minute)
            current_time = time.time()
            recent_connections = [
                t for t in self.connection_rates.get(pid, [])
                if current_time - t <= 60
            ]
            stats['connection_rate_per_minute'] = len(recent_connections)

            # Add threat information
            if self.threat_detector:
                stats['threat_analysis'] = self.threat_detector.get_process_threat_analysis(pid)

            return {
                'process_info': stats,
                'recent_connections': process_connections[:50],  # Limit to 50 most recent
                'total_connections': len(process_connections)
            }

    async def get_statistics(self) -> Dict[str, Any]:
        """Get overall connection statistics"""
        async with self.lock:
            current_time = time.time()
            uptime = current_time - self.start_time

            # Count active processes
            active_processes = len([p for p in self.process_stats.values()
                                  if current_time - p['last_seen'] < 300])  # Active in last 5 minutes

            # Count suspicious connections
            suspicious_count = sum(1 for conn in self.connections.values()
                                 if conn.get('is_suspicious', False))

            # Most active processes
            top_processes = sorted(
                self.process_stats.items(),
                key=lambda x: x[1]['connection_count'],
                reverse=True
            )[:10]

            # Most frequent destinations
            top_destinations = sorted(
                self.ip_frequency.items(),
                key=lambda x: x[1],
                reverse=True
            )[:10]

            return {
                'total_connections': self.total_connections,
                'active_connections': len(self.connections),
                'active_processes': active_processes,
                'suspicious_connections': suspicious_count,
                'suspicious_percentage': (suspicious_count / len(self.connections)) * 100 if self.connections else 0,
                'uptime_seconds': uptime,
                'average_connections_per_second': self.total_connections / uptime if uptime > 0 else 0,
                'top_processes': [
                {
                    'pid': pid,
                    **{**stats, 'unique_destinations': list(stats.get('unique_destinations', []))}
                } for pid, stats in top_processes
            ],
                'top_destinations': [{'ip': ip, 'count': count} for ip, count in top_destinations]
            }

    def format_ip(self, ip_int: int) -> str:
        """Convert integer IP address to string format"""
        try:
            return socket.inet_ntoa(struct.pack('!I', ip_int))
        except:
            return f"Invalid-IP-{ip_int}"

    def is_private_ip(self, ip_int: int) -> bool:
        """Check if IP address is in private range"""
        try:
            ip_str = self.format_ip(ip_int)

            # Check private IP ranges
            private_ranges = [
                ('10.0.0.0', '10.255.255.255'),
                ('172.16.0.0', '172.31.255.255'),
                ('192.168.0.0', '192.168.255.255'),
                ('127.0.0.0', '127.255.255.255')
            ]

            for start, end in private_ranges:
                start_int = struct.unpack('!I', socket.inet_aton(start))[0]
                end_int = struct.unpack('!I', socket.inet_aton(end))[0]
                if start_int <= ip_int <= end_int:
                    return True

            return False
        except:
            return False


