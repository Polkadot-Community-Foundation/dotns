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
            class="bg-white rounded-2xl shadow-2xl w-full max-w-md p-10 text-center relative font-sans"
          >
            <button
              class="absolute top-5 right-5 text-gray-400 hover:text-gray-600 transition-colors"
              @click="$emit('close')"
              aria-label="Close modal"
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

            <h2 class="text-2xl font-bold text-gray-900 mb-3">Renew {{ handle }}</h2>
            <p class="text-gray-500 text-sm mb-10 leading-relaxed">
              Extend your domain registration for the selected duration.
            </p>

            <div class="mb-8">
              <label class="block text-sm font-semibold text-gray-700 text-left mb-2">
                Renewal Duration
              </label>
              <div
                class="flex items-center border border-gray-200 rounded-xl overflow-hidden shadow-sm"
              >
                <button @click="decreaseDuration" class="px-4 py-2 text-gray-600 hover:bg-gray-100">
                  −
                </button>

                <input
                  v-model.number="amount"
                  @input="onAmountInput"
                  type="number"
                  :min="minValue"
                  class="w-full text-center py-2 text-gray-800 focus:outline-none hide-arrows"
                />

                <button @click="increaseDuration" class="px-4 py-2 text-gray-600 hover:bg-gray-100">
                  +
                </button>

                <div class="relative border-l border-gray-200">
                  <select
                    v-model="selectedUnit"
                    @change="onUnitChange"
                    class="appearance-none bg-white text-gray-700 px-4 py-2 pr-8 text-sm font-medium focus:outline-none focus:ring-2 focus:ring-[#E6007A]/40 rounded-r-lg"
                  >
                    <option value="minutes">minutes</option>
                    <option value="days">days</option>
                    <option value="months">months</option>
                    <option value="years">years</option>
                  </select>
                  <svg
                    class="absolute right-2 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-500 pointer-events-none"
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

            <div class="mb-10 text-left">
              <div class="flex justify-between items-center text-sm font-medium text-gray-700 mb-1">
                <span>Estimated Renewal Fee</span>
                <span v-if="isLoading" class="text-gray-400 animate-pulse">Fetching...</span>
                <span v-else>{{ formattedPrice }}</span>
              </div>
              <p class="text-xs text-gray-400">+ network transaction fee</p>
            </div>

            <button
              @click="submit"
              class="w-full py-3 rounded-xl bg-[#E6007A] hover:bg-[#d1006f] text-white font-semibold transition"
              :disabled="isLoading"
            >
              Renew
            </button>
          </div>
        </Transition>
      </div>
    </Transition>
  </Teleport>
</template>

<script setup lang="ts">
import { ref, computed, watch } from 'vue';
import { useWalletStore } from '../store/useWalletStore';
import type { Unit } from '../type';
import { getSecondsForUnit } from '../utils';
import { useDomainStore } from '@/store/useDomainStore';

const props = defineProps<{ open: boolean; handle: string }>();
const emit = defineEmits<{
  close: [];
  confirm: [{ handle: string; duration: bigint; unit: Unit }];
}>();

const wallet = useWalletStore();
const domainStore = useDomainStore();

const selectedUnit = ref<Unit>('minutes');
const amount = ref(5);
const price = ref('0');
const isLoading = ref(true);

const minValue = computed(() => (selectedUnit.value === 'minutes' ? 5 : 1));

async function fetchPrice() {
  try {
    isLoading.value = true;
    const seconds = getSecondsForUnit(selectedUnit.value);
    const duration = BigInt(amount.value) * seconds;
    const cost = await domainStore.fetchRegistrationCost(props.handle, duration, true);
    price.value = cost as string;
  } catch (err) {
    console.error('Failed to fetch price', err);
    price.value = '0';
  } finally {
    isLoading.value = false;
  }
}

const formattedPrice = computed(() => `${price.value}`);

function enforceMinOnUnit() {
  if (selectedUnit.value === 'minutes') {
    amount.value = Math.max(amount.value, 5);
  } else {
    if (amount.value === 5) {
      amount.value = 1;
    }
    amount.value = Math.max(amount.value, 1);
  }
}

function onUnitChange() {
  enforceMinOnUnit();
  if (wallet.isConnected) fetchPrice();
}

function increaseDuration() {
  amount.value += 1;
  if (wallet.isConnected) fetchPrice();
}

function decreaseDuration() {
  if (selectedUnit.value === 'minutes') {
    amount.value = Math.max(amount.value - 1, 5);
  } else {
    console.log('decreaseDuration: ', amount.value);
    amount.value = Math.max(amount.value - 1, 1);
  }
  if (wallet.isConnected) fetchPrice();
}

function onAmountInput() {
  if (Number.isNaN(amount.value)) {
    amount.value = selectedUnit.value === 'minutes' ? 5 : 1;
  }
  enforceMinOnUnit();
  if (wallet.isConnected) fetchPrice();
}

function submit() {
  enforceMinOnUnit();
  const seconds = getSecondsForUnit(selectedUnit.value);
  const duration = BigInt(amount.value) * seconds;
  emit('confirm', { handle: props.handle, duration, unit: selectedUnit.value });
  emit('close');
}

watch(
  () => props.open,
  isOpen => {
    if (isOpen) {
      enforceMinOnUnit();
      if (wallet.isConnected) fetchPrice();
    }
  },
  { immediate: true }
);

watch(selectedUnit, () => {
  enforceMinOnUnit();
  if (wallet.isConnected) fetchPrice();
});
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
