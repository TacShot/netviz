"""
Threat Detection Module
Analyzes network connections for suspicious patterns using rule-based and ML approaches
"""

import logging
import time
from collections import defaultdict, deque
from datetime import datetime
from typing import Dict, List, Any, Set, Optional
import numpy as np

logger = logging.getLogger(__name__)

class ThreatDetector:
    """Detects suspicious network connections using rule-based and ML analysis"""

    def __init__(self):
        # Known safe ports and IPs
        self.safe_ports = {80, 443, 22, 53, 25, 587, 993, 995, 21, 110, 143, 8080, 8443, 9418}
        self.common_dns_servers = {
            '8.8.8.8', '8.8.4.4',    # Google
            '1.1.1.1', '1.0.0.1',    # Cloudflare
            '208.67.222.222',        # OpenDNS
            '9.9.9.9', '149.112.112.112'  # Quad9
        }

        # Tracking data structures
        self.ip_frequency = defaultdict(int)
        self.process_connection_history = defaultdict(lambda: deque(maxlen=100))
        self.first_time_ips = set()
        self.process_first_connection = set()

        # Suspicious indicators
        self.suspicious_countries = {'CN', 'RU', 'KP', 'IR'}  # Country codes
        self.suspicious_ports = {1337, 31337, 4444, 5555, 6667, 12345, 54321}

        # Statistics
        self.total_analyzed = 0
        self.suspicious_detected = 0
        self.start_time = time.time()

        # ML model placeholder (simplified for initial implementation)
        self.connection_features = []
        self.anomaly_threshold = 0.7

    def analyze_connection(self, event: Dict[str, Any]) -> int:
        """
        Analyze a connection event and return threat score (0-100)

        Scoring system:
        0-25: Safe (normal traffic)
        26-49: Low risk (slightly unusual)
        50-74: Medium risk (suspicious)
        75-89: High risk (very suspicious)
        90-100: Critical (likely malicious)
        """
        try:
            self.total_analyzed += 1
            threat_score = 0

            # Update tracking data
            dst_ip = event.get('dst_ip', '')
            pid = event.get('pid', 0)
            dst_port = event.get('dport', 0)
            current_time = time.time()

            # Track IP frequency
            self.ip_frequency[dst_ip] += 1

            # Track process connection history
            self.process_connection_history[pid].append({
                'timestamp': current_time,
                'dst_ip': dst_ip,
                'dst_port': dst_port
            })

            # Apply threat detection rules
            threat_score += self._check_destination_rarity(event)
            threat_score += self._check_connection_frequency(event)
            threat_score += self._check_suspicious_ports(event)
            threat_score += self._check_unusual_timing(event)
            threat_score += self._check_first_time_process(event)
            threat_score += self._check_geographic_anomalies(event)
            threat_score += self._check_process_anomalies(event)
            threat_score += self._check_connection_patterns(event)

            # Apply ML-based anomaly detection
            ml_score = self._ml_anomaly_detection(event)
            threat_score = max(threat_score, ml_score * 50)  # Weight ML score

            # Cap at 100
            threat_score = min(100, max(0, threat_score))

            # Track suspicious connections
            if threat_score >= 50:
                self.suspicious_detected += 1
                logger.info(f"Suspicious connection detected (score: {threat_score}): "
                           f"PID={pid}, Dest={dst_ip}:{dst_port}, Process={event.get('process_name', 'Unknown')}")

            return int(threat_score)

        except Exception as e:
            logger.error(f"Error analyzing connection: {e}")
            return 25  # Default to low risk on error

    def _check_destination_rarity(self, event: Dict[str, Any]) -> int:
        """Check if destination IP is rare or unknown"""
        score = 0
        dst_ip = event.get('dst_ip', '')

        if not dst_ip:
            return 0

        # Very common destinations get 0 points
        if dst_ip in self.common_dns_servers:
            return 0

        # Calculate IP rarity score
        total_connections = self.total_analyzed
        ip_count = self.ip_frequency[dst_ip]

        if total_connections < 10:  # Not enough data
            return 0

        ip_frequency = ip_count / total_connections

        # Rare IP (<0.1% of all connections)
        if ip_frequency < 0.001:
            score += 20
        elif ip_frequency < 0.005:  # Uncommon IP (<0.5% of connections)
            score += 10
        elif ip_frequency < 0.01:   # Slightly uncommon (<1% of connections)
            score += 5

        return score

    def _check_connection_frequency(self, event: Dict[str, Any]) -> int:
        """Check for unusually high connection frequency"""
        score = 0
        pid = event.get('pid', 0)
        current_time = time.time()

        # Get recent connections for this process (last 60 seconds)
        recent_connections = [
            conn for conn in self.process_connection_history[pid]
            if current_time - conn['timestamp'] <= 60
        ]

        connection_rate = len(recent_connections)

        # High frequency connections
        if connection_rate > 100:  # >100 connections/minute
            score += 25
        elif connection_rate > 50:   # >50 connections/minute
            score += 15
        elif connection_rate > 20:   # >20 connections/minute
            score += 10
        elif connection_rate > 10:   # >10 connections/minute
            score += 5

        # Check for connection bursts
        if len(recent_connections) >= 3:
            # Check if multiple connections to same destination
            dst_counts = defaultdict(int)
            for conn in recent_connections:
                dst_counts[conn['dst_ip']] += 1

            max_dst_count = max(dst_counts.values())
            if max_dst_count > 20:  # Many connections to same destination
                score += 15

        return score

    def _check_suspicious_ports(self, event: Dict[str, Any]) -> int:
        """Check connections to suspicious ports"""
        score = 0
        dst_port = event.get('dport', 0)

        # Check if it's a known suspicious port
        if dst_port in self.suspicious_ports:
            score += 30

        # Check if it's an unusual high port
        if dst_port > 49152 and dst_port not in self.safe_ports:
            score += 10  # High dynamic port

        # Check for non-standard service ports
        if dst_port not in self.safe_ports and dst_port < 1024:
            score += 15

        return score

    def _check_unusual_timing(self, event: Dict[str, Any]) -> int:
        """Check for connections at unusual times"""
        score = 0
        current_hour = datetime.now().hour

        # Late night connections (2AM - 6AM)
        if 2 <= current_hour <= 6:
            score += 10

        # Weekend connections to unusual destinations
        if datetime.now().weekday() >= 5:  # Saturday or Sunday
            dst_port = event.get('dport', 0)
            if dst_port not in self.safe_ports:
                score += 5

        return score

    def _check_first_time_process(self, event: Dict[str, Any]) -> int:
        """Check if this is the first network connection from a process"""
        score = 0
        pid = event.get('pid', 0)

        if pid not in self.process_first_connection:
            self.process_first_connection.add(pid)

            # Check if it's a system process making its first connection
            process_name = event.get('process_name', '').lower()
            system_processes = {'systemd', 'kernel', 'init', 'kthreadd'}

            if process_name in system_processes:
                score += 30  # System processes shouldn't make network connections
            else:
                score += 15  # First connection is moderately suspicious

        return score

    def _check_geographic_anomalies(self, event: Dict[str, Any]) -> int:
        """Check for connections to unusual geographic locations"""
        score = 0

        # This is a placeholder - in a real implementation, you would use
        # a geoIP database to determine the country of the destination IP
        dst_ip = event.get('dst_ip', '')

        # For now, just check if it's a private IP (less suspicious)
        if event.get('is_private', False):
            return 0

        # Add placeholder score for non-private IPs
        # In real implementation, you'd check country codes against self.suspicious_countries
        score += 5

        return score

    def _check_process_anomalies(self, event: Dict[str, Any]) -> int:
        """Check for suspicious process characteristics"""
        score = 0
        process_name = event.get('process_name', '').lower()
        cmdline = event.get('cmdline_full', '').lower()
        exe_path = event.get('exe_path', '').lower()

        # Suspicious process names
        suspicious_names = {'nc', 'ncat', 'netcat', 'python', 'perl', 'bash', 'sh'}
        if any(sus_name in process_name for sus_name in suspicious_names):
            score += 20

        # Check for suspicious command line arguments
        suspicious_args = {'-e', '--execute', '/bin/sh', '/bin/bash', 'reverse', 'shell'}
        if any(sus_arg in cmdline for sus_arg in suspicious_args):
            score += 25

        # Check if executable is in temporary directory
        if '/tmp/' in exe_path or '/var/tmp/' in exe_path:
            score += 30

        # Check for hidden executables
        if exe_path and exe_path.startswith('/.'):
            score += 20

        return score

    def _check_connection_patterns(self, event: Dict[str, Any]) -> int:
        """Check for unusual connection patterns"""
        score = 0
        pid = event.get('pid', 0)
        dst_ip = event.get('dst_ip', '')

        # Check if process connects to many different destinations
        if pid in self.process_connection_history:
            unique_destinations = set(conn['dst_ip'] for conn in self.process_connection_history[pid])
            if len(unique_destinations) > 50:
                score += 15
            elif len(unique_destinations) > 20:
                score += 10
            elif len(unique_destinations) > 10:
                score += 5

        # Check sequential port scanning pattern
        recent_connections = [
            conn for conn in self.process_connection_history[pid]
            if time.time() - conn['timestamp'] <= 30  # Last 30 seconds
        ]

        if len(recent_connections) >= 5:
            ports = [conn['dst_port'] for conn in recent_connections]
            ports.sort()

            # Check if ports are sequential (possible port scanning)
            sequential_count = 1
            for i in range(1, len(ports)):
                if ports[i] == ports[i-1] + 1:
                    sequential_count += 1
                else:
                    sequential_count = 1

            if sequential_count >= 5:
                score += 20

        return score

    def _ml_anomaly_detection(self, event: Dict[str, Any]) -> float:
        """
        Machine learning based anomaly detection
        Simplified version - in production, you'd use scikit-learn models
        """
        try:
            # Extract features for ML analysis
            features = self._extract_features(event)

            # Simple statistical anomaly detection
            # In production, this would use IsolationForest or similar
            if len(self.connection_features) < 100:  # Need training data
                self.connection_features.append(features)
                return 0.0

            # Calculate statistical distance from normal patterns
            mean_features = np.mean(self.connection_features, axis=0)
            std_features = np.std(self.connection_features, axis=0) + 1e-8

            # Z-score based anomaly detection
            z_scores = np.abs((features - mean_features) / std_features)
            anomaly_score = np.mean(z_scores)

            # Convert to 0-1 scale (higher is more anomalous)
            normalized_score = min(1.0, anomaly_score / 3.0)

            # Add to training data if it looks normal
            if normalized_score < self.anomaly_threshold:
                self.connection_features.append(features)
                # Keep feature list manageable
                if len(self.connection_features) > 10000:
                    self.connection_features = self.connection_features[-5000:]

            return normalized_score

        except Exception as e:
            logger.error(f"ML anomaly detection error: {e}")
            return 0.0

    def _extract_features(self, event: Dict[str, Any]) -> np.ndarray:
        """Extract numerical features for ML analysis"""
        features = [
            event.get('dport', 0) / 65535.0,  # Normalized port
            event.get('sport', 0) / 65535.0,  # Normalized source port
            int(event.get('is_private', False)),
            int(event.get('is_safe_port', True)),
            len(event.get('process_name', '')) / 50.0,  # Process name length
            len(event.get('cmdline_full', '')) / 200.0,  # Command line length
            datetime.now().hour / 24.0,  # Time of day
            datetime.now().weekday() / 7.0,  # Day of week
        ]

        return np.array(features)

    def get_process_threat_analysis(self, pid: int) -> Dict[str, Any]:
        """Get detailed threat analysis for a specific process"""
        if pid not in self.process_connection_history:
            return {"error": "Process not found"}

        connections = list(self.process_connection_history[pid])
        if not connections:
            return {"error": "No connections found"}

        # Analyze connection patterns
        unique_destinations = len(set(conn['dst_ip'] for conn in connections))
        unique_ports = len(set(conn['dst_port'] for conn in connections))
        connection_rate = len(connections) / max(1, (time.time() - connections[0]['timestamp']) / 60)  # per minute

        # Calculate average threat score (this would need to be tracked per connection)
        # For now, provide pattern-based analysis
        risk_factors = []

        if connection_rate > 50:
            risk_factors.append("High connection frequency")
        if unique_destinations > 20:
            risk_factors.append("Many unique destinations")
        if unique_ports > 10:
            risk_factors.append("Port scanning pattern")

        # Calculate overall risk level
        risk_score = min(100, (connection_rate * 0.5) + (unique_destinations * 2) + (unique_ports * 3))

        if risk_score >= 75:
            risk_level = "Critical"
        elif risk_score >= 50:
            risk_level = "High"
        elif risk_score >= 25:
            risk_level = "Medium"
        else:
            risk_level = "Low"

        return {
            "risk_level": risk_level,
            "risk_score": int(risk_score),
            "risk_factors": risk_factors,
            "connection_stats": {
                "total_connections": len(connections),
                "unique_destinations": unique_destinations,
                "unique_ports": unique_ports,
                "connection_rate_per_minute": round(connection_rate, 2)
            }
        }

    def get_statistics(self) -> Dict[str, Any]:
        """Get threat detection statistics"""
        return {
            "total_analyzed": self.total_analyzed,
            "suspicious_detected": self.suspicious_detected,
            "suspicious_percentage": (self.suspicious_detected / self.total_analyzed * 100) if self.total_analyzed > 0 else 0,
            "uptime_seconds": time.time() - self.start_time,
            "unique_ips_tracked": len(self.ip_frequency),
            "processes_tracked": len(self.process_connection_history),
            "ml_training_samples": len(self.connection_features)
        }