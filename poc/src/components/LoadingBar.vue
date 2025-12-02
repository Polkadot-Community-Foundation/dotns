<template>
  <div v-if="transactionStatus === 'idle'" class="progress-container" v-show="isLoading">
    <div class="progress-bar"></div>
  </div>
</template>

<script setup>
import { storeToRefs } from 'pinia';
import { useWalletStore } from '../store/useWalletStore';

const walletStore = useWalletStore();
const { isLoading, transactionStatus } = storeToRefs(walletStore);
</script>
<style scoped>
.progress-container {
  position: fixed;
  top: 0;
  left: 0;
  width: 100%;
  height: 4px;
  z-index: 999999;
  overflow: hidden;
}

.progress-bar {
  width: 100%;
  height: 200%;
  background: #e6007a;
  background-size: 200% 100%;
  animation: loading 2s infinite linear;
}

@keyframes loading {
  0% {
    transform: translateX(-100%);
  }

  100% {
    transform: translateX(100%);
  }
}
</style>
