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
              :disabled="isFinalizing"
              aria-label="Close waiting modal"
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

            <h2 class="text-2xl font-bold text-gray-900 mb-3 mt-2">{{ localHandle }}</h2>
            <p class="text-gray-500 text-sm mb-10 leading-relaxed">
              Let’s make sure no one else is registering this handle during this confirmation
              period.
            </p>

            <div class="relative w-52 h-52 mx-auto mb-10">
              <svg class="absolute inset-0 w-full h-full -rotate-90">
                <circle
                  class="text-gray-200"
                  stroke="currentColor"
                  stroke-width="8"
                  fill="transparent"
                  r="96"
                  cx="104"
                  cy="104"
                />
                <circle
                  class="text-[#E6007A]"
                  stroke="currentColor"
                  stroke-width="8"
                  stroke-linecap="round"
                  fill="transparent"
                  :stroke-dasharray="circumference"
                  :stroke-dashoffset="strokeOffset"
                  cx="104"
                  cy="104"
                />
              </svg>

              <div class="absolute inset-0 flex flex-col items-center justify-center">
                <div class="text-5xl font-extrabold text-gray-900">{{ remaining }}</div>
                <div class="text-sm text-gray-500">seconds left</div>
              </div>
            </div>

            <div class="flex justify-center">
              <button
                class="w-20 h-10 rounded-full bg-[#E6007A] hover:bg-[#d1006f] text-white font-semibold text-lg flex items-center justify-center transition-colors"
                @click="cancelWaiting"
                :disabled="isFinalizing"
              >
                <span v-if="!isFinalizing" class="flex space-x-1">
                  <span
                    v-for="i in 3"
                    :key="i"
                    class="w-2 h-2 bg-white rounded-full opacity-70 animate-bounce-dot"
                    :style="{ animationDelay: `${(i - 1) * 0.25}s` }"
                  ></span>
                </span>
                <svg
                  v-else
                  class="animate-spin h-5 w-5 text-white"
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                >
                  <circle
                    class="opacity-25"
                    cx="12"
                    cy="12"
                    r="10"
                    stroke="currentColor"
                    stroke-width="4"
                  />
                  <path
                    class="opacity-75"
                    fill="currentColor"
                    d="M4 12a8 8 0 018-8V0C5.373 0 
                       0 5.373 0 12h4zm2 5.291A7.962 
                       7.962 0 014 12H0c0 3.042 
                       1.135 5.824 3 7.938l3-2.647z"
                  />
                </svg>
              </button>
            </div>
          </div>
        </Transition>
      </div>
    </Transition>
  </Teleport>
</template>

<script setup lang="ts">
import type { TransactionResult } from '../type';
import { zeroHash } from 'viem';
import { ref, onUnmounted, computed, watch } from 'vue';

const props = defineProps<{
  open: boolean;
  handle: string;
  duration: number;
  onComplete: () => Promise<any>;
}>();

const emit = defineEmits<{
  close: [];
  finalized: [TransactionResult];
}>();
const localHandle = ref('');
const remaining = ref(props.duration);
const isFinalizing = ref(false);
const circumference = 2 * Math.PI * 96;
const strokeOffset = computed(
  () => ((props.duration - remaining.value) / props.duration) * circumference
);

let timer: number | null = null;

function startCountdown() {
  if (timer) clearInterval(timer);
  remaining.value = props.duration;
  timer = window.setInterval(async () => {
    if (remaining.value > 0) {
      remaining.value--;
    } else {
      clearInterval(timer!);
      await autoFinalize();
    }
  }, 1000);
}

async function autoFinalize() {
  try {
    isFinalizing.value = true;
    const txHash = await props.onComplete();
    emit('finalized', txHash);
  } catch (err) {
    console.error('Auto-finalize failed:', err);
    emit('finalized', { status: false, hash: zeroHash });
  } finally {
    isFinalizing.value = false;
    emit('close');
  }
}

function cancelWaiting() {
  clearInterval(timer!);
  emit('close');
}

watch(
  () => props.open,
  val => {
    if (val) startCountdown();
    else if (timer) clearInterval(timer);
  }
);
watch(
  () => props.handle,
  handle => {
    localHandle.value = handle.includes('.dot') ? handle : `${handle}.dot`;
  }
);
onUnmounted(() => {
  if (timer) clearInterval(timer);
});
</script>

<style scoped>
svg circle {
  transition: stroke-dashoffset 1s cubic-bezier(0.4, 0, 0.2, 1);
}

@keyframes bounce-dot {
  0%,
  80%,
  100% {
    transform: scale(0.7);
    opacity: 0.4;
  }

  40% {
    transform: scale(1);
    opacity: 1;
  }
}

.animate-bounce-dot {
  animation: bounce-dot 1.3s infinite ease-in-out both;
}
</style>
