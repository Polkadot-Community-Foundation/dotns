import { defineStore } from 'pinia';
import { web3AccountsSubscribe, web3Enable, web3FromAddress } from '@polkadot/extension-dapp';
import type { InjectedAccountWithMeta } from '@polkadot/extension-inject/types';
import { ref } from 'vue';
import { zeroAddress, type Address } from 'viem';
import {
  getInjectedExtensions,
  connectInjectedExtension,
  type InjectedPolkadotAccount,
} from 'polkadot-api/pjs-signer';
import { useNetworkStore } from './useNetworkStore';
import { useTransactionStore } from './useTransactionStore';
import { useDomainStore } from './useDomainStore';
import { useResolverStore } from './useResolverStore';
import { useUserStoreManager } from './useUserStoreManager';
import type { TransactionStatus } from '@/type';
import { useAbiStore } from './useAbiStore';

export const useWalletStore = defineStore(
  'useWalletStore',
  () => {
    const isConnected = ref(false);
    const address = ref<Address | null>(null);
    const hasWalletExtension = ref(false);
    const isLoading = ref(false);
    const injected = ref<any>(null);
    const currentAccount = ref<InjectedAccountWithMeta | InjectedPolkadotAccount | null>(null);
    const transactionStatus = ref<TransactionStatus>('idle');

    const networkStore = useNetworkStore();
    const transactionStore = useTransactionStore();
    const abiStore = useAbiStore();
    const domainStore = useDomainStore();
    const resolverStore = useResolverStore();
    const userStoreManager = useUserStoreManager();

    function setIsLoading(status: boolean) {
      isLoading.value = status;
    }

    function setTransactionStatus(status: TransactionStatus) {
      transactionStatus.value = status;
    }

    async function init(): Promise<void> {
      try {
        isLoading.value = true;
        await abiStore.loadABIs();
        await networkStore.initClient();
        await listenForAccountChanges();
        const connected = await connectWallet();
        console.log('connected: ', connected);
        if (connected) {
          isConnected.value = true;
        }
      } catch (error) {
        console.error('[WalletStore:init]', error);
      } finally {
        isLoading.value = false;
      }
    }

    async function connectWallet(): Promise<boolean> {
      try {
        const papiExtensionNames = getInjectedExtensions();

        if (papiExtensionNames.length > 0) {
          const papiExtension = await connectInjectedExtension(papiExtensionNames[0]!);
          const papiAccounts = papiExtension.getAccounts();

          if (papiAccounts.length > 0 && papiAccounts[0]!.polkadotSigner) {
            const papiAccount = papiAccounts[0];
            currentAccount.value = papiAccount!;
            const clientInstance = await networkStore.getClient();
            address.value = await clientInstance.evmAddress(papiAccount!.address);
            injected.value = papiAccount!.polkadotSigner;
            hasWalletExtension.value = true;
            await userStoreManager.getUserStore(address.value);
            return true;
          }
        }

        const legacyExtensions = await web3Enable('dotNS');
        if (!legacyExtensions.length) {
          hasWalletExtension.value = false;
          return false;
        }

        hasWalletExtension.value = true;

        const legacyAccounts = await legacyExtensions[0]!.accounts.get();
        if (!legacyAccounts.length) {
          return false;
        }

        const legacyAccount = legacyAccounts[0]!;
        currentAccount.value = legacyAccount as InjectedAccountWithMeta;

        const injector = await web3FromAddress(legacyAccount.address);
        injected.value = injector.signer;

        const clientInstance = await networkStore.getClient();
        address.value = await clientInstance.evmAddress(legacyAccount.address);
        await userStoreManager.getUserStore(address.value);

        return true;
      } catch (error) {
        console.error('[WalletStore:connectWallet]', error);
        return false;
      }
    }

    async function listenForAccountChanges(): Promise<() => void> {
      try {
        const legacyExtensions = await web3Enable('dotNS');
        if (!legacyExtensions.length) {
          hasWalletExtension.value = false;
          return () => {};
        }

        hasWalletExtension.value = true;

        const unsubscribe = await web3AccountsSubscribe(async accounts => {
          await handleAccountChange(accounts);
        });

        return unsubscribe;
      } catch (error) {
        console.error('[WalletStore:listenForAccountChanges]', error);
        hasWalletExtension.value = false;
        return () => {};
      }
    }

    async function handleAccountChange(accounts: InjectedAccountWithMeta[]): Promise<void> {
      if (accounts.length === 0) {
        handleDisconnect();
        return;
      }

      const papiExtensionNames = getInjectedExtensions();
      if (papiExtensionNames.length > 0) {
        const papiExtension = await connectInjectedExtension(papiExtensionNames[0]!);
        const papiAccounts = papiExtension.getAccounts();

        const matchingPapiAccount = papiAccounts.find(
          account => account.address === accounts[0]!.address
        );

        if (matchingPapiAccount && matchingPapiAccount.polkadotSigner) {
          currentAccount.value = matchingPapiAccount;
          injected.value = matchingPapiAccount.polkadotSigner;

          const clientInstance = await networkStore.getClient();
          address.value = await clientInstance.evmAddress(matchingPapiAccount.address);
          await userStoreManager.getUserStore(address.value);
          isConnected.value = true;
          return;
        }
      }

      currentAccount.value = accounts[0]!;
      const injector = await web3FromAddress(accounts[0]!.address);
      injected.value = injector.signer;

      const legacyClient = await networkStore.getClient();
      address.value = await legacyClient.evmAddress(accounts[0]!.address);
      await userStoreManager.getUserStore(address.value);

      isConnected.value = true;
    }

    function handleDisconnect(): void {
      isConnected.value = false;
      address.value = zeroAddress;
      currentAccount.value = null;
      injected.value = null;
    }

    function ensureConnected(): void {
      if (!injected.value || !currentAccount.value) {
        throw new Error('Wallet not connected');
      }
      if (!isConnected.value) {
        throw new Error('Wallet not connected');
      }
    }

    function getInjected(): any {
      ensureConnected();
      return injected.value;
    }

    async function convertToEVM(substrateAddress: string): Promise<Address> {
      let defaultAddress = zeroAddress as Address;
      try {
        setIsLoading(true);
        defaultAddress = await (await networkStore.getClient()).evmAddress(substrateAddress);
        console.log('convertToEVM: ', defaultAddress);
      } catch (error) {
        console.error('[WalletStore:convertToEVM]', error);
      } finally {
        setIsLoading(false);
        return defaultAddress;
      }
    }

    return {
      isConnected,
      address,
      hasWalletExtension,
      init,
      connectWallet,
      handleDisconnect,
      ensureConnected,
      getInjected,
      networkStore,
      transactionStore,
      domainStore,
      resolverStore,
      userStoreManager,
      isLoading,
      setIsLoading,
      transactionStatus,
      setTransactionStatus,
      convertToEVM,
    };
  },
  { persist: { storage: sessionStorage } }
);
