import { useState, useEffect, useRef, useCallback } from 'react';

interface Connection {
  id: string;
  timestamp: number;
  pid: number;
  processName: string;
  cmdlineFull: string;
  srcIp: string;
  dstIp: string;
  srcPort: number;
  dstPort: number;
  protocolStr: string;
  threatScore: number;
  isSuspicious: boolean;
  username: string;
  exePath: string;
  isPrivate: boolean;
  isSafePort: boolean;
}

interface Statistics {
  totalConnections: number;
  activeConnections: number;
  activeProcesses: number;
  suspiciousConnections: number;
  suspiciousPercentage: number;
  uptimeSeconds: number;
  averageConnectionsPerSecond: number;
}

interface UseWebSocketReturn {
  isConnected: boolean;
  connections: Connection[];
  statistics: Statistics;
  threatCount: number;
  connectionStatus: 'disconnected' | 'connecting' | 'connected' | 'error';
  sendMessage: (message: any) => void;
  reconnect: () => void;
}

const useWebSocket = (url: string): UseWebSocketReturn => {
  const [isConnected, setIsConnected] = useState(false);
  const [connections, setConnections] = useState<Connection[]>([]);
  const [statistics, setStatistics] = useState<Statistics>({
    totalConnections: 0,
    activeConnections: 0,
    activeProcesses: 0,
    suspiciousConnections: 0,
    suspiciousPercentage: 0,
    uptimeSeconds: 0,
    averageConnectionsPerSecond: 0
  });
  const [threatCount, setThreatCount] = useState(0);
  const [connectionStatus, setConnectionStatus] = useState<'disconnected' | 'connecting' | 'connected' | 'error'>('disconnected');

  const wsRef = useRef<WebSocket | null>(null);
  const reconnectTimeoutRef = useRef<NodeJS.Timeout | null>(null);
  const heartbeatIntervalRef = useRef<NodeJS.Timeout | null>(null);
  const reconnectAttempts = useRef(0);
  const maxReconnectAttempts = 10;
  const baseReconnectDelay = 1000; // 1 second
  const maxReconnectDelay = 30000; // 30 seconds

  // Calculate exponential backoff delay
  const getReconnectDelay = useCallback(() => {
    const delay = Math.min(baseReconnectDelay * Math.pow(2, reconnectAttempts.current), maxReconnectDelay);
    return delay + Math.random() * 1000; // Add jitter
  }, []);

  // Handle WebSocket connection
  const connect = useCallback(() => {
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      return;
    }

    setConnectionStatus('connecting');
    setIsConnected(false);

    try {
      const ws = new WebSocket(url);
      wsRef.current = ws;

      ws.onopen = () => {
        console.log('WebSocket connected');
        setIsConnected(true);
        setConnectionStatus('connected');
        reconnectAttempts.current = 0;

        // Start heartbeat
        startHeartbeat();

        // Request initial data
        sendMessage({
          type: 'get_connections',
          data: { limit: 1000 }
        });
      };

      ws.onmessage = (event) => {
        try {
          const message = JSON.parse(event.data);
          handleMessage(message);
        } catch (error) {
          console.error('Error parsing WebSocket message:', error);
        }
      };

      ws.onclose = (event) => {
        console.log('WebSocket disconnected:', event.code, event.reason);
        setIsConnected(false);
        setConnectionStatus('disconnected');
        stopHeartbeat();

        // Attempt reconnection if not a normal closure
        if (event.code !== 1000) {
          scheduleReconnect();
        }
      };

      ws.onerror = (error) => {
        console.error('WebSocket error:', error);
        setConnectionStatus('error');
      };

    } catch (error) {
      console.error('Error creating WebSocket connection:', error);
      setConnectionStatus('error');
      scheduleReconnect();
    }
  }, [url]);

  // Schedule reconnection with exponential backoff
  const scheduleReconnect = useCallback(() => {
    if (reconnectAttempts.current >= maxReconnectAttempts) {
      console.log('Max reconnection attempts reached');
      return;
    }

    const delay = getReconnectDelay();
    console.log(`Scheduling reconnection in ${delay}ms (attempt ${reconnectAttempts.current + 1})`);

    reconnectTimeoutRef.current = setTimeout(() => {
      reconnectAttempts.current++;
      connect();
    }, delay);
  }, [connect, getReconnectDelay]);

  // Handle incoming messages
  const handleMessage = useCallback((message: any) => {
    switch (message.type) {
      case 'connection':
        handleNewConnection(message.data);
        break;

      case 'initial_data':
        handleInitialData(message.data);
        break;

      case 'connections':
        handleConnectionsData(message.data);
        break;

      case 'statistics':
        handleStatisticsData(message.data);
        break;

      case 'process_details':
        // Process details would be handled by a separate hook or component
        console.log('Process details received:', message.data);
        break;

      case 'pong':
        // Heartbeat response
        break;

      case 'error':
        console.error('Server error:', message.data.error);
        break;

      default:
        console.log('Unknown message type:', message.type);
    }
  }, []);

  // Handle new connection
  const handleNewConnection = useCallback((connectionData: Connection) => {
    setConnections(prev => {
      // Add new connection to the beginning of the array
      const updated = [connectionData, ...prev];
      // Keep only the most recent 1000 connections
      return updated.slice(0, 1000);
    });

    // Update threat count
    setThreatCount(prev => {
      const newThreatCount = connectionData.isSuspicious ? prev + 1 : prev;
      // Also check if this is already counted in our connections
      const suspiciousInConnections = connections.filter(c => c.isSuspicious).length;
      return suspiciousInConnections + (connectionData.isSuspicious ? 1 : 0);
    });
  }, [connections]);

  // Handle initial data
  const handleInitialData = useCallback((data: any) => {
    if (data.connections) {
      setConnections(data.connections.slice(0, 1000));
      setThreatCount(data.connections.filter((c: Connection) => c.isSuspicious).length);
    }

    if (data.server_info) {
      // Update server info if needed
      console.log('Server info:', data.server_info);
    }
  }, []);

  // Handle connections data
  const handleConnectionsData = useCallback((data: any) => {
    if (data.connections) {
      setConnections(data.connections.slice(0, 1000));
      setThreatCount(data.connections.filter((c: Connection) => c.isSuspicious).length);
    }
  }, []);

  // Handle statistics data
  const handleStatisticsData = useCallback((data: any) => {
    setStatistics(prev => ({
      ...prev,
      ...data
    }));
  }, []);

  // Start heartbeat
  const startHeartbeat = useCallback(() => {
    if (heartbeatIntervalRef.current) {
      clearInterval(heartbeatIntervalRef.current);
    }

    heartbeatIntervalRef.current = setInterval(() => {
      sendMessage({ type: 'ping', data: { timestamp: Date.now() } });
    }, 30000); // Send ping every 30 seconds
  }, []);

  // Stop heartbeat
  const stopHeartbeat = useCallback(() => {
    if (heartbeatIntervalRef.current) {
      clearInterval(heartbeatIntervalRef.current);
      heartbeatIntervalRef.current = null;
    }
  }, []);

  // Send message to WebSocket
  const sendMessage = useCallback((message: any) => {
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      wsRef.current.send(JSON.stringify(message));
    } else {
      console.warn('WebSocket not connected, cannot send message:', message);
    }
  }, []);

  // Manual reconnection
  const reconnect = useCallback(() => {
    reconnectAttempts.current = 0;
    if (reconnectTimeoutRef.current) {
      clearTimeout(reconnectTimeoutRef.current);
      reconnectTimeoutRef.current = null;
    }
    connect();
  }, [connect]);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      if (reconnectTimeoutRef.current) {
        clearTimeout(reconnectTimeoutRef.current);
      }
      if (heartbeatIntervalRef.current) {
        clearInterval(heartbeatIntervalRef.current);
      }
      if (wsRef.current) {
        wsRef.current.close(1000, 'Component unmounting');
      }
    };
  }, []);

  // Initial connection
  useEffect(() => {
    connect();
  }, [connect]);

  return {
    isConnected,
    connections,
    statistics,
    threatCount,
    connectionStatus,
    sendMessage,
    reconnect
  };
};

export default useWebSocket;
export type { Connection, Statistics, UseWebSocketReturn };