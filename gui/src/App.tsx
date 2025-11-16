import React, { useState, useEffect, useContext, createContext } from 'react';
import styled, { ThemeProvider, createGlobalStyle } from 'styled-components';
import NetworkGraph from './components/NetworkGraph';
import ProcessDetails from './components/ProcessDetails';
import useWebSocket from './hooks/useWebSocket';

// Theme definition
const lightTheme = {
  name: 'light',
  colors: {
    background: '#ffffff',
    surface: '#f6f8fa',
    border: '#d1d9e0',
    text: {
      primary: '#24292f',
      secondary: '#656d76',
      muted: '#8b949e'
    },
    graph: {
      background: '#fafbfc',
      node: {
        safe: '#0969da',
        warning: '#9a6700',
        suspicious: '#cf222e',
        critical: '#8250df'
      },
      edge: {
        safe: '#0969da',
        warning: '#9a6700',
        suspicious: '#cf222e',
        critical: '#8250df'
      }
    },
    status: {
      online: '#1a7f37',
      offline: '#cf222e',
      warning: '#9a6700'
    }
  }
};

const darkTheme = {
  name: 'dark',
  colors: {
    background: '#0d1117',
    surface: '#161b22',
    border: '#30363d',
    text: {
      primary: '#c9d1d9',
      secondary: '#8b949e',
      muted: '#656d76'
    },
    graph: {
      background: '#0d1117',
      node: {
        safe: '#58a6ff',
        warning: '#f85149',
        suspicious: '#f85149',
        critical: '#bc8cff'
      },
      edge: {
        safe: '#58a6ff',
        warning: '#f85149',
        suspicious: '#f85149',
        critical: '#bc8cff'
      }
    },
    status: {
      online: '#3fb950',
      offline: '#f85149',
      warning: '#d29922'
    }
  }
};

// Global styles
const GlobalStyle = createGlobalStyle`
  * {
    box-sizing: border-box;
  }

  body {
    margin: 0;
    padding: 0;
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Oxygen',
      'Ubuntu', 'Cantarell', 'Fira Sans', 'Droid Sans', 'Helvetica Neue',
      sans-serif;
    background-color: ${props => props.theme.colors.background};
    color: ${props => props.theme.colors.text.primary};
    overflow: hidden;
  }

  code {
    font-family: source-code-pro, Menlo, Monaco, Consolas, 'Courier New',
      monospace;
  }

  /* Scrollbar styling */
  ::-webkit-scrollbar {
    width: 8px;
    height: 8px;
  }

  ::-webkit-scrollbar-track {
    background: ${props => props.theme.colors.surface};
  }

  ::-webkit-scrollbar-thumb {
    background: ${props => props.theme.colors.border};
    border-radius: 4px;
  }

  ::-webkit-scrollbar-thumb:hover {
    background: ${props => props.theme.colors.text.muted};
  }

  /* Selection styling */
  ::selection {
    background-color: ${props => props.theme.colors.graph.node.safe};
    color: ${props => props.theme.colors.background};
  }
`;

// Theme context
interface ThemeContextType {
  theme: typeof lightTheme;
  toggleTheme: () => void;
  isDark: boolean;
}

const ThemeContext = createContext<ThemeContextType | undefined>(undefined);

// Styled components
const AppContainer = styled.div`
  width: 100vw;
  height: 100vh;
  display: flex;
  flex-direction: column;
  background-color: ${props => props.theme.colors.background};
  color: ${props => props.theme.colors.text.primary};
`;

const Header = styled.header`
  height: 60px;
  background-color: ${props => props.theme.colors.surface};
  border-bottom: 1px solid ${props => props.theme.colors.border};
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0 20px;
  flex-shrink: 0;
`;

const HeaderLeft = styled.div`
  display: flex;
  align-items: center;
  gap: 20px;
`;

const HeaderRight = styled.div`
  display: flex;
  align-items: center;
  gap: 15px;
`;

const Title = styled.h1`
  font-size: 24px;
  font-weight: 600;
  margin: 0;
  color: ${props => props.theme.colors.text.primary};
`;

const StatusIndicator = styled.div<{ $status: 'online' | 'offline' | 'warning' }>`
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 6px 12px;
  border-radius: 6px;
  background-color: ${props => {
    switch (props.$status) {
      case 'online': return 'rgba(63, 185, 80, 0.1)';
      case 'offline': return 'rgba(248, 81, 73, 0.1)';
      case 'warning': return 'rgba(210, 153, 34, 0.1)';
    }
  }};
  color: ${props => props.theme.colors.status[props.$status]};
  font-size: 14px;
  font-weight: 500;
`;

const StatusDot = styled.div<{ $status: 'online' | 'offline' | 'warning' }>`
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background-color: ${props => props.theme.colors.status[props.$status]};
  animation: ${props => props.$status === 'online' ? 'pulse 2s infinite' : 'none'};

  @keyframes pulse {
    0%, 100% {
      opacity: 1;
    }
    50% {
      opacity: 0.5;
    }
  }
`;

const MainContent = styled.main`
  flex: 1;
  display: flex;
  overflow: hidden;
`;

const GraphContainer = styled.div`
  flex: 1;
  position: relative;
  background-color: ${props => props.theme.colors.graph.background};
`;

const Sidebar = styled.aside<{ $isOpen: boolean }>`
  width: ${props => props.$isOpen ? '400px' : '0'};
  background-color: ${props => props.theme.colors.surface};
  border-left: 1px solid ${props => props.theme.colors.border};
  transition: width 0.3s ease;
  overflow: hidden;
  display: flex;
  flex-direction: column;
`;

const Footer = styled.footer`
  height: 40px;
  background-color: ${props => props.theme.colors.surface};
  border-top: 1px solid ${props => props.theme.colors.border};
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0 20px;
  font-size: 12px;
  color: ${props => props.theme.colors.text.secondary};
`;

const StatsContainer = styled.div`
  display: flex;
  gap: 20px;
`;

const StatItem = styled.div`
  display: flex;
  align-items: center;
  gap: 5px;
`;

const ThreatBadge = styled.span<{ $level: 'low' | 'medium' | 'high' | 'critical' }>`
  padding: 2px 8px;
  border-radius: 4px;
  font-size: 11px;
  font-weight: 600;
  background-color: ${props => {
    switch (props.$level) {
      case 'low': return 'rgba(88, 166, 255, 0.2)';
      case 'medium': return 'rgba(248, 81, 73, 0.2)';
      case 'high': return 'rgba(248, 81, 73, 0.3)';
      case 'critical': return 'rgba(188, 140, 255, 0.3)';
    }
  }};
  color: ${props => {
    switch (props.$level) {
      case 'low': return props.theme.colors.graph.node.safe;
      case 'medium': return props.theme.colors.graph.node.warning;
      case 'high': return props.theme.colors.graph.node.suspicious;
      case 'critical': return props.theme.colors.graph.node.critical;
    }
  }};
`;

const ThemeToggle = styled.button`
  background: none;
  border: 1px solid ${props => props.theme.colors.border};
  border-radius: 6px;
  padding: 6px 10px;
  color: ${props => props.theme.colors.text.secondary};
  cursor: pointer;
  font-size: 14px;
  transition: all 0.2s ease;

  &:hover {
    background-color: ${props => props.theme.colors.border};
    color: ${props => props.theme.colors.text.primary};
  }
`;

// Main App component
const App: React.FC = () => {
  console.log('App component rendered. window.electronAPI:', window.electronAPI);
  const [isDark, setIsDark] = useState(() => {
    // Check system preference and localStorage
    if (typeof window !== 'undefined') {
      const saved = localStorage.getItem('netviz-theme');
      if (saved) return saved === 'dark';
      return window.matchMedia('(prefers-color-scheme: dark)').matches;
    }
    return true;
  });

  const [selectedProcess, setSelectedProcess] = useState<any>(null);
  const [sidebarOpen, setSidebarOpen] = useState(false);

  const theme = isDark ? darkTheme : lightTheme;

  // WebSocket hook
  const {
    isConnected,
    connections,
    statistics,
    threatCount,
    connectionStatus
  } = useWebSocket('ws://localhost:8080/ws/realtime');

  // Theme management
  useEffect(() => {
    localStorage.setItem('netviz-theme', isDark ? 'dark' : 'light');
  }, [isDark]);

  const toggleTheme = () => {
    setIsDark(!isDark);
  };

  // Handle node selection in graph
  const handleNodeSelect = (processData: any) => {
    setSelectedProcess(processData);
    setSidebarOpen(true);
  };

  // Get connection status for header
  const getConnectionStatus = (): 'online' | 'offline' | 'warning' => {
    if (isConnected) return 'online';
    if (connectionStatus === 'connecting') return 'warning';
    return 'offline';
  };

  return (
    <ThemeContext.Provider value={{ theme, toggleTheme, isDark }}>
      <ThemeProvider theme={theme}>
        <GlobalStyle />
        <AppContainer>
          <Header>
            <HeaderLeft>
              <Title>🌐 NetViz</Title>
              <StatusIndicator $status={getConnectionStatus()}>
                <StatusDot $status={getConnectionStatus()} />
                {isConnected ? 'Connected' : connectionStatus === 'connecting' ? 'Connecting...' : 'Disconnected'}
              </StatusIndicator>
              {threatCount > 0 && (
                <ThreatBadge $level={threatCount > 10 ? 'critical' : threatCount > 5 ? 'high' : threatCount > 1 ? 'medium' : 'low'}>
                  {threatCount} Threat{threatCount !== 1 ? 's' : ''}
                </ThreatBadge>
              )}
            </HeaderLeft>
            <HeaderRight>
              <ThemeToggle onClick={toggleTheme}>
                {isDark ? '☀️' : '🌙'}
              </ThemeToggle>
            </HeaderRight>
          </Header>

          <MainContent>
            <GraphContainer>
              <NetworkGraph
                connections={connections}
                onNodeSelect={handleNodeSelect}
                selectedProcess={selectedProcess}
                theme={theme}
              />
            </GraphContainer>

            <Sidebar $isOpen={sidebarOpen}>
              {selectedProcess && (
                <ProcessDetails
                  process={selectedProcess}
                  onClose={() => setSidebarOpen(false)}
                  theme={theme}
                />
              )}
            </Sidebar>
          </MainContent>

          <Footer>
            <StatsContainer>
              <StatItem>
                <span>Total Connections:</span>
                <strong>{statistics.totalConnections || 0}</strong>
              </StatItem>
              <StatItem>
                <span>Active Processes:</span>
                <strong>{statistics.activeProcesses || 0}</strong>
              </StatItem>
              <StatItem>
                <span>Suspicious:</span>
                <strong style={{ color: theme.colors.graph.node.suspicious }}>
                  {statistics.suspiciousConnections || 0}
                </strong>
              </StatItem>
            </StatsContainer>
            <div>
              NetViz v1.0.0 | {typeof window !== 'undefined' && window.electronAPI ?
                window.electronAPI.platform : 'Web'}
            </div>
          </Footer>
        </AppContainer>
      </ThemeProvider>
    </ThemeContext.Provider>
  );
};

// Hook to use theme context
export const useTheme = () => {
  const context = useContext(ThemeContext);
  if (context === undefined) {
    throw new Error('useTheme must be used within a ThemeProvider');
  }
  return context;
};

export default App;
