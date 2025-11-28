import React, { useState, useEffect } from 'react';
import styled from 'styled-components';
import { format } from 'date-fns';

interface ProcessDetailsProps {
  process: any;
  onClose: () => void;
  theme: any;
  sendMessage: (message: any) => void;
}

interface ProcessAnalysis {
  risk_level: string;
  risk_score: number;
  risk_factors: string[];
  connection_stats: {
    total_connections: number;
    unique_destinations: number;
    unique_ports: number;
    connection_rate_per_minute: number;
  };
}

const DetailsContainer = styled.div`
  height: 100%;
  display: flex;
  flex-direction: column;
  background-color: ${props => props.theme.colors.surface};
  color: ${props => props.theme.colors.text.primary};
`;

const DetailsHeader = styled.div`
  padding: 20px;
  border-bottom: 1px solid ${props => props.theme.colors.border};
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
`;

const HeaderContent = styled.div`
  flex: 1;
`;

const ProcessName = styled.h2`
  margin: 0 0 8px 0;
  font-size: 18px;
  font-weight: 600;
  color: ${props => props.theme.colors.text.primary};
  display: flex;
  align-items: center;
  gap: 10px;
`;

const CloseButton = styled.button`
  background: none;
  border: none;
  font-size: 20px;
  cursor: pointer;
  color: ${props => props.theme.colors.text.secondary};
  padding: 0;
  width: 30px;
  height: 30px;
  border-radius: 4px;
  display: flex;
  align-items: center;
  justify-content: center;

  &:hover {
    background-color: ${props => props.theme.colors.border};
    color: ${props => props.theme.colors.text.primary};
  }
`;

const DetailsBody = styled.div`
  flex: 1;
  overflow-y: auto;
  padding: 20px;
`;

const Section = styled.div`
  margin-bottom: 30px;

  h3 {
    margin: 0 0 15px 0;
    font-size: 14px;
    font-weight: 600;
    text-transform: uppercase;
    color: ${props => props.theme.colors.text.secondary};
    letter-spacing: 0.5px;
  }
`;

const InfoRow = styled.div`
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 8px 0;
  border-bottom: 1px solid ${props => props.theme.colors.border};
  font-size: 14px;

  &:last-child {
    border-bottom: none;
  }
`;

const InfoLabel = styled.span`
  color: ${props => props.theme.colors.text.secondary};
  font-weight: 500;
`;

const InfoValue = styled.span`
  color: ${props => props.theme.colors.text.primary};
  text-align: right;
  word-break: break-all;
`;

const RiskBadge = styled.span<{ $level: string }>`
  padding: 4px 8px;
  border-radius: 4px;
  font-size: 12px;
  font-weight: 600;
  background-color: ${props => {
    switch (props.$level) {
      case 'Critical': return 'rgba(188, 140, 255, 0.3)';
      case 'High': return 'rgba(248, 81, 73, 0.3)';
      case 'Medium': return 'rgba(248, 81, 73, 0.2)';
      case 'Low': return 'rgba(88, 166, 255, 0.2)';
      default: return 'rgba(139, 148, 158, 0.2)';
    }
  }};
  color: ${props => {
    switch (props.$level) {
      case 'Critical': return props.theme.colors.graph.node.critical;
      case 'High': return props.theme.colors.graph.node.suspicious;
      case 'Medium': return props.theme.colors.graph.node.warning;
      case 'Low': return props.theme.colors.graph.node.safe;
      default: return props.theme.colors.text.secondary;
    }
  }};
`;

const RiskFactor = styled.div`
  padding: 8px 12px;
  margin-bottom: 8px;
  background-color: ${props => props.theme.colors.border};
  border-radius: 6px;
  font-size: 13px;
  color: ${props => props.theme.colors.text.primary};
  display: flex;
  align-items: center;
  gap: 8px;

  &:before {
    content: '⚠️';
    font-size: 14px;
  }
`;

const ActionButton = styled.button<{ $danger?: boolean }>`
  width: 100%;
  padding: 12px;
  margin-bottom: 10px;
  background: none;
  border: 1px solid ${props => props.theme.colors.border};
  border-radius: 6px;
  color: ${props => props.theme.colors.text.primary};
  cursor: pointer;
  font-size: 14px;
  transition: all 0.2s ease;

  &:hover {
    background-color: ${props => props.theme.colors.border};
  }

  ${props => props.$danger && `
    border-color: ${props.theme.colors.graph.node.suspicious};
    color: ${props.theme.colors.graph.node.suspicious};

    &:hover {
      background-color: ${props.theme.colors.graph.node.suspicious};
      color: white;
    }
  `}
`;

const ConnectionsList = styled.div`
  max-height: 400px;
  overflow-y: auto;
  border: 1px solid ${props => props.theme.colors.border};
  border-radius: 6px;
  background-color: ${props => props.theme.colors.background};
`;

const ConnectionItem = styled.div`
  padding: 12px;
  border-bottom: 1px solid ${props => props.theme.colors.border};
  font-size: 13px;

  &:last-child {
    border-bottom: none;
  }

  &:hover {
    background-color: ${props => props.theme.colors.surface};
  }
`;

const ConnectionHeader = styled.div`
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 6px;
  font-weight: 500;
`;

const ConnectionDetails = styled.div`
  font-size: 12px;
  color: ${props => props.theme.colors.text.secondary};
  line-height: 1.4;
`;

const ProcessDetails: React.FC<ProcessDetailsProps> = ({ process, onClose, theme, sendMessage }) => {
  const [processAnalysis, setProcessAnalysis] = useState<ProcessAnalysis | null>(null);
  const [recentConnections, setRecentConnections] = useState<any[]>([]);

  // Format timestamp
  const formatTimestamp = (timestamp: number) => {
    try {
      return format(new Date(timestamp / 1000000), 'MMM dd, yyyy HH:mm:ss');
    } catch {
      return 'Unknown';
    }
  };

  // Format duration
  const formatDuration = (startTime: number) => {
    try {
      const now = Date.now();
      const start = startTime / 1000000; // Convert from nanoseconds
      const diff = now - start;

      const seconds = Math.floor(diff / 1000);
      const minutes = Math.floor(seconds / 60);
      const hours = Math.floor(minutes / 60);
      const days = Math.floor(hours / 24);

      if (days > 0) return `${days}d ${hours % 24}h`;
      if (hours > 0) return `${hours}h ${minutes % 60}m`;
      if (minutes > 0) return `${minutes}m ${seconds % 60}s`;
      return `${seconds}s`;
    } catch {
      return 'Unknown';
    }
  };

  // Fetch detailed process analysis
  useEffect(() => {
    // This would normally fetch from the WebSocket API
    // For now, we'll create a mock analysis
    const mockAnalysis: ProcessAnalysis = {
      risk_level: process.threatScore >= 75 ? 'Critical' :
                 process.threatScore >= 50 ? 'High' :
                 process.threatScore >= 25 ? 'Medium' : 'Low',
      risk_score: process.threatScore || 0,
      risk_factors: process.isSuspicious ? [
        'High connection frequency',
        'Connections to suspicious ports',
        'Unusual network activity detected'
      ] : [],
      connection_stats: {
        total_connections: process.connectionCount || 0,
        unique_destinations: process.unique_destinations?.length || 1,
        unique_ports: 1,
        connection_rate_per_minute: process.connection_rate_per_minute || 0
      }
    };

    setProcessAnalysis(mockAnalysis);
    setRecentConnections([]); // Would fetch from API
  }, [process]);

  if (!process) {
    return <div>No process selected</div>;
  }

  return (
    <DetailsContainer>
      <DetailsHeader>
        <HeaderContent>
          <ProcessName>
            📁 {process.processName || 'Unknown Process'}
            {process.isSuspicious && <RiskBadge $level="High">🚨 Suspicious</RiskBadge>}
          </ProcessName>
          <div style={{ fontSize: '12px', color: theme.colors.text.secondary }}>
            PID: {process.pid}
          </div>
        </HeaderContent>
        <CloseButton onClick={onClose}>×</CloseButton>
      </DetailsHeader>

      <DetailsBody>
        {/* Basic Information */}
        <Section>
          <h3>Basic Information</h3>
          <InfoRow>
            <InfoLabel>Process ID</InfoLabel>
            <InfoValue>{process.pid}</InfoValue>
          </InfoRow>
          <InfoRow>
            <InfoLabel>Process Name</InfoLabel>
            <InfoValue>{process.processName || 'Unknown'}</InfoValue>
          </InfoRow>
          <InfoRow>
            <InfoLabel>Command Line</InfoLabel>
            <InfoValue>{process.cmdline || process.cmdlineFull || 'Unknown'}</InfoValue>
          </InfoRow>
          <InfoRow>
            <InfoLabel>Executable Path</InfoLabel>
            <InfoValue>{process.exePath || 'Unknown'}</InfoValue>
          </InfoRow>
          <InfoRow>
            <InfoLabel>Username</InfoLabel>
            <InfoValue>{process.username || 'Unknown'}</InfoValue>
          </InfoRow>
          <InfoRow>
            <InfoLabel>Start Time</InfoLabel>
            <InfoValue>{process.createTime ? formatTimestamp(process.createTime * 1000000) : 'Unknown'}</InfoValue>
          </InfoRow>
          <InfoRow>
            <InfoLabel>Duration</InfoLabel>
            <InfoValue>{process.createTime ? formatDuration(process.createTime * 1000000) : 'Unknown'}</InfoValue>
          </InfoRow>
        </Section>

        {/* Threat Analysis */}
        {processAnalysis && (
          <Section>
            <h3>Threat Analysis</h3>
            <InfoRow>
              <InfoLabel>Risk Level</InfoLabel>
              <InfoValue>
                <RiskBadge $level={processAnalysis.risk_level}>
                  {processAnalysis.risk_level}
                </RiskBadge>
              </InfoValue>
            </InfoRow>
            <InfoRow>
              <InfoLabel>Threat Score</InfoLabel>
              <InfoValue>{processAnalysis.risk_score}/100</InfoValue>
            </InfoRow>
            <InfoRow>
              <InfoLabel>Total Connections</InfoLabel>
              <InfoValue>{processAnalysis.connection_stats.total_connections}</InfoValue>
            </InfoRow>
            <InfoRow>
              <InfoLabel>Unique Destinations</InfoLabel>
              <InfoValue>{processAnalysis.connection_stats.unique_destinations}</InfoValue>
            </InfoRow>
            <InfoRow>
              <InfoLabel>Connection Rate</InfoLabel>
              <InfoValue>{processAnalysis.connection_stats.connection_rate_per_minute.toFixed(1)}/min</InfoValue>
            </InfoRow>

            {processAnalysis.risk_factors.length > 0 && (
              <div style={{ marginTop: '15px' }}>
                <div style={{ fontSize: '12px', fontWeight: 500, marginBottom: '8px', color: theme.colors.text.secondary }}>
                  Risk Factors:
                </div>
                {processAnalysis.risk_factors.map((factor, index) => (
                  <RiskFactor key={index}>{factor}</RiskFactor>
                ))}
              </div>
            )}
          </Section>
        )}

        {/* Actions */}
        <Section>
          <h3>Actions</h3>
          <ActionButton
            onClick={() => {
              window.open(`https://www.google.com/search?q=${process.processName || 'unknown process'}+process`, '_blank');
            }}
          >
            🔍 Search Process Online
          </ActionButton>
          <ActionButton onClick={() => alert('Export functionality is not yet implemented.')}>
            📊 Export Process Details
          </ActionButton>
          <ActionButton onClick={() => alert('Block functionality is not yet implemented.')}>
            🚫 Block Network Access
          </ActionButton>
          <ActionButton
            $danger
            onClick={() => {
              if (window.confirm(`Are you sure you want to kill process ${process.pid}?`)) {
                sendMessage({ type: 'kill_process', data: { pid: process.pid } });
              }
            }}
          >
            ⚠️ Kill Process
          </ActionButton>
        </Section>

        {/* Recent Connections */}
        <Section>
          <h3>Recent Network Connections</h3>
          <ConnectionsList>
            {recentConnections.length > 0 ? (
              recentConnections.map((connection, index) => (
                <ConnectionItem key={index}>
                  <ConnectionHeader>
                    <span>{connection.dst_ip}:{connection.dst_port}</span>
                    <span style={{ color: connection.is_suspicious ? theme.colors.graph.node.suspicious : theme.colors.graph.node.safe }}>
                      {connection.is_suspicious ? '⚠️' : '✅'}
                    </span>
                  </ConnectionHeader>
                  <ConnectionDetails>
                    <div>Protocol: {connection.protocol_str}</div>
                    <div>Time: {formatTimestamp(connection.timestamp)}</div>
                    <div>Threat Score: {connection.threat_score}</div>
                  </ConnectionDetails>
                </ConnectionItem>
              ))
            ) : (
              <div style={{ padding: '20px', textAlign: 'center', color: theme.colors.text.secondary }}>
                No recent connections available
              </div>
            )}
          </ConnectionsList>
        </Section>
      </DetailsBody>
    </DetailsContainer>
  );
};

export default ProcessDetails;