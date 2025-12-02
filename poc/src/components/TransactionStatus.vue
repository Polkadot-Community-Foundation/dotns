<template>
  <Teleport to="body">
    <Transition
      enter-active-class="transition-opacity duration-300"
      enter-from-class="opacity-0"
      leave-active-class="transition-opacity duration-300"
      leave-to-class="opacity-0"
    >
      <div
        v-if="open"
        class="fixed inset-0 bg-black/40 backdrop-blur-sm flex items-center justify-center z-50"
        @click.self="$emit('close')"
      >
        <Transition
          enter-active-class="transform transition duration-300 ease-out"
          enter-from-class="scale-95 opacity-0 translate-y-4"
          enter-to-class="scale-100 opacity-100 translate-y-0"
          leave-active-class="transform transition duration-200 ease-in"
          leave-from-class="scale-100 opacity-100 translate-y-0"
          leave-to-class="scale-95 opacity-0 translate-y-4"
        >
          <div
            v-if="open"
            class="bg-white rounded-2xl shadow-2xl w-full max-w-md p-10 text-center relative"
          >
            <button
              class="absolute top-5 right-5 text-gray-400 hover:text-gray-600 transition-colors"
              @click="$emit('close')"
              aria-label="Close transaction status"
            >
              <svg
                class="w-5 h-5"
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
                stroke-width="2"
              >
                <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>

            <template v-if="transaction && status === 'pending'">
              <div class="relative w-20 h-20 mx-auto mb-8">
                <svg class="w-full h-full" viewBox="0 0 100 100">
                  <defs>
                    <linearGradient id="loader-gradient" x1="0%" y1="0%" x2="100%" y2="100%">
                      <stop offset="0%" stop-color="#E6007A" />
                      <stop offset="100%" stop-color="#FF73B9" />
                    </linearGradient>
                  </defs>
                  <circle
                    class="text-gray-200"
                    stroke="currentColor"
                    stroke-width="10"
                    fill="none"
                    cx="50"
                    cy="50"
                    r="40"
                  />
                  <circle
                    class="animate-loader-ring"
                    stroke="url(#loader-gradient)"
                    stroke-width="10"
                    stroke-linecap="round"
                    fill="none"
                    cx="50"
                    cy="50"
                    r="40"
                  />
                </svg>
              </div>

              <h2 class="text-2xl font-semibold text-gray-900 mb-2">Submitting Transaction</h2>
              <p class="text-gray-500 text-sm mb-4">
                Your transaction is being finalized. Please wait...
              </p>

              <div v-if="elapsed > 15" class="text-sm text-gray-600">
                It looks like this is taking longer than usual. Please be patient
                <a
                  v-if="explorerUrl"
                  :href="explorerUrl"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="text-[#E6007A] font-medium hover:underline ml-1"
                >
                  View on Explorer
                </a>
              </div>
            </template>

            <template v-else-if="transaction && status === 'success'">
              <div
                class="w-20 h-20 mx-auto mb-8 flex items-center justify-center bg-[#FCE5EF] rounded-full"
              >
                <svg
                  class="w-10 h-10 text-[#E6007A]"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="3"
                    d="M5 13l4 4L19 7"
                  />
                </svg>
              </div>

              <h2 class="text-2xl font-extrabold text-gray-900 mb-2">Congratulations!</h2>
              <p class="text-gray-600 text-sm mb-6">Transaction successful!</p>

              <div class="flex flex-col space-y-3">
                <button
                  class="w-full py-3 rounded-xl bg-[#E6007A] hover:bg-[#C00066] text-white font-medium transition"
                  @click="$emit('close')"
                >
                  Done
                </button>

                <a
                  v-if="explorerUrl"
                  :href="explorerUrl"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="w-full block py-3 rounded-xl bg-gray-900 text-white font-medium hover:bg-gray-800 transition"
                >
                  View Details
                </a>
              </div>
            </template>

            <template v-else-if="transaction && status === 'failed'">
              <div
                class="w-20 h-20 mx-auto mb-8 flex items-center justify-center bg-[#FCE5EF] rounded-full"
              >
                <svg
                  class="w-10 h-10 text-[#E6007A]"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="3"
                    d="M6 18L18 6M6 6l12 12"
                  />
                </svg>
              </div>

              <h2 class="text-2xl font-bold text-gray-900 mb-2">Transaction Failed or Timed Out</h2>
              <p class="text-gray-600 text-sm mb-6">
                Something went wrong during the transaction.<br />
                Please try again or check the block explorer.
              </p>

              <div class="flex flex-col space-y-3">
                <button
                  class="w-full py-3 rounded-xl bg-[#E6007A] hover:bg-[#C00066] text-white font-medium transition"
                  @click="$emit('close')"
                >
                  Close
                </button>

                <a
                  v-if="explorerUrl"
                  :href="explorerUrl"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="w-full block py-3 rounded-xl bg-gray-900 text-white font-medium hover:bg-gray-800 transition"
                >
                  View Details
                </a>
              </div>
            </template>
          </div>
        </Transition>
      </div>
    </Transition>
  </Teleport>
</template>

<script setup lang="ts">
import { zeroHash } from 'viem';
import type { TransactionResult, TransactionState } from '../type';
import { BLOCK_EXPLORER } from '../utils';
import { ref, watch, computed, onUnmounted, withDefaults } from 'vue';
import { useNetworkStore } from '@/store/useNetworkStore';

const props = withDefaults(
  defineProps<{
    open: boolean;
    handle: string;
    transaction?: TransactionResult | null;
  }>(),
  {
    transaction: null,
  }
);

const networkStore = useNetworkStore();
defineEmits<{ close: [] }>();

const status = ref<TransactionState>('pending');
const elapsed = ref(0);
let timer: number | null | NodeJS.Timeout = null;

const explorer = networkStore.currentNetwork?.blockExplorerUrls?.[0] || BLOCK_EXPLORER;

const explorerUrl = computed(() =>
  props.transaction?.hash && props.transaction?.hash !== zeroHash
    ? `${explorer}/extrinsic/${props.transaction.hash}`
    : ''
);

function startElapsedTimer() {
  if (timer) clearInterval(timer);
  elapsed.value = 0;
  timer = setInterval(() => elapsed.value++, 1000);
}

watch(
  () => props.transaction,
  newVal => {
    if (!newVal) {
      console.log('watch:props.transaction ', newVal);
      status.value = 'pending';
      return;
    }
    if (newVal.status === undefined || newVal.status === null) {
      status.value = 'pending';
      startElapsedTimer();
    } else if (newVal.status === true) {
      status.value = 'success';
      clearInterval(timer!);
    } else if (newVal.status === false) {
      status.value = 'failed';
      clearInterval(timer!);
    }
  },
  { deep: true, immediate: true }
);

watch(
  () => props.open,
  val => {
    if (val) startElapsedTimer();
    else if (timer) clearInterval(timer);
  }
);

onUnmounted(() => {
  if (timer) clearInterval(timer);
});
</script>

<style scoped>
@keyframes loader-rotate {
  0% {
    transform: rotate(0deg);
  }
  100% {
    transform: rotate(360deg);
  }
}

@keyframes loader-dash {
  0% {
    stroke-dasharray: 1, 260;
    stroke-dashoffset: 0;
  }
  50% {
    stroke-dasharray: 180, 260;
    stroke-dashoffset: -90;
  }
  100% {
    stroke-dasharray: 180, 260;
    stroke-dashoffset: -280;
  }
}

.animate-loader-ring {
  transform-origin: center;
  animation:
    loader-rotate 1.6s linear infinite,
    loader-dash 1.6s ease-in-out infinite;
}
</style>
