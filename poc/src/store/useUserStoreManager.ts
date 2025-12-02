import { defineStore } from 'pinia';
import { ref } from 'vue';
import {
  encodeFunctionData,
  decodeAbiParameters,
  keccak256,
  encodePacked,
  namehash,
  zeroAddress,
  zeroHash,
  type Address,
  type Hash,
  isAddress,
} from 'viem';
import { useNetworkStore } from './useNetworkStore';
import { useTransactionStore } from './useTransactionStore';
import { useAbiStore } from './useAbiStore';
import { isValidSubstrateAddress, normalizeDomainName } from '../utils';
import type { DotnsAvailability } from '@/type';
import { useResolverStore } from './useResolverStore';
import { useWalletStore } from './useWalletStore';

export const useUserStoreManager = defineStore('userStoreManager', () => {
  const userStore = ref<Address>(zeroAddress);
  const walletStore = useWalletStore();
  const networkStore = useNetworkStore();
  const transactionStore = useTransactionStore();
  const resolverStore = useResolverStore();
  const abiStore = useAbiStore();

  function encodeKey(walletAddress: Address, value: string): Hash {
    return keccak256(encodePacked(['address', 'string'], [walletAddress, value]));
  }

  async function getUserStore(accountAddress: Address): Promise<Address> {
    try {
      networkStore.ensureClient();
      await abiStore.ensureAbis();
      const network = networkStore.currentNetwork;
      if (!network?.storeFactory) {
        throw new Error('Store factory not configured');
      }

      const client = await networkStore.getClient();

      const data = encodeFunctionData({
        abi: abiStore.getABI('StoreFactory'),
        functionName: 'getDeployedStore',
        args: [accountAddress],
      });
      const result = await transactionStore.ethCall(
        client,
        accountAddress,
        network.storeFactory,
        data
      );

      if (result === zeroAddress || result === '0x') {
        userStore.value = zeroAddress;
        return zeroAddress;
      }

      const decoded = decodeAbiParameters([{ type: 'address' }], result);
      const store = decoded[0];

      userStore.value = store ? (store as Address) : zeroAddress;
      return userStore.value;
    } catch (error) {
      console.error('[UserStoreManager:getUserStore]', error);
      userStore.value = zeroAddress;
      return zeroAddress;
    }
  }

  async function deployStore(): Promise<Hash> {
    try {
      const network = networkStore.currentNetwork;
      await abiStore.ensureAbis();
      if (!network?.storeFactory) {
        throw new Error('Store factory not configured');
      }

      const existing = await getUserStore(walletStore.address!);
      if (existing !== zeroAddress) {
        return zeroHash;
      }

      const client = await networkStore.getClient();

      const data = encodeFunctionData({
        abi: abiStore.getABI('StoreFactory'),
        functionName: 'deploy',
        args: [],
      });

      const hash = await transactionStore.ethTransact(
        client,
        walletStore.getInjected(),
        walletStore.address!,
        {
          to: network.storeFactory,
          data,
        }
      );

      await getUserStore(walletStore.address!);
      return hash;
    } catch (error) {
      console.error('[UserStoreManager:deployStore]', error);
      throw error;
    }
  }

  async function storeSubdomain(
    domain: string,
    ownerAddress: Address,
    injected: any,
    accountAddress: Address
  ): Promise<Hash> {
    try {
      const current = await getUserStore(ownerAddress);
      if (current === zeroAddress) {
        throw new Error('User store not deployed');
      }

      const client = await networkStore.getClient();

      const key = encodeKey(ownerAddress, domain);
      const data = encodeFunctionData({
        abi: abiStore.getABI('Store'),
        functionName: 'setValue',
        args: [key, `${domain}.dot`],
      });

      return await transactionStore.ethTransact(client, injected, accountAddress, {
        to: current,
        data,
      });
    } catch (error) {
      console.error('[UserStoreManager:storeSubdomain]', error);
      throw error;
    }
  }

  async function getSubdomains(): Promise<string[]> {
    try {
      networkStore.ensureClient();
      const current = await getUserStore(walletStore.address!);
      if (current === zeroAddress) {
        return [];
      }

      const client = await networkStore.getClient();

      const data = encodeFunctionData({
        abi: abiStore.getABI('Store'),
        functionName: 'getValues',
        args: [],
      });

      const result = await transactionStore.ethCall(client, walletStore.address!, current, data);

      const decoded = decodeAbiParameters([{ type: 'string[]' }], result);
      const subdomains = decoded[0];

      return subdomains ? [...new Set(subdomains as string[])] : [];
    } catch (error) {
      console.error('[UserStoreManager:getSubdomains]', error);
      return [];
    }
  }

  async function getSubdomainsForAddress(targetAddress: Address): Promise<string[]> {
    try {
      networkStore.ensureClient();
      const network = networkStore.currentNetwork;
      if (!network?.storeFactory) {
        throw new Error('Store factory not configured');
      }

      const client = await networkStore.getClient();

      const storeCheckData = encodeFunctionData({
        abi: abiStore.getABI('StoreFactory'),
        functionName: 'getDeployedStore',
        args: [targetAddress],
      });

      const storeResult = await transactionStore.ethCall(
        client,
        walletStore.address!,
        network.storeFactory,
        storeCheckData
      );

      const storeDecoded = decodeAbiParameters([{ type: 'address' }], storeResult);
      const store = storeDecoded[0];

      if (!store || (store as Address) === zeroAddress) {
        return [];
      }

      const subData = encodeFunctionData({
        abi: abiStore.getABI('Store'),
        functionName: 'getValues',
        args: [],
      });

      const result = await transactionStore.ethCall(
        client,
        walletStore.address!,
        store as Address,
        subData
      );

      const decoded = decodeAbiParameters([{ type: 'string[]' }], result);
      const subdomains = decoded[0];

      return subdomains ? [...new Set(subdomains as string[])] : [];
    } catch (error) {
      console.error('[UserStoreManager:getSubdomainsForAddress]', error);
      return [];
    }
  }

  async function registerSubdomain(parentName: string, subdomain: string): Promise<Hash> {
    try {
      const network = networkStore.currentNetwork;
      await abiStore.ensureAbis();
      if (!network?.ensRegistry || !network?.publicResolver) {
        throw new Error('ENS registry or public resolver not configured');
      }

      const client = await networkStore.getClient();

      parentName = normalizeDomainName(parentName);
      const parentNode = namehash(`${parentName}.dot`);
      const label = keccak256(encodePacked(['string'], [subdomain]));

      const data = encodeFunctionData({
        abi: abiStore.getABI('ENSRegistry'),
        functionName: 'setSubnodeRecord',
        args: [parentNode, label, walletStore.address!, network.publicResolver, 0n],
      });

      const hash = await transactionStore.ethTransact(
        client,
        walletStore.getInjected(),
        walletStore.address!,
        {
          to: network.ensRegistry,
          data,
        }
      );

      await storeSubdomain(
        `${subdomain}.${parentName}`,
        walletStore.address!,
        walletStore.getInjected(),
        walletStore.address!
      );

      return hash;
    } catch (error) {
      console.error('[UserStoreManager:registerSubdomain]', error);
      throw error;
    }
  }

  async function getUser(name: string): Promise<Address> {
    try {
      networkStore.ensureClient();
      await abiStore.ensureAbis();
      const network = networkStore.currentNetwork;
      if (!network?.ensRegistry) {
        throw new Error('ENS registry not configured');
      }

      const client = await networkStore.getClient();

      name = normalizeDomainName(name);
      const node = name.includes('.dot') ? namehash(name) : namehash(`${name}.dot`);

      const data = encodeFunctionData({
        abi: abiStore.getABI('ENSRegistry'),
        functionName: 'owner',
        args: [node],
      });

      const result = await transactionStore.ethCall(
        client,
        walletStore.address!,
        network.ensRegistry,
        data
      );

      const decoded = decodeAbiParameters([{ type: 'address' }], result);
      const owner = decoded[0];

      return owner ? (owner as Address) : zeroAddress;
    } catch (error) {
      console.error('[UserStoreManager:getUser]', error);
      return zeroAddress;
    }
  }

  async function checkHandleAvailability(name: string | Address): Promise<DotnsAvailability> {
    try {
      const network = networkStore.currentNetwork;
      await abiStore.ensureAbis();
      if (!network?.ensRegistry) {
        throw new Error('ENS registry not configured');
      }
      let originalName = name;
      const lowerCase = name.toLowerCase();
      name = normalizeDomainName(lowerCase);
      originalName = normalizeDomainName(originalName);
      if (isValidSubstrateAddress(originalName)) {
        name = await walletStore.convertToEVM(originalName);
        const resolvedName = await resolverStore.resolveAddressToName(name as Address);
        return {
          available: !resolvedName,
          owner: name as Address,
          name: resolvedName ? normalizeDomainName(resolvedName) : null,
        };
      } else if (!isAddress(name)) {
        const node = namehash(`${name}.dot`);
        const data = encodeFunctionData({
          abi: abiStore.getABI('ENSRegistry'),
          functionName: 'owner',
          args: [node],
        });
        const client = await networkStore.getClient();

        const result = await transactionStore.ethCall(
          client,
          zeroAddress,
          network.ensRegistry,
          data
        );
        const decoded = decodeAbiParameters([{ type: 'address' }], result);
        const owner = decoded[0];

        return {
          owner: owner,
          available: (owner as Address) === zeroAddress,
          name: name,
        };
      } else {
        const resolvedName = await resolverStore.resolveAddressToName(name);
        return {
          available: !resolvedName,
          owner: name,
          name: resolvedName ? normalizeDomainName(resolvedName) : null,
        };
      }
    } catch (error) {
      console.error('[UserStoreManager:checkHandleAvailability]', error);

      throw error;
    }
  }

  return {
    userStore,
    encodeKey,
    getUserStore,
    deployStore,
    storeSubdomain,
    getSubdomains,
    getSubdomainsForAddress,
    registerSubdomain,
    getUser,
    checkHandleAvailability,
  };
});
