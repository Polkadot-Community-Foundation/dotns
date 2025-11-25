<template>
  <main class="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-16 sm:py-24 font-sans text-center">
    <Transition name="fade">
      <div v-if="!isNavigating" class="mb-12 animate-fade-in">
        <h1 class="text-4xl sm:text-5xl md:text-6xl font-extrabold text-gray-900 mb-4">
          Whois <span class="text-[#E6007A]">.dot</span> Lookup
        </h1>
        <p class="text-lg sm:text-xl text-gray-600 max-w-2xl mx-auto">
          Search for any <span class="font-semibold text-[#E6007A]">.dot</span> handle to see who
          owns it on Polkadot.
        </p>
      </div>
    </Transition>

    <div class="max-w-2xl mx-auto">
      <div
        class="relative transition-all duration-300 flex items-center rounded-2xl border bg-white shadow-sm w-full"
        :class="borderClass"
      >
        <div class="flex items-center justify-center pl-4 pr-3 h-full">
          <svg
            class="w-5 h-5"
            :class="{
              'text-[#E6007A]': status === 'taken',
              'text-green-600': status === 'available',
              'text-gray-400': !status,
            }"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"
            />
          </svg>
        </div>

        <div class="relative flex-1 flex items-center">
          <input
            v-model="searchQuery"
            @input="handleInput"
            @keyup.enter="navigateToProfile"
            @focus="isFocused = true"
            @blur="handleBlur"
            type="text"
            placeholder="Search for a dot handle..."
            class="w-full py-4 pr-16 text-lg bg-transparent border-none focus:outline-none placeholder-gray-400 transition-colors duration-200"
            :class="{
              'text-gray-800': !status,
              'text-green-600 placeholder-green-400': status === 'available',
              'text-[#E6007A] placeholder-[#E6007A]/60': status === 'taken',
            }"
          />
          <span
            class="absolute right-4 top-1/2 -translate-y-1/2 text-lg font-medium pointer-events-none"
            :class="{
              'text-gray-400': !status,
              'text-green-600': status === 'available',
              'text-[#E6007A]': status === 'taken',
            }"
          >
            .dot
          </span>
        </div>

        <div class="absolute right-14 top-1/2 -translate-y-1/2">
          <svg
            v-if="isLoading"
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
                 0 5.373 0 12h4zm2 5.291A7.962 
                 7.962 0 014 12H0c0 3.042 
                 1.135 5.824 3 7.938l3-2.647z"
            />
          </svg>

          <svg
            v-else-if="status === 'available'"
            class="h-6 w-6 text-green-500"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M5 13l4 4L19 7"
            />
          </svg>

          <svg
            v-else-if="status === 'taken'"
            class="h-6 w-6 text-[#E6007A]"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M6 18L18 6M6 6l12 12"
            />
          </svg>
        </div>
      </div>

      <Transition name="fade">
        <div v-if="!isLoading && status" class="mt-8 text-center">
          <div
            v-if="status === 'available'"
            class="p-6 bg-green-50 border border-green-200 rounded-2xl"
          >
            <p class="text-green-700 font-medium text-lg">This handle is available!</p>
            <p class="text-green-600 mt-2 text-sm">No owner found on the registry.</p>
          </div>

          <div
            v-else-if="status === 'taken'"
            class="p-6 bg-[#fff0f5] border border-[#f7c2da] rounded-2xl cursor-pointer"
            @click="navigateToProfile"
          >
            <p class="text-[#E6007A] font-medium text-lg mb-2">
              {{ searchQuery }}.dot is already taken
            </p>
            <p class="text-gray-500 text-sm mt-1">Click to view {{ searchQuery }}.dot profile →</p>
          </div>
        </div>
      </Transition>
    </div>
  </main>
</template>

<script setup lang="ts">
import { ref, computed } from 'vue';
import { useRouter } from 'vue-router';
import { useWalletStore } from '@/store/useWalletStore';
import type { DotNSStatus } from '@/type';

const router = useRouter();
const wallet = useWalletStore();

const searchQuery = ref('');
const status = ref<DotNSStatus | null>(null);
const isLoading = ref(false);
const isFocused = ref(false);
const isNavigating = ref(false);

let debounceTimer: number;

function handleInput() {
  clearTimeout(debounceTimer);
  status.value = null;
  if (!searchQuery.value.trim()) {
    isLoading.value = false;
    return;
  }
  isLoading.value = true;
  debounceTimer = window.setTimeout(checkName, 800);
}

function handleBlur() {
  isFocused.value = false;
}

async function checkName() {
  try {
    const available = await wallet.checkHandleAvailability(searchQuery.value);
    status.value = available ? 'available' : 'taken';
  } catch (err) {
    console.error('Whois check failed:', err);
    status.value = null;
  } finally {
    isLoading.value = false;
  }
}

async function navigateToProfile() {
  if (status.value === 'taken' && searchQuery.value.trim()) {
    isNavigating.value = true;
    await new Promise(resolve => setTimeout(resolve, 250));
    router.push(`/whois/${searchQuery.value}`);
  }
}

const borderClass = computed(() => {
  if (status.value === 'available') return 'border-green-400 focus-within:border-green-500';
  if (status.value === 'taken') return 'border-[#E6007A] focus-within:border-[#E6007A]';
  return 'border-gray-300 focus-within:border-[#E6007A] focus-within:ring-2 focus-within:ring-[#E6007A]/40';
});
</script>

<style scoped>
@keyframes fade-in {
  from {
    opacity: 0;
    transform: translateY(12px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}
.animate-fade-in {
  animation: fade-in 0.8s ease-out forwards;
}

.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.25s ease;
}
.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}
</style>
