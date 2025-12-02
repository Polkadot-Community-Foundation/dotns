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
            class="bg-white rounded-2xl shadow-md w-full max-w-md p-8 font-sans text-gray-800"
          >
            <h2 class="text-2xl font-bold text-gray-900 text-center mb-1">Add Subdomain</h2>
            <p class="text-gray-500 text-sm text-center mb-6">
              Register a new subdomain under one of your owned .dot domains.
            </p>

            <div class="mb-3">
              <label class="text-sm font-semibold text-gray-700 block mb-2">
                Choose parent domain
              </label>
              <div class="relative">
                <select
                  v-model="selectedTLD"
                  class="w-full border border-gray-200 rounded-xl py-2 pl-4 pr-10 text-gray-700 text-sm appearance-none focus:ring-2 focus:ring-[#E6007A]/40 focus:outline-none"
                >
                  <option v-for="(tld, idx) in normalizedTLDs" :key="idx" :value="tld">
                    {{ tld }}.dot
                  </option>
                </select>

                <svg
                  class="absolute right-[14px] top-1/2 -translate-y-1/2 w-4 h-4 text-gray-500 pointer-events-none"
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

            <div class="relative mb-6">
              <input
                v-model="subdomain"
                @input="debouncedCheck"
                type="text"
                placeholder="Enter subdomain..."
                class="w-full py-3 pr-28 pl-4 border border-gray-200 rounded-xl text-gray-800 focus:outline-none placeholder-gray-400 transition-colors"
                :class="{
                  'border-[#E6007A] text-[#E6007A]': status === 'taken',
                  'border-green-500 text-green-600': status === 'available',
                }"
              />
              <span
                class="absolute right-4 top-1/2 -translate-y-1/2 text-gray-500 text-sm font-medium whitespace-nowrap"
              >
                .{{ selectedTLD }}.dot
              </span>

              <div v-if="isLoading" class="absolute right-24 top-1/2 -translate-y-1/2">
                <svg
                  class="animate-spin h-5 w-5 text-[#E6007A]"
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
                         0 5.373 0 12h4zm2
                         5.291A7.962 7.962 0 014 12H0
                         c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                  />
                </svg>
              </div>
            </div>

            <div v-if="status && !isLoading" class="text-center text-sm font-medium mb-6">
              <span v-if="status === 'available'" class="text-green-600">
                {{ fullDomain }} is available
              </span>
              <span v-else class="text-[#E6007A]"> {{ fullDomain }} is already taken </span>
            </div>

            <div class="flex justify-end gap-3">
              <button
                @click="$emit('close')"
                class="px-5 py-2 rounded-lg border border-gray-300 text-gray-700 hover:bg-gray-100 font-medium transition"
              >
                Cancel
              </button>
              <button
                @click="confirmAdd"
                :disabled="!subdomain.trim() || status !== 'available' || isSubmitting"
                class="px-6 py-2 rounded-lg font-semibold text-white bg-[#E6007A] hover:bg-[#d1006f] disabled:opacity-50 transition"
              >
                <span v-if="isSubmitting" class="flex items-center gap-2 justify-center">
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
                    />
                    <path
                      class="opacity-75"
                      fill="currentColor"
                      d="M4 12a8 8 0 018-8V0C5.373 0
                           0 5.373 0 12h4zm2
                           5.291A7.962 7.962 0 014 12H0
                           c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                    />
                  </svg>
                  Processing...
                </span>
                <span v-else>Register</span>
              </button>
            </div>
          </div>
        </Transition>
      </div>
    </Transition>
  </Teleport>
</template>

<script setup lang="ts">
import { ref, computed, watch } from 'vue';
import type { DotNSStatus } from '../type';
import { useUserStoreManager } from '@/store/useUserStoreManager';

const props = defineProps<{ open: boolean; tlds: string[] }>();
const emit = defineEmits<{ close: []; confirm: [{ txHash: string | null }] }>();

const storeManager = useUserStoreManager();
const subdomain = ref('');
const selectedTLD = ref<string | undefined>('');
const status = ref<DotNSStatus | null>(null);
const isLoading = ref(false);
const isSubmitting = ref(false);

const normalizedTLDs = computed(() => props.tlds.map(t => t.replace(/\.dot$/, '')));

watch(
  normalizedTLDs,
  newList => {
    if (newList.length > 0 && !selectedTLD.value) {
      selectedTLD.value = newList[0];
    }
  },
  { immediate: true }
);

const fullDomain = computed(() =>
  subdomain.value.trim() && selectedTLD.value ? `${subdomain.value}.${selectedTLD.value}.dot` : ''
);

let debounceTimer: number | NodeJS.Timeout;
const debouncedCheck = () => {
  clearTimeout(debounceTimer);
  status.value = null;
  isLoading.value = true;
  debounceTimer = setTimeout(checkAvailability, 600);
};

async function checkAvailability() {
  let name = subdomain.value.trim();
  if (!name) {
    isLoading.value = false;
    status.value = null;
    return;
  }
  name = `${name}.${selectedTLD.value}`;
  const taken = await storeManager.checkHandleAvailability(name);
  status.value = taken ? 'taken' : 'available';
  isLoading.value = false;
}

async function confirmAdd() {
  try {
    isSubmitting.value = true;
    const txHash = await storeManager.registerSubdomain(
      selectedTLD.value as string,
      subdomain.value
    );
    emit('confirm', { txHash });
  } catch (err) {
    console.error('Subdomain registration failed:', err);
    emit('confirm', { txHash: null });
  } finally {
    isSubmitting.value = false;
    emit('close');
  }
}
</script>
