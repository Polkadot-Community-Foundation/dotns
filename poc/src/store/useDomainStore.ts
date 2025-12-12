import { defineStore } from 'pinia';
import {
  encodeFunctionData,
  decodeAbiParameters,
  keccak256,
  toBytes,
  formatEther,
  hexToBigInt,
  zeroHash,
  type Address,
  type Hash,
  zeroAddress,
} from 'viem';
import { useNetworkStore } from './useNetworkStore';
import { useTransactionStore } from './useTransactionStore';
import { useAbiStore } from './useAbiStore';
import { useUserStoreManager } from './useUserStoreManager';
import { normalizeDomainName, toFixed, getSecondsForUnit, PopStatus } from '../utils';
import type { Commitment, Registration, TransactionResult } from '@/type';
import { useWalletStore } from './useWalletStore';

export const useDomainStore = defineStore('useDomainStore', () => {
  const networkStore = useNetworkStore();
  const transactionStore = useTransactionStore();
  const abiStore = useAbiStore();
  const userStoreManager = useUserStoreManager();
  const walletStore = useWalletStore();

  function isDomainTLD(domain: string): boolean {
    const parts = domain.replace('.dot', '').split('.');
    return parts.length === 1;
  }

  function extractLabel(domain: string): string {
    return domain.replace('.dot', '').split('.')[0] ?? '';
  }

  function calculateTokenId(label: string): bigint {
    const labelHash = keccak256(toBytes(label));
    return hexToBigInt(labelHash);
  }

  async function makeCommitment(
    name: string,
    owner: Address,
    duration: bigint
  ): Promise<Commitment> {
    try {
      networkStore.ensureClient();
      await abiStore.ensureAbis();
      const network = networkStore.currentNetwork;

      if (!network?.publicResolver || !network?.registrarController) {
        throw new Error('Network not properly configured');
      }

      const client = await networkStore.getClient();

      name = normalizeDomainName(name);
      const secretBytes = crypto.getRandomValues(new Uint8Array(32));
      const secret = `0x${Array.from(secretBytes)
        .map(b => b.toString(16).padStart(2, '0'))
        .join('')}` as Hash;

      const registration: Registration = {
        label: name,
        owner,
        duration,
        secret,
        resolver: network.publicResolver,
        data: [],
        reverseRecord: true,
        referrer: keccak256('0x0'),
      };

      const data = encodeFunctionData({
        abi: abiStore.getABI('ETHRegistrarController'),
        functionName: 'makeCommitment',
        args: [registration],
      });

      const result = await transactionStore.ethCall(
        client,
        walletStore.address!,
        network.registrarController,
        data
      );

      const decoded = decodeAbiParameters([{ type: 'bytes32' }], result);
      const commitment = decoded[0];
      if (!commitment) {
        throw new Error('Failed to decode commitment');
      }

      return { commitment: commitment as Hash, registration };
    } catch (error) {
      console.error('[DomainStore:makeCommitment]', error);
      throw error;
    }
  }

  async function commitRegistration(commitment: string): Promise<Hash> {
    try {
      const network = networkStore.currentNetwork;
      await abiStore.ensureAbis();
      if (!network?.registrarController) {
        throw new Error('Registrar controller not configured');
      }

      const client = await networkStore.getClient();

      const data = encodeFunctionData({
        abi: abiStore.getABI('ETHRegistrarController'),
        functionName: 'commit',
        args: [commitment],
      });
      return await transactionStore.ethTransact(
        client,
        walletStore.getInjected(),
        walletStore.address!,
        {
          to: network.registrarController,
          data,
        }
      );
    } catch (error) {
      console.error('[DomainStore:commitRegistration]', error);
      throw error;
    }
  }

  async function fetchRegistrationCost(
    label: string,
    duration: bigint,
    formatted: boolean = true
  ): Promise<string | bigint> {
    try {
      networkStore.ensureClient();
      await abiStore.ensureAbis();
      const network = networkStore.currentNetwork;

      if (!network?.registrarController) {
        throw new Error('Registrar controller not configured');
      }

      const client = await networkStore.getClient();

      const data = encodeFunctionData({
        abi: abiStore.getABI('ETHRegistrarController'),
        functionName: 'rentPrice',
        args: [label, duration],
      });

      const result = await transactionStore.ethCall(
        client,
        walletStore.address!,
        network.registrarController,
        data,
        0n,
        true,
        network.ethRPCURL
      );

      const decoded = decodeAbiParameters(
        [
          {
            type: 'tuple',
            components: [
              { name: 'base', type: 'uint256' },
              { name: 'premium', type: 'uint256' },
            ],
          },
        ],
        result
      );
      const contractCost = decoded[0];
      if (!contractCost) throw new Error('Failed to decode registration cost');

      const cost = BigInt(contractCost.base) + BigInt(contractCost.premium);

      if (formatted) {
        return `${toFixed(formatEther(cost), 12)} ${network.nativeCurrency.symbol}`;
      }

      return cost;
    } catch (error) {
      console.error('[DomainStore:fetchRegistrationCost]', error);
      if (formatted && networkStore.currentNetwork) {
        return `0.00 ${networkStore.currentNetwork.nativeCurrency.symbol}`;
      }
      return 0n;
    }
  }
  async function classifyName(label: string): Promise<string> {
    try {
      networkStore.ensureClient();
      await abiStore.ensureAbis();
      const network = networkStore.currentNetwork;

      if (!network?.StableOracle) {
        throw new Error('Registrar controller not configured');
      }

      const client = await networkStore.getClient();

      const data = encodeFunctionData({
        abi: abiStore.getABI('StableOracle'),
        functionName: 'classifyName',
        args: [label],
      });

      const result = await transactionStore.ethCall(
        client,
        walletStore.address!,
        network?.StableOracle,
        data,
        0n,
        true,
        network.ethRPCURL
      );

      const decoded = decodeAbiParameters(
        [
          {
            type: 'tuple',
            components: [
              { name: 'requirement', type: 'uint256' },
              { name: 'message', type: 'string' },
            ],
          },
        ],
        result
      );
      const classification = decoded[0];

      return classification.message;
    } catch (error) {
      console.error('[DomainStore:classifyName]', error);
      return 'Available to all';
    }
  }
  async function getNamePopStatus(label: string): Promise<PopStatus> {
    try {
      networkStore.ensureClient();
      await abiStore.ensureAbis();
      const network = networkStore.currentNetwork;

      if (!network?.StableOracle) {
        throw new Error('Registrar controller not configured');
      }

      const client = await networkStore.getClient();

      const data = encodeFunctionData({
        abi: abiStore.getABI('StableOracle'),
        functionName: 'getNamePopStatus',
        args: [label],
      });

      const result = await transactionStore.ethCall(
        client,
        walletStore.address!,
        network?.StableOracle,
        data,
        0n,
        true,
        network.ethRPCURL
      );

      const decoded = decodeAbiParameters(
        [
          {
            type: 'enum',
            components: [
              { name: 'requirement', type: 'uint256' },
              { name: 'message', type: 'string' },
            ],
          },
        ],
        result
      );

      const status = decoded[0] as PopStatus;

      return status;
    } catch (error) {
      console.error('[DomainStore:getNamePopStatus]', error);
      return PopStatus.NoStatus;
    }
  }

  async function isAvailable(domain: string, accountAddress: Address): Promise<boolean> {
    try {
      networkStore.ensureClient();
      await abiStore.ensureAbis();
      const network = networkStore.currentNetwork;
      if (!network?.baseRegistrar) {
        throw new Error('Base registrar not configured');
      }

      const client = await networkStore.getClient();

      const label = extractLabel(domain);
      const tokenId = calculateTokenId(label);

      const data = encodeFunctionData({
        abi: abiStore.getABI('BaseRegistrar'),
        functionName: 'available',
        args: [tokenId],
      });

      const result = await transactionStore.ethCall(
        client,
        accountAddress,
        network.baseRegistrar,
        data
      );

      const decoded = decodeAbiParameters([{ type: 'bool' }], result);
      return (decoded[0] as boolean) ?? false;
    } catch (error) {
      console.error('[DomainStore:isAvailable]', error);
      throw error;
    }
  }

  async function nameExpires(domain: string): Promise<bigint> {
    try {
      networkStore.ensureClient();
      await abiStore.ensureAbis();
      const network = networkStore.currentNetwork;
      if (!network?.baseRegistrar) {
        throw new Error('Base registrar not configured');
      }

      const client = await networkStore.getClient();

      const label = extractLabel(domain);
      const tokenId = calculateTokenId(label);

      const data = encodeFunctionData({
        abi: abiStore.getABI('BaseRegistrar'),
        functionName: 'nameExpires',
        args: [tokenId],
      });

      const result = await transactionStore.ethCall(
        client,
        walletStore.address!,
        network.baseRegistrar,
        data
      );

      const decoded = decodeAbiParameters([{ type: 'uint256' }], result);
      return (decoded[0] as bigint) ?? 0n;
    } catch (error) {
      console.error('[DomainStore:nameExpires]', error);
      throw error;
    }
  }

  async function renewDomain(name: string, duration: bigint): Promise<TransactionResult> {
    try {
      const network = networkStore.currentNetwork;
      await abiStore.ensureAbis();
      if (!network?.registrarController) {
        throw new Error('Registrar controller not configured');
      }

      const client = await networkStore.getClient();
      name = normalizeDomainName(name);
      if (!isDomainTLD(name)) {
        throw new Error('Cannot renew subdomains');
      }

      const label = extractLabel(name);
      const cost = (await fetchRegistrationCost(label, duration, false)) as bigint;

      const data = encodeFunctionData({
        abi: abiStore.getABI('ETHRegistrarController'),
        functionName: 'renew',
        args: [label, duration, zeroHash],
      });

      const hash = await transactionStore.ethTransact(
        client,
        walletStore.getInjected(),
        walletStore.address!,
        {
          to: network.registrarController,
          data,
          value: cost,
        }
      );

      return { hash, status: hash !== zeroHash };
    } catch (error) {
      console.error('[DomainStore:renewDomain]', error);
      throw error;
    }
  }

  async function finalizeRegistration(registration: Registration): Promise<TransactionResult> {
    try {
      const network = networkStore.currentNetwork;
      await abiStore.ensureAbis();
      if (!network?.registrarController) {
        throw new Error('Registrar controller not configured');
      }

      const client = await networkStore.getClient();

      const totalCost = (await fetchRegistrationCost(
        registration.label,
        registration.duration,
        false
      )) as bigint;

      registration = {
        ...registration,
        reverseRecord: true,
      };

      const data = encodeFunctionData({
        abi: abiStore.getABI('ETHRegistrarController'),
        functionName: 'register',
        args: [registration],
      });

      const hash = await transactionStore.ethTransact(
        client,
        walletStore.getInjected(),
        walletStore.address!,
        {
          to: network.registrarController,
          data,
          value: totalCost,
        }
      );

      if (hash === zeroHash) {
        return { hash, status: false };
      }

      if (userStoreManager.userStore === zeroAddress) {
        await userStoreManager.deployStore();
      }

      if (userStoreManager.userStore !== zeroAddress) {
        await userStoreManager.storeSubdomain(
          registration.label,
          walletStore.address!,
          walletStore.getInjected(),
          walletStore.address!
        );
      }

      return { hash, status: true };
    } catch (error) {
      console.error('[DomainStore:finalizeRegistration]', error);
      throw error;
    }
  }

  async function getMinCommitmentAge(): Promise<bigint> {
    try {
      networkStore.ensureClient();
      await abiStore.ensureAbis();
      const network = networkStore.currentNetwork;
      if (!network?.registrarController) {
        throw new Error('Registrar controller not configured');
      }

      const client = await networkStore.getClient();

      const data = encodeFunctionData({
        abi: abiStore.getABI('ETHRegistrarController'),
        functionName: 'minCommitmentAge',
        args: [],
      });

      const result = await transactionStore.ethCall(
        client,
        walletStore.address!,
        network.registrarController,
        data
      );

      const decoded = decodeAbiParameters([{ type: 'uint256' }], result);
      const minWait = decoded[0];

      return minWait ? (minWait as bigint) : 60n;
    } catch (error) {
      console.error('[DomainStore:getMinCommitmentAge]', error);
      return 60n;
    }
  }

  async function getGracePeriod(): Promise<bigint> {
    try {
      networkStore.ensureClient();
      await abiStore.ensureAbis();
      const network = networkStore.currentNetwork;
      if (!network?.baseRegistrar) {
        throw new Error('Base registrar not configured');
      }

      const client = await networkStore.getClient();

      const data = encodeFunctionData({
        abi: abiStore.getABI('BaseRegistrar'),
        functionName: 'GRACE_PERIOD',
        args: [],
      });

      const result = await transactionStore.ethCall(
        client,
        walletStore.address!,
        network.baseRegistrar,
        data
      );

      const decoded = decodeAbiParameters([{ type: 'uint256' }], result);
      const gracePeriod = decoded[0];

      return gracePeriod ? (gracePeriod as bigint) : BigInt(getSecondsForUnit('minutes') * 5n);
    } catch (error) {
      console.error('[DomainStore:getGracePeriod]', error);
      return BigInt(getSecondsForUnit('minutes') * 5n);
    }
  }

  async function reclaimDomain(name: string): Promise<TransactionResult> {
    try {
      const network = networkStore.currentNetwork;
      await abiStore.ensureAbis();
      if (!network?.baseRegistrar) {
        throw new Error('Base registrar not configured');
      }

      const client = await networkStore.getClient();

      name = normalizeDomainName(name);
      const label = extractLabel(name);
      const tokenId = calculateTokenId(label);

      const data = encodeFunctionData({
        abi: abiStore.getABI('BaseRegistrar'),
        functionName: 'reclaim',
        args: [tokenId, walletStore.address!],
      });

      const hash = await transactionStore.ethTransact(
        client,
        walletStore.getInjected(),
        walletStore.address!,
        {
          to: network.baseRegistrar,
          data,
        }
      );

      return { hash, status: true };
    } catch (error) {
      console.error('[DomainStore:reclaimDomain]', error);
      throw error;
    }
  }

  async function batchRenewDomains(names: string[], duration: bigint): Promise<Hash> {
    try {
      const network = networkStore.currentNetwork;
      await abiStore.ensureAbis();
      if (!network?.bulkRenewal) {
        throw new Error('Bulk renewal not configured');
      }

      const client = await networkStore.getClient();

      const tldNames = names.filter(name => isDomainTLD(name));

      if (tldNames.length === 0) {
        throw new Error('No valid TLDs to renew');
      }

      const labels = tldNames.map(name => extractLabel(name));
      const costs = await Promise.all(
        labels.map(label => fetchRegistrationCost(label, duration, false) as Promise<bigint>)
      );
      const totalCost = costs.reduce((acc, curr) => acc + curr, 0n);

      const data = encodeFunctionData({
        abi: abiStore.getABI('StaticBulkRenewal'),
        functionName: 'renewAll',
        args: [labels, duration, zeroHash],
      });

      return await transactionStore.ethTransact(
        client,
        walletStore.getInjected(),
        walletStore.address!,
        {
          to: network.bulkRenewal,
          data,
          value: totalCost,
        }
      );
    } catch (error) {
      console.error('[DomainStore:batchRenewDomains]', error);
      throw error;
    }
  }

  return {
    isDomainTLD,
    extractLabel,
    calculateTokenId,
    makeCommitment,
    commitRegistration,
    fetchRegistrationCost,
    isAvailable,
    nameExpires,
    renewDomain,
    finalizeRegistration,
    getMinCommitmentAge,
    getGracePeriod,
    reclaimDomain,
    batchRenewDomains,
    classifyName,
    getNamePopStatus,
  };
});
