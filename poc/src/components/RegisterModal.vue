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
          <div v-if="open" class="bg-white rounded-2xl shadow-2xl w-full max-w-md p-8 text-center">
            <h2 class="text-2xl font-bold text-gray-900 mb-2">{{ handle }}.dot</h2>

            <p class="text-gray-500 text-sm mb-6">
              The registration process involves two transactions. The first opens the waiting period
              to ensure no other user has tried to register the same name.
            </p>

            <div class="text-left mb-6">
              <label class="text-sm font-semibold text-gray-700"> Registration Duration </label>

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
                  @input="onManualInput"
                  type="number"
                  min="5"
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
                    class="appearance-none bg-white text-gray-700 px-4 py-2 pr-10 text-sm font-medium focus:outline-none focus:ring-2 focus:ring-[#E6007A]/40 rounded-r-lg border-l border-gray-200 transition [&>option]:bg-white [&>option]:text-gray-700 [&>option]:hover:bg-[#FCE5EF]"
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

const props = defineProps<{ open: boolean; handle: string }>();
const emit = defineEmits<{ close: []; confirm: [number]; wait: [number, bigint, any] }>();

const wallet = useWalletStore();

const selectedUnit = ref<Unit>('minutes');
const amount = ref(5);
const price = ref<string>('0');
const isFetching = ref(true);
const isRegistering = ref(false);

const owner = computed(() => wallet.address ?? null);

async function fetchPriceFromStore() {
  try {
    isFetching.value = true;
    const duration = getSecondsForUnit(selectedUnit.value) * BigInt(amount.value);
    const cost = await wallet.fetchRegistrationCost(props.handle, duration);
    price.value = cost as string;
  } catch (err) {
    console.error('Failed to fetch price:', err);
    price.value = '0';
  } finally {
    isFetching.value = false;
  }
}

async function startRegistration() {
  try {
    isRegistering.value = true;

    if (!wallet.isConnected || !owner.value) {
      throw new Error('Wallet not connected.');
    }

    const duration = BigInt(getSecondsForUnit(selectedUnit.value)) * BigInt(amount.value);
    const { commitment, registration } = await wallet.makeCommitment(
      props.handle,
      owner.value,
      duration
    );

    await wallet.commitRegistration(commitment);
    const waitTime = await wallet.getMinCommitmentAge();

    emit('wait', amount.value, BigInt(waitTime), registration);

    isRegistering.value = false;
    emit('close');
  } catch (err) {
    console.error('Registration failed:', err);
    isRegistering.value = false;
  }
}

async function increaseDuration() {
  amount.value++;
  await fetchPriceFromStore();
}

async function decreaseDuration() {
  if (amount.value > 5) {
    amount.value--;
  }
  await fetchPriceFromStore();
}

async function onManualInput() {
  if (amount.value < 5) amount.value = 5;
  await fetchPriceFromStore();
}

async function onUnitChange() {
  await fetchPriceFromStore();
}

watch(
  () => props.open,
  async isOpen => {
    if (isOpen && props.handle.trim() !== '') {
      await fetchPriceFromStore();
    }
  },
  { immediate: true }
);

watch([amount, selectedUnit], fetchPriceFromStore);
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
