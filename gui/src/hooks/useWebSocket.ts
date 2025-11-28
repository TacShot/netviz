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

  // --- Function Declarations ---

  const transformConnection = (data: any): Connection => ({
    id: data.id,
    timestamp: data.timestamp,
    pid: data.pid,
    processName: data.process_name,
    cmdlineFull: data.cmdline_full,
    srcIp: data.src_ip,
    dstIp: data.dst_ip,
    srcPort: data.sport,
    dstPort: data.dport,
    protocolStr: data.protocol_str,
    threatScore: data.threat_score,
    isSuspicious: data.is_suspicious,
    username: data.username,
    exePath: data.exe_path,
    isPrivate: data.is_private,
    isSafePort: data.is_safe_port,
  });

  // These handlers are simple state setters, so they can be defined first.
  const handleNewConnection = useCallback((connectionData: any) => {
    const transformedData = transformConnection(connectionData);
    setConnections(prev => [transformedData, ...prev].slice(0, 1000));
    if (transformedData.isSuspicious) {
      setThreatCount(prev => prev + 1);
    }
  }, []);

  const handleInitialData = useCallback((data: any) => {
    if (data.connections) {
      const transformedConnections = data.connections.map(transformConnection);
      setConnections(transformedConnections.slice(0, 1000));
      setThreatCount(transformedConnections.filter((c: Connection) => c.isSuspicious).length);
    }
    if (data.server_info) {
      console.log('Server info:', data.server_info);
    }
  }, []);

  const handleConnectionsData = useCallback((data: any) => {
    if (data.connections) {
      const transformedConnections = data.connections.map(transformConnection);
      setConnections(transformedConnections.slice(0, 1000));
      setThreatCount(transformedConnections.filter((c: Connection) => c.isSuspicious).length);
    }
  }, []);

  const handleStatisticsData = useCallback((data: any) => {
    setStatistics(prev => ({ ...prev, ...data }));
  }, []);

  const handleMessage = useCallback((message: any) => {
    switch (message.type) {
      case 'connection': handleNewConnection(message.data); break;
      case 'initial_data': handleInitialData(message.data); break;
      case 'connections': handleConnectionsData(message.data); break;
      case 'statistics': handleStatisticsData(message.data); break;
      case 'pong': break;
      case 'error': console.error('Server error:', message.data.error); break;
      default: console.log('Unknown message type:', message.type);
    }
  }, [handleNewConnection, handleInitialData, handleConnectionsData, handleStatisticsData]);

  const sendMessage = useCallback((message: any) => {
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      wsRef.current.send(JSON.stringify(message));
    } else {
      console.warn('WebSocket not connected, cannot send message:', message);
    }
  }, []);

  const stopHeartbeat = useCallback(() => {
    if (heartbeatIntervalRef.current) {
      clearInterval(heartbeatIntervalRef.current);
      heartbeatIntervalRef.current = null;
    }
  }, []);

  const startHeartbeat = useCallback(() => {
    stopHeartbeat(); // Ensure no multiple heartbeats
    heartbeatIntervalRef.current = setInterval(() => {
      sendMessage({ type: 'ping', data: { timestamp: Date.now() } });
    }, 30000);
  }, [sendMessage, stopHeartbeat]);

  const getReconnectDelay = useCallback(() => {
    const delay = Math.min(baseReconnectDelay * Math.pow(2, reconnectAttempts.current), maxReconnectDelay);
    return delay + Math.random() * 1000; // Add jitter
  }, []);

  // We need to use a ref to break the circular dependency between connect and scheduleReconnect
  const connectRef = useRef<() => void>();

  const scheduleReconnect = useCallback(() => {
    if (reconnectAttempts.current >= maxReconnectAttempts) {
      console.log('Max reconnection attempts reached');
      return;
    }
    const delay = getReconnectDelay();
    console.log(`Scheduling reconnection in ${delay}ms (attempt ${reconnectAttempts.current + 1})`);
    reconnectTimeoutRef.current = setTimeout(() => {
      reconnectAttempts.current++;
      connectRef.current?.();
    }, delay);
  }, [getReconnectDelay]);

  const connect = useCallback(() => {
    if (wsRef.current?.readyState === WebSocket.OPEN) return;

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
        startHeartbeat();
        sendMessage({ type: 'get_connections', data: { limit: 1000 } });
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
        if (event.code !== 1000) { // Don't reconnect on normal close
          scheduleReconnect();
        }
      };

      ws.onerror = (error) => {
        console.error('WebSocket error:', error);
        setConnectionStatus('error');
        // onclose will be called next, which will trigger reconnect
      };
    } catch (error) {
      console.error('Error creating WebSocket connection:', error);
      setConnectionStatus('error');
      scheduleReconnect();
    }
  }, [url, handleMessage, startHeartbeat, stopHeartbeat, sendMessage, scheduleReconnect]);

  // Assign the connect function to the ref for scheduleReconnect to use
  connectRef.current = connect;

  const reconnect = useCallback(() => {
    reconnectAttempts.current = 0;
    if (reconnectTimeoutRef.current) {
      clearTimeout(reconnectTimeoutRef.current);
    }
    connect();
  }, [connect]);

  // --- Effects ---

  // Initial connection
  useEffect(() => {
    connect();
  }, [connect]);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      if (reconnectTimeoutRef.current) {
        clearTimeout(reconnectTimeoutRef.current);
      }
      stopHeartbeat();
      if (wsRef.current) {
        wsRef.current.close(1000, 'Component unmounting');
      }
    };
  }, [stopHeartbeat]);


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
