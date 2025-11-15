import React, { useEffect, useRef, useState, useCallback } from 'react';
import * as d3 from 'd3';
import { Connection } from '../hooks/useWebSocket';
import styled from 'styled-components';

interface GraphNode extends d3.SimulationNodeDatum {
  id: string;
  pid: number;
  processName: string;
  cmdline: string;
  username: string;
  exePath: string;
  threatScore: number;
  isSuspicious: boolean;
  connectionCount: number;
  lastSeen: number;
}

interface GraphLink extends d3.SimulationLinkDatum<GraphNode> {
  source: string | GraphNode;
  target: string | GraphNode;
  connection: Connection;
  value: number;
}

interface NetworkGraphProps {
  connections: Connection[];
  onNodeSelect: (node: any) => void;
  selectedProcess: any;
  theme: any;
}

const GraphContainer = styled.div`
  width: 100%;
  height: 100%;
  position: relative;
  overflow: hidden;
  background-color: ${props => props.theme.colors.graph.background};
`;

const GraphSvg = styled.svg`
  width: 100%;
  height: 100%;
  cursor: grab;

  &.dragging {
    cursor: grabbing;
  }
`;

const Controls = styled.div`
  position: absolute;
  top: 20px;
  right: 20px;
  display: flex;
  flex-direction: column;
  gap: 10px;
  z-index: 10;
`;

const ControlButton = styled.button`
  background-color: ${props => props.theme.colors.surface};
  border: 1px solid ${props => props.theme.colors.border};
  border-radius: 6px;
  padding: 8px 12px;
  color: ${props => props.theme.colors.text.secondary};
  cursor: pointer;
  font-size: 12px;
  transition: all 0.2s ease;

  &:hover {
    background-color: ${props => props.theme.colors.border};
    color: ${props => props.theme.colors.text.primary};
  }

  &:active {
    transform: scale(0.95);
  }
`;

const Tooltip = styled.div`
  position: absolute;
  background-color: ${props => props.theme.colors.surface};
  border: 1px solid ${props => props.theme.colors.border};
  border-radius: 6px;
  padding: 10px;
  font-size: 12px;
  pointer-events: none;
  z-index: 100;
  max-width: 300px;
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
`;

const NetworkGraph: React.FC<NetworkGraphProps> = ({
  connections,
  onNodeSelect,
  selectedProcess,
  theme
}) => {
  const svgRef = useRef<SVGSVGElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const [tooltip, setTooltip] = useState<{ visible: boolean; x: number; y: number; content?: string }>({
    visible: false,
    x: 0,
    y: 0
  });

  // Graph state
  const simulationRef = useRef<d3.Simulation<GraphNode, GraphLink>>();
  const nodesRef = useRef<GraphNode[]>([]);
  const linksRef = useRef<GraphLink[]>([]);

  // Convert connections to graph data
  const processData = useCallback(() => {
    const processMap = new Map<string, GraphNode>();
    const linkArray: GraphLink[] = [];

    // Group connections by process
    connections.forEach(connection => {
      const processId = `pid_${connection.pid}`;

      if (!processMap.has(processId)) {
        processMap.set(processId, {
          id: processId,
          pid: connection.pid,
          processName: connection.processName,
          cmdline: connection.cmdlineFull,
          username: connection.username,
          exePath: connection.exePath,
          threatScore: connection.threatScore,
          isSuspicious: connection.isSuspicious,
          connectionCount: 0,
          lastSeen: connection.timestamp
        });
      }

      // Update process node
      const node = processMap.get(processId)!;
      node.connectionCount++;
      node.lastSeen = Math.max(node.lastSeen, connection.timestamp);
      node.threatScore = Math.max(node.threatScore, connection.threatScore);
      node.isSuspicious = node.isSuspicious || connection.isSuspicious;

      // Create link to destination IP
      const destId = `ip_${connection.dstIp}`;

      if (!processMap.has(destId)) {
        processMap.set(destId, {
          id: destId,
          pid: -1, // IP nodes don't have PIDs
          processName: connection.dstIp,
          cmdline: '',
          username: '',
          exePath: '',
          threatScore: connection.threatScore,
          isSuspicious: connection.isSuspicious,
          connectionCount: 0,
          lastSeen: connection.timestamp
        });
      }

      // Create link
      linkArray.push({
        source: processId,
        target: destId,
        connection: connection,
        value: 1
      });
    });

    return {
      nodes: Array.from(processMap.values()),
      links: linkArray
    };
  }, [connections]);

  // Get node color based on threat level
  const getNodeColor = useCallback((node: GraphNode) => {
    if (node.pid === -1) {
      // IP node
      return node.isSuspicious ? theme.colors.graph.node.suspicious : theme.colors.text.secondary;
    }

    if (node.threatScore >= 75) return theme.colors.graph.node.critical;
    if (node.threatScore >= 50) return theme.colors.graph.node.suspicious;
    if (node.threatScore >= 25) return theme.colors.graph.node.warning;
    return theme.colors.graph.node.safe;
  }, [theme]);

  // Get link color based on threat level
  const getLinkColor = useCallback((link: GraphLink) => {
    if (link.connection.threatScore >= 75) return theme.colors.graph.edge.critical;
    if (link.connection.threatScore >= 50) return theme.colors.graph.edge.suspicious;
    if (link.connection.threatScore >= 25) return theme.colors.graph.edge.warning;
    return theme.colors.graph.edge.safe;
  }, [theme]);

  // Initialize and update D3 visualization
  useEffect(() => {
    if (!svgRef.current || !containerRef.current) return;

    const svg = d3.select(svgRef.current);
    const container = d3.select(containerRef.current);

    // Clear previous visualization
    svg.selectAll('*').remove();

    // Set up dimensions
    const width = container.node()!.clientWidth;
    const height = container.node()!.clientHeight;

    svg.attr('width', width).attr('height', height);

    // Create zoom behavior
    const zoom = d3.zoom<SVGSVGElement, unknown>()
      .scaleExtent([0.1, 4])
      .on('zoom', (event) => {
        g.attr('transform', event.transform);
      });

    svg.call(zoom);

    // Create main group for zoom/pan
    const g = svg.append('g');

    // Process data
    const { nodes, links } = processData();
    nodesRef.current = nodes;
    linksRef.current = links;

    // Create simulation
    const simulation = d3.forceSimulation<GraphNode>(nodes)
      .force('link', d3.forceLink<GraphNode, GraphLink>(links)
        .id(d => d.id)
        .distance(100)
        .strength(0.5))
      .force('charge', d3.forceManyBody().strength(-300))
      .force('center', d3.forceCenter(width / 2, height / 2))
      .force('collision', d3.forceCollide().radius(30));

    simulationRef.current = simulation;

    // Create arrow markers for directed edges
    svg.append('defs').selectAll('marker')
      .data(['safe', 'warning', 'suspicious', 'critical'])
      .enter().append('marker')
      .attr('id', d => `arrow-${d}`)
      .attr('viewBox', '0 -5 10 10')
      .attr('refX', 20)
      .attr('refY', 0)
      .attr('markerWidth', 6)
      .attr('markerHeight', 6)
      .attr('orient', 'auto')
      .append('path')
      .attr('d', 'M0,-5L10,0L0,5')
      .attr('fill', d => {
        switch (d) {
          case 'critical': return theme.colors.graph.edge.critical;
          case 'suspicious': return theme.colors.graph.edge.suspicious;
          case 'warning': return theme.colors.graph.edge.warning;
          default: return theme.colors.graph.edge.safe;
        }
      });

    // Create links
    const link = g.append('g')
      .attr('class', 'links')
      .selectAll('line')
      .data(links)
      .enter().append('line')
      .attr('stroke', d => getLinkColor(d))
      .attr('stroke-width', d => Math.max(1, d.connection.threatScore / 25))
      .attr('stroke-opacity', d => d.connection.isSuspicious ? 0.8 : 0.6)
      .attr('marker-end', d => {
        if (d.connection.threatScore >= 75) return 'url(#arrow-critical)';
        if (d.connection.threatScore >= 50) return 'url(#arrow-suspicious)';
        if (d.connection.threatScore >= 25) return 'url(#arrow-warning)';
        return 'url(#arrow-safe)';
      });

    // Create nodes
    const node = g.append('g')
      .attr('class', 'nodes')
      .selectAll('g')
      .data(nodes)
      .enter().append('g')
      .attr('class', 'node')
      .style('cursor', 'pointer')
      .call(d3.drag<SVGGElement, GraphNode>()
        .on('start', dragstarted)
        .on('drag', dragged)
        .on('end', dragended) as any);

    // Add circles for nodes
    node.append('circle')
      .attr('r', d => {
        const baseRadius = d.pid === -1 ? 8 : 12; // IP nodes are smaller
        return baseRadius + Math.min(d.connectionCount * 2, 20);
      })
      .attr('fill', d => getNodeColor(d))
      .attr('stroke', '#fff')
      .attr('stroke-width', 2)
      .attr('stroke-opacity', d => selectedProcess?.id === d.id ? 1 : 0.3);

    // Add glow effect for suspicious nodes
    node.append('circle')
      .attr('r', d => {
        const baseRadius = d.pid === -1 ? 8 : 12;
        return baseRadius + Math.min(d.connectionCount * 2, 20) + 5;
      })
      .attr('fill', 'none')
      .attr('stroke', d => getNodeColor(d))
      .attr('stroke-width', 2)
      .attr('stroke-opacity', 0)
      .classed('pulse', d => d.isSuspicious);

    // Add labels
    node.append('text')
      .text(d => d.pid === -1 ? d.processName : d.processName.length > 10 ? d.processName.substring(0, 10) + '...' : d.processName)
      .attr('x', 0)
      .attr('y', d => d.pid === -1 ? -15 : -20)
      .attr('text-anchor', 'middle')
      .attr('font-size', '11px')
      .attr('font-weight', '600')
      .attr('fill', theme.colors.text.secondary)
      .style('pointer-events', 'none');

    // Add event handlers
    node
      .on('mouseover', handleMouseOver)
      .on('mouseout', handleMouseOut)
      .on('click', handleClick);

    // Update positions on simulation tick
    simulation.on('tick', () => {
      link
        .attr('x1', d => (d.source as GraphNode).x!)
        .attr('y1', d => (d.source as GraphNode).y!)
        .attr('x2', d => (d.target as GraphNode).x!)
        .attr('y2', d => (d.target as GraphNode).y!);

      node.attr('transform', d => `translate(${d.x},${d.y})`);
    });

    // Drag functions
    function dragstarted(event: d3.D3DragEvent<SVGGElement, GraphNode, GraphNode>, d: GraphNode) {
      if (!event.active) simulation.alphaTarget(0.3).restart();
      d.fx = d.x;
      d.fy = d.y;
    }

    function dragged(event: d3.D3DragEvent<SVGGElement, GraphNode, GraphNode>, d: GraphNode) {
      d.fx = event.x;
      d.fy = event.y;
    }

    function dragended(event: d3.D3DragEvent<SVGGElement, GraphNode, GraphNode>, d: GraphNode) {
      if (!event.active) simulation.alphaTarget(0);
      d.fx = null;
      d.fy = null;
    }

    // Mouse event handlers
    function handleMouseOver(event: MouseEvent, d: GraphNode) {
      const content = `
        <div><strong>${d.processName}</strong></div>
        ${d.pid !== -1 ? `<div>PID: ${d.pid}</div>` : ''}
        <div>Connections: ${d.connectionCount}</div>
        ${d.username ? `<div>User: ${d.username}</div>` : ''}
        <div>Threat Score: ${d.threatScore}</div>
        <div>Status: ${d.isSuspicious ? '🚨 Suspicious' : '✅ Safe'}</div>
      `;

      setTooltip({
        visible: true,
        x: event.pageX + 10,
        y: event.pageY - 10,
        content
      });

      // Highlight connected nodes
      highlightConnections(d.id, true);
    }

    function handleMouseOut() {
      setTooltip({ visible: false, x: 0, y: 0 });
      highlightConnections(null, false);
    }

    function handleClick(event: MouseEvent, d: GraphNode) {
      if (d.pid !== -1) { // Only process nodes are clickable
        onNodeSelect(d);
      }
    }

    function highlightConnections(nodeId: string | null, highlight: boolean) {
      link.style('opacity', l => {
        if (!highlight) return 0.6;
        const link = l as GraphLink;
        return (link.source as GraphNode).id === nodeId || (link.target as GraphNode).id === nodeId ? 1 : 0.2;
      });
    }

    return () => {
      simulation.stop();
    };

  }, [connections, selectedProcess, processData, getNodeColor, getLinkColor, theme, onNodeSelect]);

  // Add CSS animation for pulsing suspicious nodes
  useEffect(() => {
    const style = document.createElement('style');
    style.textContent = `
      .pulse {
        animation: pulse-red 2s infinite;
      }
      @keyframes pulse-red {
        0%, 100% {
          stroke-opacity: 0.8;
          r: 20;
        }
        50% {
          stroke-opacity: 0.3;
          r: 25;
        }
      }
    `;
    document.head.appendChild(style);

    return () => {
      document.head.removeChild(style);
    };
  }, []);

  return (
    <GraphContainer ref={containerRef}>
      <GraphSvg ref={svgRef} />

      <Controls>
        <ControlButton onClick={() => {
          // Reset zoom
          if (svgRef.current) {
            const svg = d3.select(svgRef.current);
            svg.transition().duration(750).call(
              d3.zoom().transform as any,
              d3.zoomIdentity
            );
          }
        }}>
          🔄 Reset View
        </ControlButton>

        <ControlButton onClick={() => {
          // Recenter layout
          if (simulationRef.current && containerRef.current) {
            const width = containerRef.current.clientWidth;
            const height = containerRef.current.clientHeight;
            simulationRef.current.force('center', d3.forceCenter(width / 2, height / 2));
            simulationRef.current.alpha(0.3).restart();
          }
        }}>
          🎯 Re-center
        </ControlButton>
      </Controls>

      {tooltip.visible && (
        <Tooltip
          style={{
            left: tooltip.x,
            top: tooltip.y,
            display: tooltip.visible ? 'block' : 'none'
          }}
          dangerouslySetInnerHTML={{ __html: tooltip.content || '' }}
        />
      )}
    </GraphContainer>
  );
};

export default NetworkGraph;