import { defineStore } from 'pinia';
import { ref } from 'vue';
import { DEFAULT_NETWORK_ID, getFirstDeployedNetwork, SUPPORTED_NETWORKS } from '../utils';
import type { NetworkConfig, Deployment } from '@/type';
import { zeroAddress } from 'viem';
import { ClientWrapper, type IClientWrapper } from '@/composables';
import { useTypeClientAPI } from '@/composables/useTypedAPI';

export const useNetworkStore = defineStore('useNetworkStore', () => {
  const chainId = ref<number | null>(null);
  const currentNetwork = ref<(NetworkConfig & Partial<Deployment>) | null>(null);
  const client = ref<IClientWrapper | null>(null);
  const rawClient = ref<IClientWrapper | null>(null);

  async function createIfMissing() {
    if (!rawClient.value) {
      const selectedNetwork = currentNetwork.value || getFirstDeployedNetwork();
      if (!selectedNetwork) {
        throw new Error('No valid network found for initialisation');
      }
      const typedApi = await useTypeClientAPI(selectedNetwork.rpcUrls);
      rawClient.value = new ClientWrapper(typedApi);
    }
  }

  function hasValidContracts(network: NetworkConfig & Partial<Deployment>): boolean {
    return !!(
      network.storeFactory &&
      network.storeFactory !== zeroAddress &&
      network.ensRegistry &&
      network.ensRegistry !== zeroAddress &&
      network.registrarController &&
      network.registrarController !== zeroAddress &&
      network.baseRegistrar &&
      network.baseRegistrar !== zeroAddress &&
      network.multicall !== zeroAddress
    );
  }

  async function initClient(network?: NetworkConfig & Partial<Deployment>): Promise<void> {
    try {
      const targetNetwork = network || getFirstDeployedNetwork();
      if (!targetNetwork) {
        throw new Error('No valid network found for initialisation');
      }

      console.time('init client');
      const typedApi = await useTypeClientAPI(targetNetwork.rpcUrls);
      client.value = new ClientWrapper(typedApi);
      console.timeEnd('init client');

      if (!currentNetwork.value) {
        currentNetwork.value = targetNetwork;
        chainId.value = targetNetwork.chainId;
      }
    } catch (error) {
      console.error('[NetworkStore:initClient]', error);
      throw error;
    }
  }

  async function switchNetwork(targetChainId: number = DEFAULT_NETWORK_ID): Promise<boolean> {
    try {
      const targetNetwork = SUPPORTED_NETWORKS[targetChainId];
      if (!targetNetwork) {
        throw new Error(`Network with chainId ${targetChainId} not found`);
      }

      chainId.value = targetChainId;
      currentNetwork.value = targetNetwork;
      await initClient(targetNetwork);

      return true;
    } catch (error) {
      console.error('[NetworkStore:switchNetwork]', error);
      return false;
    }
  }

  async function getClient(): Promise<IClientWrapper> {
    await createIfMissing();
    return rawClient.value as IClientWrapper;
  }

  function ensureClient(): void {
    if (!client.value) {
      throw new Error('Client not initialised - call initClient first');
    }
    if (!currentNetwork.value) {
      throw new Error('Network not configured');
    }
  }

  return {
    chainId,
    currentNetwork,
    hasValidContracts,
    initClient,
    switchNetwork,
    getClient,
    ensureClient,
  };
});
