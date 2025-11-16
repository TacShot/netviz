// gui/src/electron.d.ts
export interface IElectronAPI {
  platform: string;
  getAppVersion: () => Promise<string>;
  getAppName: () => Promise<string>;
}

declare global {
  interface Window {
    electronAPI: IElectronAPI;
  }
}
