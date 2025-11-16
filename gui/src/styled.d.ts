import 'styled-components';

declare module 'styled-components' {
  export interface DefaultTheme {
    name: string;
    colors: {
      background: string;
      surface: string;
      border: string;
      text: {
        primary: string;
        secondary: string;
        muted: string;
      };
      graph: {
        background: string;
        node: {
          safe: string;
          warning: string;
          suspicious: string;
          critical: string;
        };
        edge: {
          safe: string;
          warning: string;
          suspicious: string;
          critical: string;
        };
      };
      status: {
        online: string;
        offline: string;
        warning: string;
      };
    };
  }
}

// Augment the Window interface for Electron API
declare global {
  interface Window {
    electronAPI?: {
      platform: string;
      // Add other Electron API properties here if needed
    };
  }
}