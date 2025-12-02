import type { Injected } from 'dedot/types';

export {};

declare global {
  export type InjectedWeb3Provider = {
    enable: (origin: string) => Promise<Injected>;
    connect?: () => Promise<void>;
  };
  interface EthereumProvider {
    request: (args: { method: string; params?: any[] }) => Promise<any>;
    on: (event: string, handler: (...args: any[]) => void) => void;
    removeListener?: (event: string, handler: (...args: any[]) => void) => void;
    autoRefreshOnNetworkChange?: boolean;
  }

  interface Window {
    ethereum?: EthereumProvider;
    talisman?: EthereumProvider;
    injectedWeb3?: Record<string, InjectedWeb3Provider>;
  }
}
