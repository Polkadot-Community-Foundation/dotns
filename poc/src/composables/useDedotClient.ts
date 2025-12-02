import type { PaseoAssetHubApi } from '@dedot/chaintypes';
import { DedotClient, WsProvider } from 'dedot';

const DEFAULT_RPC_ENDPOINT = 'wss://asset-hub-paseo-rpc.n.dwellir.com';

let clientInstance: DedotClient<PaseoAssetHubApi> | null = null;
let currentEndpoint: string | null = null;

export const useDedotClient = async (
  rpcEndpoint: string = DEFAULT_RPC_ENDPOINT
): Promise<DedotClient<PaseoAssetHubApi>> => {
  if (clientInstance && currentEndpoint !== rpcEndpoint) {
    clientInstance = null;
    currentEndpoint = null;
  }

  if (!clientInstance) {
    const provider = new WsProvider(rpcEndpoint);
    clientInstance = await DedotClient.new<PaseoAssetHubApi>({ provider, cacheMetadata: true });
    currentEndpoint = rpcEndpoint;
  }

  return clientInstance;
};
