<template>
  <button
    @click="toggleWallet"
    :disabled="isLoading"
    class="relative px-5 py-2.5 rounded-lg font-medium text-sm transition-all duration-200 font-sans shadow-sm"
    :class="[
      wallet.isConnected
        ? 'bg-[#E6007A] hover:bg-[#d1006f] text-white'
        : 'bg-[#E6007A] hover:bg-[#d1006f] text-white',
      isLoading && 'opacity-60 cursor-not-allowed',
    ]"
  >
    <span v-if="isLoading" class="flex items-center gap-2">
      <svg
        class="animate-spin h-4 w-4 text-white"
        xmlns="http://www.w3.org/2000/svg"
        fill="none"
        viewBox="0 0 24 24"
      >
        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
        <path
          class="opacity-75"
          fill="currentColor"
          d="M4 12a8 8 0 018-8V0C5.373 0 
             0 5.373 0 12h4zm2 5.291A7.962 7.962 
             0 014 12H0c0 3.042 1.135 5.824 
             3 7.938l3-2.647z"
        />
      </svg>
      Connecting...
    </span>

    <span v-else-if="wallet.isConnected" class="flex items-center gap-2">
      <span class="w-2.5 h-2.5 rounded-full animate-pulse" style="background-color: #4caf50"></span>
      {{ truncatedAddress }}
    </span>

    <span v-else>Connect Wallet</span>
  </button>
</template>

<script setup lang="ts">
import { ref, computed } from 'vue';
import { useWalletStore } from '@/store/useWalletStore';
import { useToast } from 'vue-toastification';

const wallet = useWalletStore();
const toast = useToast();
const isLoading = ref(false);

const truncatedAddress = computed(() => {
  const addr = wallet.address;
  if (addr) {
    return `${addr.slice(0, 6)}...${addr.slice(-4)}`;
  }
  return '';
});

async function toggleWallet() {
  if (wallet.isConnected) {
    disconnect();
  } else {
    await connect();
  }
}

async function connect() {
  try {
    isLoading.value = true;

    if (!wallet.isConnected) {
      await wallet.init();

      if (wallet.isConnected) {
        toast.success('Wallet connected successfully');
      } else {
        toast.warning('No EVM compatible wallet is installed');
      }
    }
  } catch (err: any) {
    console.error('Wallet connection failed:', err);

    const errorMessage = getErrorMessage(err);
    toast.error(errorMessage);
  } finally {
    isLoading.value = false;
  }
}

function disconnect() {
  wallet.$patch({
    isConnected: false,
  });
  toast.info('Wallet disconnected');
}

function getErrorMessage(error: any): string {
  if (error?.message?.includes('No wallet provider detected')) {
    return 'No wallet detected. Please install MetaMask or another Web3 wallet';
  }

  if (error?.code === 4001) {
    return 'Connection request rejected';
  }

  if (error?.code === -32002) {
    return 'Connection request already pending. Check your wallet';
  }

  if (error?.message?.includes('User rejected')) {
    return 'Connection cancelled';
  }

  if (error?.message?.includes('network')) {
    return 'Network connection failed. Please try again';
  }

  return error?.message || 'Failed to connect wallet';
}
</script>
