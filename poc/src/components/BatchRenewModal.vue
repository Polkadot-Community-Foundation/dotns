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
            class="bg-white rounded-2xl shadow-md w-full max-w-xl p-10 font-sans text-gray-800"
          >
            <h2 class="text-2xl font-bold text-gray-900 text-center mb-2">Batch Renew</h2>
            <p class="text-gray-500 text-sm text-center mb-8">
              You are renewing {{ handles.length }} subdomains for the same duration.
            </p>

            <div class="mb-6">
              <label class="text-sm font-semibold text-gray-700 text-left block mb-2">
                Renewal Duration
              </label>
              <div class="flex items-center border border-gray-200 rounded-xl overflow-hidden">
                <button
                  @click="decreaseDuration"
                  class="px-4 py-2 text-gray-600 hover:bg-gray-100 disabled:opacity-40"
                >
                  −
                </button>

                <input
                  v-model.number="duration"
                  type="number"
                  min="1"
                  class="w-full text-center py-2 text-gray-800 focus:outline-none hide-arrows"
                />

                <button @click="increaseDuration" class="px-4 py-2 text-gray-600 hover:bg-gray-100">
                  +
                </button>

                <div class="relative border-l border-gray-200">
                  <select
                    v-model="unit"
                    class="appearance-none bg-white text-gray-700 px-4 py-2 pr-8 text-sm font-medium focus:outline-none focus:ring-2 focus:ring-[#E6007A]/40 rounded-r-lg"
                  >
                    <option value="minutes">minutes</option>
                    <option value="hours">hours</option>
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

            <div class="border-t border-gray-100 pt-4 mb-6 max-h-56 overflow-y-auto">
              <table class="w-full text-sm text-left">
                <thead class="text-gray-500 font-semibold">
                  <tr>
                    <th class="pl-2 py-2">Subdomain</th>
                    <th class="text-right pr-2 py-2">Price</th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    v-for="(h, index) in handles"
                    :key="index"
                    class="border-b border-gray-100 hover:bg-gray-50 transition"
                  >
                    <td class="pl-2 py-2 font-medium text-gray-800 break-all">{{ h.name }}.dot</td>
                    <td class="text-right pr-2 py-2 text-gray-600">
                      {{ calculatePrice(h.name).toFixed(3) }} DOT
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>

            <div class="mt-8">
              <div class="flex justify-between text-sm font-medium mb-1">
                <span>Estimated Total</span>
                <span>{{ totalPrice.toFixed(3) }} DOT</span>
              </div>
              <p class="text-xs text-gray-400 mb-4">+ 0.001 DOT network fee</p>

              <div class="flex justify-end gap-3">
                <button
                  @click="$emit('close')"
                  class="px-5 py-2 rounded-lg border border-gray-300 text-gray-700 hover:bg-gray-100 font-medium transition"
                >
                  Cancel
                </button>
                <button
                  @click="confirm"
                  class="px-6 py-2 rounded-lg font-semibold text-white bg-[#E6007A] hover:bg-[#d1006f] transition"
                >
                  Confirm Renewal
                </button>
              </div>
            </div>
          </div>
        </Transition>
      </div>
    </Transition>
  </Teleport>
</template>

<script setup lang="ts">
import { ref, computed } from 'vue';

const props = defineProps<{ open: boolean; handles: any[] }>();
const emit = defineEmits<{ close: []; confirm: [number] }>();

const duration = ref(5);
const unit = ref('minutes');

const calculatePrice = (name: string) => {
  const base = 0.002;
  const mult = unit.value === 'years' ? 100 : unit.value === 'months' ? 10 : 1;
  return base * duration.value * mult * (1 + name.length / 20);
};

const totalPrice = computed(() =>
  props.handles.reduce((acc, h) => acc + calculatePrice(h.name), 0)
);

const increaseDuration = () => {
  duration.value++;
};
const decreaseDuration = () => {
  duration.value = Math.max(1, duration.value - 1);
};

const confirm = () => {
  emit('confirm', 1);
};
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

/* Scrollbar styling */
::-webkit-scrollbar {
  width: 6px;
}

::-webkit-scrollbar-track {
  background: transparent;
}

::-webkit-scrollbar-thumb {
  background-color: rgba(0, 0, 0, 0.1);
  border-radius: 9999px;
}

::-webkit-scrollbar-thumb:hover {
  background-color: rgba(0, 0, 0, 0.2);
}

/* Firefox */
* {
  scrollbar-width: thin;
  scrollbar-color: rgba(0, 0, 0, 0.15) transparent;
}
</style>
