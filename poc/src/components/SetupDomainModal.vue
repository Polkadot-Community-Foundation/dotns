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
        @click.self="close"
      >
        <div class="bg-white rounded-2xl shadow-md w-full max-w-md p-8 font-sans text-gray-800">
          <h2 class="text-xl font-semibold mb-4">Domain Setup Required</h2>

          <p class="text-gray-600 mb-6">
            Your domain needs to be set up before you can manage records. This requires
            {{ needsReclaim && needsResolver ? 'two' : 'one' }} transaction{{
              needsReclaim && needsResolver ? 's' : ''
            }}:
          </p>

          <div class="space-y-3 mb-6">
            <div v-if="needsReclaim" class="flex items-start gap-3">
              <div
                :class="[
                  'w-6 h-6 rounded-full flex items-center justify-center text-sm font-medium',
                  currentStep > 1
                    ? 'bg-green-100 text-green-600'
                    : currentStep === 1
                      ? 'bg-blue-100 text-blue-600'
                      : 'bg-gray-100 text-gray-600',
                ]"
              >
                <svg
                  v-if="currentStep === 1"
                  class="animate-spin h-4 w-4"
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
                  ></circle>
                  <path
                    class="opacity-75"
                    fill="currentColor"
                    d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                  ></path>
                </svg>
                <span v-else-if="currentStep > 1">✓</span>
                <span v-else>1</span>
              </div>
              <div>
                <p class="font-medium text-gray-900">Reclaim Ownership</p>
                <p class="text-sm text-gray-600">
                  Transfer domain control from registrar to your wallet
                </p>
              </div>
            </div>

            <div v-if="needsResolver" class="flex items-start gap-3">
              <div
                :class="[
                  'w-6 h-6 rounded-full flex items-center justify-center text-sm font-medium',
                  currentStep > 2
                    ? 'bg-green-100 text-green-600'
                    : currentStep === 2
                      ? 'bg-blue-100 text-blue-600'
                      : 'bg-gray-100 text-gray-600',
                ]"
              >
                <svg
                  v-if="currentStep === 2"
                  class="animate-spin h-4 w-4"
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
                  ></circle>
                  <path
                    class="opacity-75"
                    fill="currentColor"
                    d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                  ></path>
                </svg>
                <span v-else-if="currentStep > 2">✓</span>
                <span v-else>{{ needsReclaim ? '2' : '1' }}</span>
              </div>
              <div>
                <p class="font-medium text-gray-900">Set Resolver</p>
                <p class="text-sm text-gray-600">Configure resolver to manage domain records</p>
              </div>
            </div>
          </div>

          <div class="flex justify-end gap-3">
            <button
              @click="close"
              :disabled="isProcessing"
              class="px-4 py-2 rounded-lg border border-gray-300 hover:bg-gray-100 transition disabled:opacity-50 disabled:cursor-not-allowed"
            >
              Cancel
            </button>
            <button
              @click="handleSetup"
              :disabled="isProcessing"
              class="px-4 py-2 rounded-lg bg-[#E6007A] hover:bg-[#d1006f] text-white font-medium transition disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-2"
            >
              <svg
                v-if="isProcessing"
                class="animate-spin h-4 w-4"
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
                ></circle>
                <path
                  class="opacity-75"
                  fill="currentColor"
                  d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                ></path>
              </svg>
              {{ statusText }}
            </button>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<script setup lang="ts">
import { ref, watch, computed } from 'vue';
import { useWalletStore } from '../store/useWalletStore';
import { zeroHash } from 'viem';
import type { TransactionResult } from '@/type';

const props = defineProps<{
  open: boolean;
  name: string;
  needsReclaim: boolean;
  needsResolver: boolean;
}>();

const emit = defineEmits(['close', 'complete']);

const wallet = useWalletStore();
const isProcessing = ref(false);
const currentStep = ref(0);

const statusText = computed(() => {
  if (!isProcessing.value) return 'Start Setup';
  if (currentStep.value === 1) return 'Reclaiming...';
  if (currentStep.value === 2) return 'Setting resolver...';
  return 'Processing...';
});

watch(
  () => props.open,
  v => {
    if (v) {
      currentStep.value = 0;
      isProcessing.value = false;
    }
  }
);

function close() {
  if (!isProcessing.value) {
    emit('close');
  }
}

async function handleSetup() {
  isProcessing.value = true;

  try {
    let finalResult: TransactionResult = { hash: zeroHash, status: false };

    if (props.needsReclaim) {
      currentStep.value = 1;
      const reclaimResult = await wallet.reclaimDomain(props.name);

      if (!reclaimResult.status) {
        finalResult = reclaimResult;
        emit('complete', finalResult);
        return;
      }

      currentStep.value = 2;
    } else if (props.needsResolver) {
      currentStep.value = 2;
    }

    if (props.needsResolver) {
      const resolverResult = await wallet.setResolverForName(props.name);
      finalResult = resolverResult;

      if (resolverResult.status) {
        currentStep.value = 3;
      }
    }

    setTimeout(() => {
      emit('complete', finalResult);
    }, 500);
  } catch (e) {
    console.error('Setup failed:', e);
    emit('complete', { hash: zeroHash, status: false });
  } finally {
    isProcessing.value = false;
  }
}
</script>
