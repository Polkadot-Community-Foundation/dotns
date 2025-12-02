<template>
  <div class="relative font-sans">
    <div
      class="relative transition-all duration-300 flex items-center rounded-2xl"
      :class="['border bg-white shadow-sm w-full', borderClass]"
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
          @focus="isFocused = true"
          @blur="handleBlur"
          @input="handleInput"
          type="text"
          placeholder="Search for your dot handle..."
          class="w-full py-4 pr-16 text-lg bg-transparent border-none focus:outline-none placeholder-gray-400 transition-colors duration-200"
          :class="{
            'text-gray-800': !status,
            'text-green-600 placeholder-green-400': status === 'available',
            'text-[#E6007A] placeholder-[#E6007A]/60': status === 'taken',
          }"
        />
        <span
          class="absolute right-4 top-1/2 -translate-y-1/2 text-lg font-medium pointer-events-none transition-colors duration-200"
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

    <div v-if="status && !isLoading" class="mt-[2%] text-center transition-all duration-200">
      <p
        class="text-sm font-medium mb-3"
        :class="status === 'available' ? 'text-green-600' : 'text-[#E6007A]'"
      >
        {{ status === 'available' ? 'Handle is available' : 'Handle is already taken' }}
      </p>

      <button
        v-if="status === 'available'"
        @click="registerHandle"
        class="px-6 py-3 rounded-xl font-medium text-white bg-[#E6007A] hover:bg-[#d1006f] transition-colors duration-200"
      >
        Register Handle
      </button>
    </div>

    <RegisterModal
      :open="showModal"
      :handle="searchQuery"
      @close="showModal = false"
      @wait="openWaitingModal"
    />

    <WaitingPeriod
      :open="showWaiting"
      :handle="searchQuery"
      :duration="waitingDuration"
      :onComplete="finalizeRegistration"
      @finalized="handleFinalized"
      @close="handleWaitingComplete"
    />

    <TransactionStatus
      :open="showTransaction"
      :handle="searchQuery"
      :transaction="transaction"
      @close="showTransaction = false"
    />
  </div>
</template>

<script setup lang="ts">
import { ref, computed } from 'vue';
import RegisterModal from './RegisterModal.vue';
import WaitingPeriod from './WaitingPeriod.vue';
import TransactionStatus from './TransactionStatus.vue';
import type { DotNSStatus, TransactionResult } from '../type';
import { zeroHash } from 'viem';
import { useDomainStore } from '@/store/useDomainStore';
import { useUserStoreManager } from '@/store/useUserStoreManager';

const storeManager = useUserStoreManager();
const domainStore = useDomainStore();
const searchQuery = ref('');
const isFocused = ref(false);
const isLoading = ref(false);
const status = ref<DotNSStatus | null>(null);

const showModal = ref(false);
const showWaiting = ref(false);
const showTransaction = ref(false);
const waitingDuration = ref(0);
const pendingRegistration = ref<any>(null);
const pendingDuration = ref<bigint>(0n);
const transaction = ref<TransactionResult>({
  hash: zeroHash,
  status: false,
});

let debounceTimer: number;

function registerHandle() {
  showModal.value = true;
}

function openWaitingModal(duration: number, waitTime: bigint, registration: any) {
  showModal.value = false;
  waitingDuration.value = Number(waitTime);
  pendingDuration.value = BigInt(duration);
  pendingRegistration.value = registration;
  setTimeout(() => (showWaiting.value = true), 400);
}

async function finalizeRegistration() {
  try {
    const hash = await domainStore.finalizeRegistration(pendingRegistration.value);
    return hash;
  } catch (err) {
    console.error('Finalize registration failed:', err);
    return { status: false, hash: zeroHash };
  }
}

function handleFinalized(transactionResults: TransactionResult) {
  transaction.value = transactionResults;
  showTransaction.value = true;
}

function handleWaitingComplete() {
  showWaiting.value = false;
}

function handleInput() {
  clearTimeout(debounceTimer);
  status.value = null;
  if (!searchQuery.value.trim()) {
    isLoading.value = false;
    return;
  }
  isLoading.value = true;
  debounceTimer = window.setTimeout(checkHandleAvailability, 800);
}

function handleBlur() {
  isFocused.value = false;
}

async function checkHandleAvailability() {
  try {
    const available = await storeManager.checkHandleAvailability(searchQuery.value);
    status.value = available.available ? 'available' : 'taken';
  } catch (err) {
    console.error('Handle availability check failed:', err);
    status.value = 'taken';
  } finally {
    isLoading.value = false;
  }
}

const borderClass = computed(() => {
  if (status.value === 'available') return 'border-green-400 focus-within:border-green-500';
  if (status.value === 'taken') return 'border-[#E6007A] focus-within:border-[#E6007A]';
  return 'border-gray-300 focus-within:border-[#E6007A] focus-within:ring-2 focus-within:ring-[#E6007A]/40';
});
</script>
