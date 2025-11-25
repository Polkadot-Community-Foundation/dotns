import { defineStore } from 'pinia';
import {
  createWalletClient,
  custom,
  defineChain,
  keccak256,
  toHex,
  toBytes,
  zeroHash,
  namehash,
  type Address,
  zeroAddress,
  formatEther,
  encodePacked,
  type Hash,
  hexToBigInt,
  createPublicClient,
  http,
  type Call,
  encodeFunctionData,
  publicActions,
} from 'viem';
import { ref } from 'vue';
import {
  DEFAULT_NETWORK_ID,
  getFirstDeployedNetwork,
  getSecondsForUnit,
  normalizeDomainName,
  SUPPORTED_NETWORKS,
  toFixed,
} from '../utils';
import type {
  Commitment,
  Deployment,
  ENSPrice,
  NetworkConfig,
  Registration,
  ResolverStatus,
  TextRecord,
  TransactionResult,
} from '@/type';
import { Buffer } from 'buffer';
import { CID } from 'multiformats/cid';

export const useWalletStore = defineStore(
  'wallet',
  () => {
    const isConnected = ref(false);
    const address = ref<Address | null>(null);
    const userStore = ref<Address>(zeroAddress);
    const chainId = ref<number | null>(null);
    const currentNetwork = ref<(NetworkConfig & Partial<Deployment>) | null>(null);

    let publicClient: any = null;
    let client: any = null;
    let DummyOracleABI: any;
    let ETHRegistrarControllerABI: any;
    let ENSRegistryABI: any;
    let StaticBulkRenewalABI: any;
    let BASE_REGISTRAR_ABI: any;
    let STORE_FACTORY_ABI: any;
    let STORE_ABI: any;
    let PUBLIC_RESOLVER_ABI: any;
    let MULTI_CALL_ABI: any;

    function getEthereum(): any {
      if (window && !window.ethereum) {
        throw new Error(
          'No wallet provider detected. Please install MetaMask or another Web3 wallet.'
        );
      }
      return window.ethereum;
    }

    function ensurePublicClient(): void {
      if (!publicClient) {
        throw new Error('Public client not initialized');
      }
      if (!currentNetwork.value) {
        throw new Error('Network not configured');
      }
    }

    async function initPublicClient(network?: NetworkConfig & Partial<Deployment>): Promise<void> {
      const targetNetwork = network || getFirstDeployedNetwork();
      if (!targetNetwork) {
        throw new Error('No valid network found for initialization');
      }

      const rpcUrls = Array.isArray(targetNetwork.rpcUrls)
        ? targetNetwork.rpcUrls
        : [targetNetwork.rpcUrls];

      const chain = defineChain({
        id: targetNetwork.chainId,
        name: targetNetwork.chainName,
        nativeCurrency: targetNetwork.nativeCurrency,
        rpcUrls: {
          default: { http: rpcUrls },
          public: { http: rpcUrls },
        },
      });

      publicClient = createPublicClient({
        chain,
        transport: http(rpcUrls[0]),
      });

      if (!currentNetwork.value) {
        currentNetwork.value = targetNetwork;
        chainId.value = targetNetwork.chainId;
      }
    }
    async function loadABIs(): Promise<void> {
      if (
        ETHRegistrarControllerABI &&
        ENSRegistryABI &&
        StaticBulkRenewalABI &&
        BASE_REGISTRAR_ABI &&
        DummyOracleABI &&
        STORE_FACTORY_ABI &&
        STORE_ABI &&
        PUBLIC_RESOLVER_ABI &&
        MULTI_CALL_ABI
      ) {
        return;
      }

      const [
        ETHRegistrarController,
        ENSRegistry,
        StaticBulkRenewal,
        BaseRegistrarImplementation,
        DummyOracle,
        StoreFactory,
        Store,
        PublicResolver,
        MultiCall,
      ] = await Promise.all([
        import('../../abis/ETHRegistrarController.json'),
        import('../../abis/ENSRegistry.json'),
        import('../../abis/StaticBulkRenewal.json'),
        import('../../abis/BaseRegistrarImplementation.json'),
        import('../../abis/DummyOracle.json'),
        import('../../abis/StoreFactory.json'),
        import('../../abis/Store.json'),
        import('../../abis/PublicResolver.json'),
        import('../../abis/Multicall3.json'),
      ]);

      ETHRegistrarControllerABI = ETHRegistrarController.abi;
      ENSRegistryABI = ENSRegistry.abi;
      StaticBulkRenewalABI = StaticBulkRenewal.abi;
      BASE_REGISTRAR_ABI = BaseRegistrarImplementation.abi;
      DummyOracleABI = DummyOracle.abi;
      STORE_FACTORY_ABI = StoreFactory.abi;
      STORE_ABI = Store.abi;
      PUBLIC_RESOLVER_ABI = PublicResolver.abi;
      MULTI_CALL_ABI = MultiCall.abi;
    }

    async function init(): Promise<void> {
      try {
        setupEventListeners();
        await loadABIs();
        await initPublicClient();
        const eth = getEthereum();
        if (eth.autoRefreshOnNetworkChange) {
          eth.autoRefreshOnNetworkChange = false;
        }
        const connected = await connectWallet();
        if (connected !== zeroAddress) {
          isConnected.value = true;
        }
      } catch (error) {
        logError('init', error);
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

    async function testRpcConnection(rpcUrl: string, chainId: number): Promise<boolean> {
      try {
        const testClient = createPublicClient({
          transport: http(rpcUrl, { timeout: 5000 }),
        });
        const networkChainId = await testClient.getChainId();
        return networkChainId === chainId;
      } catch (error) {
        console.warn(`RPC connection test failed for ${rpcUrl}:`, error);
        return false;
      }
    }

    async function connectWallet(): Promise<Address> {
      try {
        const eth = getEthereum();

        const accounts = await eth.request({ method: 'eth_requestAccounts' });
        address.value = accounts[0] as Address;

        const chainIdHex = await eth.request({ method: 'eth_chainId' });
        chainId.value = parseInt(chainIdHex, 16);

        let network = SUPPORTED_NETWORKS[chainId.value!];

        if (!network || !hasValidContracts(network)) {
          const validNetwork = getFirstDeployedNetwork();
          if (!validNetwork) {
            throw new Error('No valid network with deployed contracts found');
          }

          const switched = await switchNetwork(validNetwork.chainId);
          if (!switched) {
            console.warn(
              'Failed to switch to valid network, attempting to continue with current network'
            );
            if (network) {
              currentNetwork.value = network;
            } else {
              throw new Error('Cannot connect: current network not supported and switch failed');
            }
          } else {
            network = validNetwork;
          }
        }

        currentNetwork.value = network;
        await initPublicClient(network);
        const rpcUrls = Array.isArray(network.rpcUrls) ? network.rpcUrls : [network.rpcUrls];
        const chain = defineChain({
          id: network.chainId,
          name: network.chainName,
          nativeCurrency: network.nativeCurrency,
          rpcUrls: {
            default: { http: rpcUrls },
            public: { http: rpcUrls },
          },
        });

        client = createWalletClient({
          chain,
          account: address.value,
          transport: custom(eth),
        }).extend(publicActions);

        await getUserStore();
        return address.value;
      } catch (error) {
        logError('connectWallet', error);
        currentNetwork.value = null;
        return zeroAddress;
      }
    }

    async function switchNetwork(targetChainId: number = DEFAULT_NETWORK_ID): Promise<boolean> {
      try {
        const eth = getEthereum();
        const network = SUPPORTED_NETWORKS[targetChainId];
        if (!network) {
          throw new Error(`Network with chainId ${targetChainId} not found in SUPPORTED_NETWORKS`);
        }
        const chainIdHex = `0x${targetChainId.toString(16)}`;
        await eth.request({
          method: 'wallet_switchEthereumChain',
          params: [{ chainId: chainIdHex }],
        });
        chainId.value = targetChainId;
        currentNetwork.value = network;
        return true;
      } catch (error: any) {
        logError('switchNetwork', error);
        if (error.code === 4902) {
          try {
            const added = await addNetwork(targetChainId);
            if (added) {
              return await switchNetwork(targetChainId);
            }
            return false;
          } catch (addError) {
            logError('switchNetwork:addNetwork', addError);
            return false;
          }
        }
        if (error.code === 4001) {
          console.warn('User rejected network switch');
          return false;
        }
        return false;
      }
    }

    async function addNetwork(targetChainId: number): Promise<boolean> {
      try {
        const eth = getEthereum();
        const network = SUPPORTED_NETWORKS[targetChainId];
        if (!network) {
          throw new Error(`Network with chainId ${targetChainId} not found in SUPPORTED_NETWORKS`);
        }

        const rpcUrls = Array.isArray(network.rpcUrls) ? network.rpcUrls : [network.rpcUrls];
        const blockExplorerUrls = network.blockExplorerUrls
          ? Array.isArray(network.blockExplorerUrls)
            ? network.blockExplorerUrls
            : [network.blockExplorerUrls]
          : undefined;

        console.log(`Testing RPC connection for chain ${targetChainId}...`);
        const rpcWorking = rpcUrls?.[0]
          ? await testRpcConnection(rpcUrls[0], targetChainId)
          : false;
        if (!rpcWorking) {
          throw new Error(
            `RPC endpoint ${rpcUrls[0]} is not responding or returns incorrect chain ID.`
          );
        }

        const chainIdHex = `0x${targetChainId.toString(16)}`;
        const params = {
          chainId: chainIdHex,
          chainName: network.chainName,
          nativeCurrency: {
            name: network.nativeCurrency.name,
            symbol: network.nativeCurrency.symbol,
            decimals: network.nativeCurrency.decimals,
          },
          rpcUrls,
          ...(blockExplorerUrls && { blockExplorerUrls }),
        };

        await eth.request({
          method: 'wallet_addEthereumChain',
          params: [params],
        });
        return true;
      } catch (error: any) {
        logError('addNetwork', error);
        if (error.code === -32603) {
          console.error(
            'Wallet internal error when adding network. Please add the network manually.'
          );
        }
        throw error;
      }
    }

    function logError(context: string, error: any): void {
      console.error(`[WalletStore:${context}]`, {
        message: error?.message || String(error),
        code: error?.code,
        data: error?.data,
        stack: error?.stack,
      });
    }

    function setupEventListeners(): void {
      try {
        if (!window) return;
        const eth = window.ethereum;
        if (eth) {
          eth.on('accountsChanged', handleAccountChange);
          eth.on('chainChanged', handleChainChange);
          eth.on('disconnect', handleDisconnect);
        }

        window.addEventListener('eip6963:announceProvider', (event: any) => {
          const provider = event.detail?.provider;
          if (provider && !window.ethereum) {
            window.ethereum = provider;
            const newEth = getEthereum();
            newEth.on('accountsChanged', handleAccountChange);
            newEth.on('chainChanged', handleChainChange);
            newEth.on('disconnect', handleDisconnect);
          }
        });

        window.dispatchEvent(new Event('eip6963:requestProvider'));
      } catch (error) {
        logError('setupEventListeners', error);
      }
    }

    async function handleAccountChange(accounts: string[]): Promise<void> {
      if (accounts.length > 0) {
        address.value = accounts[0] as Address;
        isConnected.value = true;
        await getUserStore();
      } else {
        address.value = zeroAddress;
        isConnected.value = false;
        currentNetwork.value = null;
        userStore.value = zeroAddress;
      }
    }

    async function handleChainChange(newChainId: string): Promise<void> {
      chainId.value = parseInt(newChainId, 16);
      await connectWallet();
    }

    function handleDisconnect(): void {
      isConnected.value = false;
      address.value = zeroAddress;
      chainId.value = null;
      currentNetwork.value = null;
      userStore.value = zeroAddress;
    }

    function ensureConnected(): void {
      if (!client) {
        throw new Error('Wallet client not initialized');
      }
      if (!isConnected.value) {
        throw new Error('Wallet not connected');
      }
      if (!currentNetwork.value) {
        throw new Error('Network not configured');
      }
    }

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
        ensurePublicClient();
        name = normalizeDomainName(name);
        const secretBytes = toHex(crypto.getRandomValues(new Uint8Array(32)));
        const registration: Registration = {
          label: name,
          owner,
          duration,
          secret: secretBytes,
          resolver: currentNetwork.value!.publicResolver!,
          data: [],
          reverseRecord: true,
          referrer: keccak256('0x0'),
        };

        await deployStore();
        const commitment = (await publicClient.readContract({
          address: currentNetwork.value!.registrarController!,
          abi: ETHRegistrarControllerABI,
          functionName: 'makeCommitment',
          args: [registration],
        })) as Hash;

        return { commitment, registration };
      } catch (error) {
        logError('makeCommitment', error);
        throw error;
      }
    }

    async function commitRegistration(commitment: string): Promise<Hash> {
      try {
        ensureConnected();
        const hash = (await client.writeContract({
          address: currentNetwork.value!.registrarController!,
          abi: ETHRegistrarControllerABI,
          functionName: 'commit',
          args: [commitment],
        })) as Hash;

        return hash;
      } catch (error) {
        logError('commitRegistration', error);
        throw error;
      }
    }

    async function getMinCommitmentAge(): Promise<bigint> {
      try {
        ensurePublicClient();
        const minWait = (await publicClient.readContract({
          address: currentNetwork.value!.registrarController!,
          abi: ETHRegistrarControllerABI,
          functionName: 'minCommitmentAge',
        })) as bigint;

        return minWait;
      } catch (error) {
        logError('getMinCommitmentAge', error);
        return 60n;
      }
    }

    async function fetchRegistrationCost(
      label: string,
      duration: bigint,
      formatted: boolean = true
    ): Promise<string | bigint> {
      try {
        ensurePublicClient();
        const contractCost = (await publicClient.readContract({
          address: currentNetwork.value!.registrarController!,
          abi: ETHRegistrarControllerABI,
          functionName: 'rentPrice',
          args: [label, duration],
        })) as ENSPrice;

        const cost = BigInt(contractCost.base.toString()) + BigInt(contractCost.premium.toString());

        if (formatted) {
          return `${toFixed(formatEther(cost), 12)} ${currentNetwork.value!.nativeCurrency.symbol}`;
        }

        return cost;
      } catch (error) {
        logError('fetchRegistrationCost', error);
        if (formatted) {
          return `0.00 ${currentNetwork.value?.nativeCurrency.symbol ?? 'ETH'}`;
        }
        return 0n;
      }
    }

    async function getGracePeriod(): Promise<bigint> {
      try {
        ensurePublicClient();
        const gracePeriod = await publicClient.readContract({
          address: currentNetwork.value!.baseRegistrar!,
          abi: BASE_REGISTRAR_ABI,
          functionName: 'GRACE_PERIOD',
          args: [],
        });
        return gracePeriod;
      } catch (error) {
        logError('getGracePeriod', error);
        return BigInt(getSecondsForUnit('minutes') * 5n);
      }
    }

    async function finalizeRegistration(registration: Registration): Promise<TransactionResult> {
      try {
        ensureConnected();
        const totalCost = (await fetchRegistrationCost(
          registration.label,
          registration.duration,
          false
        )) as bigint;

        registration = {
          ...registration,
          reverseRecord: true,
        };

        const estimatedGas = await client.estimateContractGas({
          address: currentNetwork.value!.registrarController!,
          abi: ETHRegistrarControllerABI,
          functionName: 'register',
          args: [registration],
          value: totalCost,
          account: address.value,
        });

        const gasWithBuffer = (estimatedGas * 130n) / 100n;

        const hash = (await client.writeContract({
          address: currentNetwork.value!.registrarController!,
          abi: ETHRegistrarControllerABI,
          functionName: 'register',
          args: [registration],
          value: totalCost,
          gas: gasWithBuffer,
        })) as Hash;

        const receipt = await client.waitForTransactionReceipt({ hash });
        const status = {
          hash: hash,
          status: receipt.status === 'success',
        };

        await storeSubdomain(registration.label);
        return status;
      } catch (error) {
        logError('finalizeRegistration', error);
        throw error;
      }
    }

    async function ensureUserStore() {
      if (userStore.value === zeroAddress) {
        userStore.value = await getUserStore();
      }
    }

    async function getSubdomains(): Promise<string[]> {
      try {
        ensureUserStore();
        ensurePublicClient();
        const subdomains = (await client.readContract({
          address: userStore.value,
          abi: STORE_ABI,
          functionName: 'getValues',
          args: [],
        })) as string[];
        return [...new Set(subdomains)];
      } catch (error) {
        logError('getSubdomains', error);
        return [];
      }
    }

    async function registerSubdomain(parentName: string, subdomain: string): Promise<Hash> {
      try {
        ensureConnected();
        parentName = normalizeDomainName(parentName);
        const parentNode = namehash(`${parentName}.dot`);
        const label = keccak256(toBytes(subdomain));

        const hash = (await client.writeContract({
          address: currentNetwork.value!.ensRegistry!,
          abi: ENSRegistryABI,
          functionName: 'setSubnodeRecord',
          args: [parentNode, label, address.value, currentNetwork.value!.publicResolver!, 0n],
        })) as Hash;

        const receipt = await client.waitForTransactionReceipt({ hash });

        if (receipt.status !== 'success') {
          return zeroHash;
        }

        await storeSubdomain(`${subdomain}.${parentName}`);

        return hash;
      } catch (error) {
        logError('registerSubdomain', error);
        throw error;
      }
    }

    async function renewDomain(name: string, duration: bigint): Promise<TransactionResult> {
      try {
        ensureConnected();
        name = normalizeDomainName(name);
        if (!isDomainTLD(name)) {
          throw new Error('Cannot renew subdomains. Subdomains are tied to their parent domain.');
        }

        const label = extractLabel(name);
        const cost = (await fetchRegistrationCost(label, duration, false)) as bigint;

        const hash = (await client.writeContract({
          address: currentNetwork.value!.registrarController!,
          abi: ETHRegistrarControllerABI,
          functionName: 'renew',
          args: [label, duration, zeroHash],
          value: cost,
        })) as Hash;

        const receipt = await client.waitForTransactionReceipt({ hash });

        return {
          hash: hash,
          status: receipt.status === 'success',
        };
      } catch (error) {
        logError('renewDomain', error);
        throw error;
      }
    }

    async function batchRenewDomains(names: string[], duration: bigint): Promise<Hash> {
      try {
        ensureConnected();

        const tldNames = names.filter(name => isDomainTLD(name));

        if (tldNames.length === 0) {
          throw new Error('No valid TLDs to renew. Subdomains cannot be renewed.');
        }

        if (tldNames.length < names.length) {
          console.warn('Filtered out subdomains. Only TLDs can be renewed.');
        }

        const labels = tldNames.map(name => extractLabel(name));
        const costs = await Promise.all(
          labels.map(label => fetchRegistrationCost(label, duration, false) as Promise<bigint>)
        );
        const totalCost = costs.reduce((accumulator, current) => accumulator + current, 0n);

        const hash = (await client.writeContract({
          address: currentNetwork.value!.bulkRenewal!,
          abi: StaticBulkRenewalABI,
          functionName: 'renewAll',
          args: [labels, duration, zeroHash],
          value: totalCost,
        })) as Hash;

        return hash;
      } catch (error) {
        logError('batchRenewDomains', error);
        throw error;
      }
    }

    async function isAvailable(domain: string): Promise<boolean> {
      try {
        ensurePublicClient();
        const label = extractLabel(domain);
        const tokenId = calculateTokenId(label);
        const available = (await publicClient.readContract({
          address: currentNetwork.value!.baseRegistrar!,
          abi: BASE_REGISTRAR_ABI,
          functionName: 'available',
          args: [tokenId],
        })) as boolean;

        return available;
      } catch (error) {
        logError('isAvailable', error);
        throw error;
      }
    }

    async function nameExpires(domain: string): Promise<bigint> {
      try {
        ensurePublicClient();
        const label = extractLabel(domain);
        const tokenId = calculateTokenId(label);
        const expires = (await publicClient.readContract({
          address: currentNetwork.value!.baseRegistrar!,
          abi: BASE_REGISTRAR_ABI,
          functionName: 'nameExpires',
          args: [tokenId],
        })) as bigint;
        return expires;
      } catch (error) {
        logError('nameExpires', error);
        throw error;
      }
    }

    function encodeKey(walletAddress: Address, value: string): Hash {
      return keccak256(encodePacked(['address', 'string'], [walletAddress, value]));
    }

    async function storeSubdomain(domain: string): Promise<Hash> {
      try {
        ensureConnected();
        userStore.value = await getUserStore();
        if (userStore.value === zeroAddress) {
          throw new Error('User store not deployed');
        }

        const key = encodeKey(address.value!, domain);
        const hash = (await client.writeContract({
          address: userStore.value,
          abi: STORE_ABI,
          functionName: 'setValue',
          args: [key, `${domain}.dot`],
        })) as Hash;

        await client.waitForTransactionReceipt({ hash });

        return hash;
      } catch (error) {
        logError('storeSubdomain', error);
        throw error;
      }
    }

    async function getUserStore(): Promise<Address> {
      try {
        ensurePublicClient();
        const store = (await publicClient.readContract({
          address: currentNetwork.value!.storeFactory!,
          abi: STORE_FACTORY_ABI,
          functionName: 'getDeployedStore',
          args: [address.value],
        })) as Address;

        userStore.value = store;

        return store;
      } catch (error) {
        logError('getUserStore', error);
        userStore.value = zeroAddress;
        return zeroAddress;
      }
    }

    async function deployStore(): Promise<Hash> {
      try {
        ensureConnected();
        const store = await getUserStore();
        if (store !== zeroAddress) {
          return zeroHash;
        }
        const hash = (await client.writeContract({
          address: currentNetwork.value!.storeFactory!,
          abi: STORE_FACTORY_ABI,
          functionName: 'deploy',
          args: [],
        })) as Hash;

        const receipt = await client.waitForTransactionReceipt({ hash });

        if (receipt.status === 'success') {
          await getUserStore();
        }

        return hash;
      } catch (error) {
        logError('deployStore', error);
        throw error;
      }
    }
    async function getUser(name: string): Promise<Address> {
      try {
        ensurePublicClient();
        name = normalizeDomainName(name);
        const node = name.includes('.dot') ? namehash(name) : namehash(`${name}.dot`);
        const owner = (await publicClient.readContract({
          address: currentNetwork.value!.ensRegistry!,
          abi: ENSRegistryABI,
          functionName: 'owner',
          args: [node],
        })) as Address;
        return owner;
      } catch (error) {
        logError('getUser', error);
        return zeroAddress;
      }
    }
    async function checkHandleAvailability(name: string): Promise<boolean> {
      try {
        ensurePublicClient();
        name = normalizeDomainName(name);
        const node = namehash(`${name}.dot`);

        const owner = (await publicClient.readContract({
          address: currentNetwork.value!.ensRegistry!,
          abi: ENSRegistryABI,
          functionName: 'owner',
          args: [node],
        })) as Address;
        return owner === zeroAddress;
      } catch (error) {
        logError('checkHandleAvailability', error);
        throw error;
      }
    }

    async function handleTaken(name: string): Promise<boolean> {
      try {
        ensurePublicClient();
        name = normalizeDomainName(name);
        const node = namehash(`${name}.dot`);

        const taken = (await publicClient.readContract({
          address: currentNetwork.value!.ensRegistry!,
          abi: ENSRegistryABI,
          functionName: 'recordExists',
          args: [node],
        })) as boolean;
        return taken;
      } catch (error) {
        logError('handleTaken', error);
        throw error;
      }
    }

    async function getText(name: string, key: string): Promise<string | null> {
      try {
        ensurePublicClient();
        name = normalizeDomainName(name);
        const node = namehash(`${name}.dot`);

        const value = await publicClient.readContract({
          address: currentNetwork.value!.publicResolver!,
          abi: PUBLIC_RESOLVER_ABI,
          functionName: 'text',
          args: [node, key],
        });
        if (!value || value === '' || value === 'true' || value === 'false') {
          return null;
        }

        return value;
      } catch (error) {
        logError('getText', error);
        return null;
      }
    }

    async function setText(name: string, key: string, value: string): Promise<void> {
      try {
        ensureConnected();
        name = normalizeDomainName(name);
        const node = namehash(`${name}.dot`);

        await client.writeContract({
          address: currentNetwork.value!.publicResolver!,
          abi: PUBLIC_RESOLVER_ABI,
          functionName: 'setText',
          args: [node, key, value],
        });
      } catch (error) {
        logError('setText', error);
        throw error;
      }
    }
    async function setProfileRecordsMulticall(
      name: string,
      records: TextRecord[]
    ): Promise<TransactionResult> {
      try {
        ensureConnected();
        name = normalizeDomainName(name);
        const node = namehash(`${name}.dot`);
        const entries = records.filter(r => r.value && r.value.length > 0);
        if (entries.length === 0) return { status: false, hash: zeroHash };

        const approved = (await publicClient.readContract({
          address: currentNetwork.value!.publicResolver!,
          abi: PUBLIC_RESOLVER_ABI,
          functionName: 'isApprovedForAll',
          args: [address.value, currentNetwork.value!.multicall!],
        })) as boolean;

        if (!approved) {
          const approveTx = (await client.writeContract({
            address: currentNetwork.value!.publicResolver!,
            abi: PUBLIC_RESOLVER_ABI,
            functionName: 'setApprovalForAll',
            args: [currentNetwork.value!.multicall!, true],
          })) as Hash;

          const approveReceipt = await client.waitForTransactionReceipt({ hash: approveTx });

          if (approveReceipt.status !== 'success') {
            return { hash: approveTx, status: false };
          }
        }

        const calls = entries.map(r => ({
          target: currentNetwork.value!.publicResolver!,
          callData: encodeFunctionData({
            abi: PUBLIC_RESOLVER_ABI,
            functionName: 'setText',
            args: [node, r.key, r.value],
          }),
        }));

        const multicallTx = (await client.writeContract({
          address: currentNetwork.value!.multicall!,
          abi: MULTI_CALL_ABI,
          functionName: 'aggregate',
          args: [calls],
        })) as Hash;

        const multicallReceipt = await client.waitForTransactionReceipt({ hash: multicallTx });

        const revokeTx = (await client.writeContract({
          address: currentNetwork.value!.publicResolver!,
          abi: PUBLIC_RESOLVER_ABI,
          functionName: 'setApprovalForAll',
          args: [currentNetwork.value!.multicall!, false],
        })) as Hash;

        await client.waitForTransactionReceipt({ hash: revokeTx });

        return {
          hash: multicallTx,
          status: multicallReceipt.status === 'success',
        };
      } catch (error) {
        logError('setProfileRecordsMulticall', error);
        return { status: false, hash: zeroHash };
      }
    }

    async function multicall(calls: Call[]): Promise<TransactionResult> {
      try {
        ensureConnected();
        const hash = await publicClient.readContract({
          address: currentNetwork.value!.multicall!,
          abi: MULTI_CALL_ABI,
          functionName: 'aggregate',
          args: [calls],
        });
        const receipt = await client.waitForTransactionReceipt({ hash });
        const status = {
          hash: hash,
          status: receipt.status === 'success',
        };
        return status;
      } catch (error) {
        logError('multicall', error);
        return {
          status: false,
          hash: zeroHash,
        };
      }
    }

    async function getSubdomainsForAddress(targetAddress: Address): Promise<string[]> {
      try {
        ensurePublicClient();
        const store = await publicClient.readContract({
          address: currentNetwork.value!.storeFactory!,
          abi: STORE_FACTORY_ABI,
          functionName: 'getDeployedStore',
          args: [targetAddress],
        });
        if (store === zeroAddress) {
          return [];
        }
        const subdomains: string[] = (await publicClient.readContract({
          address: store,
          abi: STORE_ABI,
          account: targetAddress,
          functionName: 'getValues',
          args: [],
        })) as string[];

        return [...new Set(subdomains)];
      } catch (error) {
        logError('getSubdomainsForAddress', error);
        return [];
      }
    }

    async function setContentHash(name: string, ipfsHash: string): Promise<TransactionResult> {
      try {
        ensureConnected();
        name = normalizeDomainName(name);
        const node = namehash(`${name}.dot`);

        const cid = CID.parse(ipfsHash);
        const contentHash: `0x${string}` = `0xe301${Buffer.from(cid.multihash.bytes).toString('hex')}`;

        const hash = await client.writeContract({
          address: currentNetwork.value!.publicResolver!,
          abi: PUBLIC_RESOLVER_ABI,
          functionName: 'setContenthash',
          args: [node, contentHash],
        });

        const receipt = await client.waitForTransactionReceipt({ hash });
        return { hash, status: receipt.status === 'success' };
      } catch (error) {
        logError('setContentHash', error);
        throw error;
      }
    }

    async function setResolverForName(name: string): Promise<TransactionResult> {
      try {
        ensureConnected();
        name = normalizeDomainName(name);
        name = normalizeDomainName(name);
        const node = namehash(`${name}.dot`);

        const hash = await client.writeContract({
          address: currentNetwork.value!.ensRegistry!,
          abi: ENSRegistryABI,
          functionName: 'setResolver',
          args: [node, currentNetwork.value!.publicResolver!],
        });

        const receipt = await client.waitForTransactionReceipt({ hash });
        return { hash, status: receipt.status === 'success' };
      } catch (error) {
        logError('setResolverForName', error);
        throw error;
      }
    }

    async function checkDomainSetup(name: string): Promise<ResolverStatus> {
      try {
        ensurePublicClient();
        name = normalizeDomainName(name);
        name = normalizeDomainName(name);
        const node = namehash(`${name}.dot`);

        const registryOwner = (await publicClient.readContract({
          address: currentNetwork.value!.ensRegistry!,
          abi: ENSRegistryABI,
          functionName: 'owner',
          args: [node],
        })) as Address;

        if (
          registryOwner === zeroAddress ||
          registryOwner === currentNetwork.value!.baseRegistrar!
        ) {
          return { needsReclaim: true, needsResolver: true, fixed: true };
        }

        const resolver = (await publicClient.readContract({
          address: currentNetwork.value!.ensRegistry!,
          abi: ENSRegistryABI,
          functionName: 'resolver',
          args: [node],
        })) as Address;

        return {
          needsReclaim: false,
          needsResolver: resolver === zeroAddress,
          fixed: true,
        };
      } catch (error) {
        logError('checkDomainSetup', error);
        throw error;
      }
    }

    async function reclaimDomain(name: string): Promise<TransactionResult> {
      try {
        ensureConnected();
        name = normalizeDomainName(name);
        const label = extractLabel(name);
        const tokenId = calculateTokenId(label);

        const hash = (await client.writeContract({
          address: currentNetwork.value!.baseRegistrar!,
          abi: BASE_REGISTRAR_ABI,
          functionName: 'reclaim',
          args: [tokenId, address.value],
        })) as Hash;

        const receipt = await client.waitForTransactionReceipt({ hash });
        return {
          hash,
          status: receipt.status === 'success',
        };
      } catch (error) {
        logError('reclaimDomain', error);
        throw error;
      }
    }
    return {
      reclaimDomain,
      setResolverForName,
      checkDomainSetup,
      setContentHash,
      multicall,
      setProfileRecordsMulticall,
      setText,
      getText,
      init,
      handleTaken,
      isConnected,
      address,
      chainId,
      currentNetwork,
      userStore,
      makeCommitment,
      commitRegistration,
      getMinCommitmentAge,
      fetchRegistrationCost,
      finalizeRegistration,
      registerSubdomain,
      getSubdomains,
      renewDomain,
      batchRenewDomains,
      isAvailable,
      nameExpires,
      checkHandleAvailability,
      switchNetwork,
      addNetwork,
      getUserStore,
      deployStore,
      getGracePeriod,
      getUser,
      getSubdomainsForAddress,
    };
  },
  { persist: { storage: sessionStorage } }
);
