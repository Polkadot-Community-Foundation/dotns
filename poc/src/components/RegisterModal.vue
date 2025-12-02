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
        @click.self="closeModal"
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
            class="bg-white rounded-2xl shadow-2xl w-full max-w-md p-8 text-center relative"
          >
            <button
              v-if="wallet.transactionStatus === 'idle'"
              class="absolute top-4 right-4 text-gray-400 hover:text-gray-600 transition-colors"
              @click="closeModal"
              aria-label="Close registration modal"
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

            <h2 class="text-2xl font-bold text-gray-900 mb-2">{{ handle }}.dot</h2>

            <p class="text-gray-500 text-sm mb-6">
              The registration process involves two transactions.
            </p>

            <div class="text-left mb-6">
              <label class="text-sm font-semibold text-gray-700">Registration Duration</label>

              <div
                class="flex items-center gap-0 mt-3 border border-gray-200 rounded-lg overflow-hidden w-full"
              >
                <button
                  @click="decreaseDuration"
                  class="px-4 py-2 text-gray-500 hover:bg-[#FCE5EF] hover:text-[#E6007A] transition disabled:opacity-40"
                  :disabled="isFetching"
                >
                  −
                </button>

                <input
                  v-model.number="amount"
                  @input="onAmountInput"
                  type="number"
                  :min="minValue"
                  class="w-full text-center text-gray-700 py-2 focus:outline-none hide-arrows"
                  :disabled="isFetching"
                />

                <button
                  @click="increaseDuration"
                  class="px-4 py-2 text-gray-500 hover:bg-[#FCE5EF] hover:text-[#E6007A] transition disabled:opacity-40"
                  :disabled="isFetching"
                >
                  +
                </button>

                <div class="relative border-l border-gray-200">
                  <select
                    v-model="selectedUnit"
                    @change="onUnitChange"
                    class="appearance-none bg-white text-gray-700 px-4 py-2 pr-10 text-sm font-medium focus:outline-none focus:ring-2 focus:ring-[#E6007A]/40 rounded-r-lg border-l border-gray-200 transition"
                    :disabled="isFetching"
                  >
                    <option value="minutes">minutes</option>
                    <option value="hours">hours</option>
                    <option value="days">days</option>
                    <option value="months">months</option>
                    <option value="years">years</option>
                  </select>
                  <svg
                    class="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-500"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M19 9l-7 7-7-7"
                    />
                  </svg>
                </div>
              </div>
            </div>

            <div class="text-left mb-8">
              <div class="flex justify-between text-sm font-medium text-gray-700 mb-1">
                <span>Estimated Fee</span>
                <span v-if="isFetching" class="text-gray-400 animate-pulse">Fetching...</span>
                <span v-else>{{ price }}</span>
              </div>
              <p class="text-xs text-gray-400">+ network transaction fee</p>
            </div>

            <button
              class="w-full py-3 rounded-xl bg-[#E6007A] hover:bg-[#d1006f] text-white font-medium transition-colors disabled:opacity-50"
              :disabled="isFetching || isRegistering || !wallet.isConnected"
              @click="startRegistration"
            >
              <span v-if="isRegistering" class="flex justify-center items-center gap-2">
                <svg
                  class="animate-spin h-4 w-4 text-white"
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
                    d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 
                           5.291A7.962 7.962 0 014 12H0c0 3.042 
                           1.135 5.824 3 7.938l3-2.647z"
                  />
                </svg>
                Registering...
              </span>
              <span v-else>Register</span>
            </button>
          </div>
        </Transition>
      </div>
    </Transition>
  </Teleport>
</template>

<script setup lang="ts">
import { ref, watch, computed } from 'vue';
import { useWalletStore } from '../store/useWalletStore';
import type { Unit } from '../type';
import { getSecondsForUnit } from '@/utils';
import { useDomainStore } from '@/store/useDomainStore';
import { zeroHash } from 'viem';
import { useToast } from 'vue-toastification';

const props = defineProps<{ open: boolean; handle: string }>();
const emit = defineEmits<{ close: []; confirm: [number]; wait: [number, bigint, any] }>();

const toaster = useToast();
const wallet = useWalletStore();
const domainStore = useDomainStore();

const selectedUnit = ref<Unit>('minutes');
const amount = ref(5);
const price = ref('0');
const isFetching = ref(false);
const isRegistering = ref(false);

const minValue = computed(() => (selectedUnit.value === 'minutes' ? 5 : 1));

async function fetchPrice() {
  try {
    isFetching.value = true;
    const duration = BigInt(amount.value) * getSecondsForUnit(selectedUnit.value);
    const cost = await domainStore.fetchRegistrationCost(props.handle, duration);
    price.value = cost as string;
  } catch {
    price.value = '0';
  } finally {
    isFetching.value = false;
  }
}

function enforceMin() {
  if (selectedUnit.value === 'minutes') {
    amount.value = Math.max(amount.value, 5);
  } else {
    amount.value = Math.max(amount.value, 1);
  }
}

async function onUnitChange() {
  enforceMin();
  await fetchPrice();
}

async function increaseDuration() {
  amount.value += 1;
  await fetchPrice();
}

async function decreaseDuration() {
  if (selectedUnit.value === 'minutes') {
    amount.value = Math.max(amount.value - 1, 5);
  } else {
    amount.value = Math.max(amount.value - 1, 1);
  }
  await fetchPrice();
}

async function onAmountInput() {
  if (Number.isNaN(amount.value)) {
    amount.value = minValue.value;
  }
  enforceMin();
  await fetchPrice();
}

async function startRegistration() {
  try {
    isRegistering.value = true;

    const owner = wallet.address;
    if (!wallet.isConnected || !owner) throw new Error();

    const duration = BigInt(amount.value) * getSecondsForUnit(selectedUnit.value);
    const { commitment, registration } = await domainStore.makeCommitment(
      props.handle,
      owner,
      duration
    );

    const result = await domainStore.commitRegistration(commitment);
    if (result === zeroHash) {
      toaster.error('Unable to register name');
      isRegistering.value = false;
      return;
    }

    const waitTime = await domainStore.getMinCommitmentAge();
    emit('wait', amount.value, BigInt(waitTime), registration);

    isRegistering.value = false;
    emit('close');
  } catch {
    isRegistering.value = false;
  }
}

function closeModal() {
  if (wallet.transactionStatus === 'idle') {
    emit('close');
  }
}

watch(
  () => props.open,
  async open => {
    if (open) {
      enforceMin();
      await fetchPrice();
    }
  },
  { immediate: true }
);

watch([amount, selectedUnit], enforceMin);
</script>

<style scoped>
.hide-arrows::-webkit-inner-spin-button,
.hide-arrows::-webkit-outer-spin-button {
  -webkit-appearance: none;
  margin: 0;
}

.hide-arrows {
  -moz-appearance: textfield;
}
</style>
