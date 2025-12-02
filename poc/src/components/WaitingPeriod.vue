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
            <h2 class="text-2xl font-bold text-gray-900 mb-3 mt-2">{{ localHandle }}</h2>

            <p class="text-gray-500 text-sm mb-10 leading-relaxed">
              Let’s make sure no one else is registering this handle during this confirmation
              period.
            </p>

            <div class="relative w-52 h-52 mx-auto mb-10">
              <svg
                class="absolute inset-0 w-full h-full"
                viewBox="0 0 240 240"
                :class="{ 'pulse-ring': remaining === 0 }"
              >
                <circle cx="120" cy="120" r="100" stroke="#e5e7eb" stroke-width="10" fill="none" />

                <circle
                  cx="120"
                  cy="120"
                  r="100"
                  stroke="#E6007A"
                  stroke-width="10"
                  fill="none"
                  stroke-linecap="round"
                  :stroke-dasharray="circumference"
                  :stroke-dashoffset="strokeOffset"
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
                    d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 
                       7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
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
import { ref, onUnmounted, computed, watch } from 'vue';
import { zeroHash } from 'viem';
import type { TransactionResult } from '../type';

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

const radius = 100;
const circumference = 2 * Math.PI * radius;

const strokeOffset = computed(() => {
  const progress = remaining.value / props.duration;
  return circumference * progress;
});

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
    const res = await props.onComplete();
    emit('finalized', res);
  } catch {
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
  v => {
    if (v) startCountdown();
    else if (timer) clearInterval(timer);
  }
);

watch(
  () => props.handle,
  v => {
    localHandle.value = v.includes('.dot') ? v : `${v}.dot`;
  }
);

onUnmounted(() => {
  if (timer) clearInterval(timer);
});
</script>

<style scoped>
.pulse-ring {
  animation: pulse 1.6s ease-in-out infinite;
}

@keyframes pulse {
  0% {
    transform: scale(1);
    opacity: 1;
  }
  50% {
    transform: scale(1.04);
    opacity: 0.7;
  }
  100% {
    transform: scale(1);
    opacity: 1;
  }
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
