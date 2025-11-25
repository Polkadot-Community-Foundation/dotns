<template>
  <main class="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 py-16 font-sans text-gray-800">
    <div class="mb-12 text-center">
      <h1 class="text-4xl font-extrabold text-gray-900 mb-4">My Domains</h1>
    </div>

    <div class="mb-6 flex justify-between items-center flex-wrap gap-4">
      <input
        v-model="searchQuery"
        type="text"
        placeholder="Search domains..."
        class="border border-gray-300 rounded-lg px-4 py-2 w-full sm:w-1/3 focus:ring-2 focus:ring-[#E6007A]/40 focus:outline-none"
        :disabled="isLoading"
      />
      <div class="flex gap-3" v-if="tlds.length > 0">
        <button
          @click="openAddSubdomains"
          :disabled="isLoading"
          class="px-5 py-2 rounded-lg bg-[#E6007A] hover:bg-[#d1006f] text-white font-medium transition disabled:opacity-50 disabled:cursor-not-allowed"
        >
          Add Subdomain
        </button>
      </div>
    </div>

    <div
      v-if="isLoading"
      class="overflow-x-auto border border-gray-200 rounded-xl shadow-sm animate-pulse"
    >
      <table class="min-w-full divide-y divide-gray-200 text-sm">
        <thead class="bg-gray-50">
          <tr>
            <th v-for="i in 5" :key="i" class="px-6 py-3 text-left">
              <div class="h-4 bg-gray-200 rounded w-24"></div>
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-gray-100 bg-white">
          <tr v-for="i in 5" :key="i" class="animate-pulse">
            <td v-for="j in 5" :key="j" class="px-6 py-3">
              <div class="h-4 bg-gray-200 rounded w-20"></div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <div
      v-else-if="allDomains.length === 0"
      class="border border-gray-200 rounded-xl shadow-sm p-16 text-center"
    >
      <svg
        class="w-16 h-16 mx-auto mb-4 text-gray-300"
        fill="none"
        viewBox="0 0 24 24"
        stroke="currentColor"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="1.5"
          d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
        />
      </svg>
      <h3 class="text-lg font-medium text-gray-900 mb-2">No domains found</h3>
      <p class="text-gray-500 mb-6">Register your first domain to get started</p>
      <button
        @click="openRegisterModal('')"
        class="px-5 py-2 rounded-lg bg-[#E6007A] hover:bg-[#d1006f] text-white font-medium transition"
      >
        Register Domain
      </button>
    </div>

    <DomainTable
      v-else
      :domains="paginatedDomains"
      @renew="openRenewModal"
      @register="openRegisterModal"
      @edit="openRecordEditor"
      :showActions="true"
      @resolve="openResolve"
      @setup="fixResolver"
    />

    <div
      v-if="!isLoading && allDomains.length > 0"
      class="flex justify-between items-center mt-4 text-sm text-gray-700"
    >
      <div>
        <label>Show</label>
        <select
          v-model.number="itemsPerPage"
          class="ml-2 border border-gray-300 rounded-md px-2 py-1 focus:outline-none focus:ring-2 focus:ring-[#E6007A]/40"
        >
          <option :value="10">10</option>
          <option :value="30">30</option>
          <option :value="50">50</option>
        </select>
      </div>
      <div class="flex items-center gap-3">
        <button
          @click="prevPage"
          :disabled="currentPage === 1"
          class="px-3 py-1 border border-gray-300 rounded hover:bg-gray-100 disabled:opacity-50"
        >
          ‹
        </button>
        <span>Page {{ currentPage }} of {{ totalPages }}</span>
        <button
          @click="nextPage"
          :disabled="currentPage === totalPages"
          class="px-3 py-1 border border-gray-300 rounded hover:bg-gray-100 disabled:opacity-50"
        >
          ›
        </button>
      </div>
    </div>

    <RenewModal
      :open="showRenewModal"
      :handle="selectedHandle"
      @close="showRenewModal = false"
      @confirm="confirmRenew"
    />
    <AddSubdomainModal
      :open="showAddModal?.open || false"
      @close="showAddModal = undefined"
      :tlds="tlds"
    />
    <RegisterModal
      :open="showRegisterModal"
      :handle="selectedHandle"
      @close="showRegisterModal = false"
      @wait="openWaitingModal"
    />
    <WaitingPeriod
      :open="showWaiting"
      :handle="selectedHandle"
      :duration="waitingDuration"
      :onComplete="finalizeRegistration"
      @finalized="handleFinalized"
      @close="showWaiting = false"
    />
    <TransactionStatus
      :open="showTransaction"
      :handle="selectedHandle"
      :transaction="transaction"
      @close="showTransaction = false"
    />
    <ResolveIPFSModal
      :open="showResolveModal"
      :name="selectedDomain"
      @close="showResolveModal = false"
      @save="saveResolve"
    />
  </main>
</template>

<script setup lang="ts">
import { ref, computed, onBeforeMount, watch } from 'vue';
import { useWalletStore } from '@/store/useWalletStore';
import RenewModal from '../components/RenewModal.vue';
import AddSubdomainModal from '../components/AddSubdomainModal.vue';
import ResolveIPFSModal from '../components/ResolveIPFSModal.vue';
import RegisterModal from '../components/RegisterModal.vue';
import WaitingPeriod from '../components/WaitingPeriod.vue';
import TransactionStatus from '../components/TransactionStatus.vue';
import DomainTable from '../components/DomainTable.vue';
import type { MyDomain, TransactionResult } from '@/type';
import { getAddress, zeroHash } from 'viem';
import { formatTimestamp } from '@/utils';
import { useRouter } from 'vue-router';

const wallet = useWalletStore();
const isLoading = ref(true);
const allDomains = ref<MyDomain[]>([]);
const searchQuery = ref('');
const showRenewModal = ref(false);
const showAddModal = ref<any>(null);
const showRegisterModal = ref(false);
const showWaiting = ref(false);
const showTransaction = ref(false);
const selectedHandle = ref('');
const transaction = ref<TransactionResult>({ hash: zeroHash, status: false });
const waitingDuration = ref(0);
const pendingRegistration = ref<any>(null);
const pendingDuration = ref<bigint>(0n);
const currentPage = ref(1);
const itemsPerPage = ref(10);
const gracePeriod = ref<bigint>(0n);
const tlds = ref<string[]>([]);
const router = useRouter();
const showResolveModal = ref(false);
const selectedDomain = ref('');

function openRecordEditor(name: string) {
  router.push(`/whois/${name}`);
}

function getEnsLevel(name: string) {
  return name.replace('.dot', '').split('.').length;
}
function getType(name: string) {
  return getEnsLevel(name) === 1 ? 'TLD' : 'Subdomain';
}
function calculateStatus(expiry: bigint, isTLD: boolean) {
  const now = BigInt(Math.floor(Date.now() / 1000));
  if (!isTLD) return { label: 'Active', icon: 'check' };
  if (now < expiry) return { label: 'Active', icon: 'check' };
  if (now < expiry + gracePeriod.value) return { label: 'Grace Period', icon: 'clock' };
  return { label: 'Expired', icon: 'x' };
}
function formatExpiry(ts: bigint, isTLD: boolean) {
  if (!isTLD) return 'Tied to parent';
  return formatTimestamp(ts);
}

watch(
  () => wallet.isConnected,
  v => v && loadDomains()
);
onBeforeMount(() => {
  if (wallet.isConnected) {
    loadDomains();
  } else {
    return router.replace('/');
  }
});

const filteredDomains = computed(() =>
  allDomains.value.filter(d => d.name.toLowerCase().includes(searchQuery.value.toLowerCase()))
);
const totalPages = computed(
  () => Math.ceil(filteredDomains.value.length / itemsPerPage.value) || 1
);
const paginatedDomains = computed(() =>
  filteredDomains.value.slice(
    (currentPage.value - 1) * itemsPerPage.value,
    currentPage.value * itemsPerPage.value
  )
);
function nextPage() {
  if (currentPage.value < totalPages.value) currentPage.value++;
}
function prevPage() {
  if (currentPage.value > 1) currentPage.value--;
}

function openRenewModal(name: string) {
  selectedHandle.value = name!;
  showRenewModal.value = true;
}

function openRegisterModal(name: string) {
  const dotnsName = name.split('.')[0];
  selectedHandle.value = dotnsName!;
  showRegisterModal.value = true;
}
function openAddSubdomains() {
  if (tlds.value.length > 0) showAddModal.value = { open: true, tld: '', tlds };
}
function openWaitingModal(duration: number, waitTime: bigint, registration: any) {
  showRegisterModal.value = false;
  waitingDuration.value = Number(waitTime);
  pendingDuration.value = BigInt(duration);
  pendingRegistration.value = registration;
  setTimeout(() => (showWaiting.value = true), 400);
}
async function finalizeRegistration() {
  try {
    const hash = await wallet.finalizeRegistration(pendingRegistration.value);
    return hash;
  } catch (err) {
    console.error('Finalize registration failed:', err);
    return { status: false, hash: zeroHash };
  }
}
function handleFinalized(txResults: TransactionResult) {
  transaction.value = txResults;
  showTransaction.value = true;
}
async function confirmRenew(confirmation: any) {
  showRenewModal.value = false;
  transaction.value = { hash: zeroHash, status: undefined };
  showTransaction.value = true;
  const txResults = await wallet.renewDomain(selectedHandle.value, confirmation.duration);
  transaction.value = txResults;
  await loadDomains();
}

function openResolve(domain: string) {
  selectedDomain.value = domain;
  showResolveModal.value = true;
}

async function saveResolve(hash: string) {
  showResolveModal.value = false;
  showTransaction.value = true;
  transaction.value = { hash: zeroHash, status: undefined };

  try {
    const tx = await wallet.setContentHash(selectedDomain.value, hash);
    transaction.value = tx;
  } catch {
    transaction.value = { hash: zeroHash, status: false };
  }
}
async function loadDomains() {
  isLoading.value = true;

  gracePeriod.value = await wallet.getGracePeriod();
  const names = await wallet.getSubdomains();
  const results = (await Promise.all(
    names.map(async name => {
      const type = getType(name);
      const isTLD = type === 'TLD';
      let expiry = 0n;

      if (isTLD) {
        expiry = await wallet.nameExpires(name);
      }

      const status = calculateStatus(expiry, isTLD);
      const ownerOfDomain = await wallet.getUser(name);
      const isOwner = !!(
        wallet.address &&
        ownerOfDomain &&
        getAddress(wallet.address) === getAddress(ownerOfDomain)
      );

      let needsResolver = false;
      if (isOwner) {
        try {
          const setup = await wallet.checkDomainSetup(name);
          needsResolver = setup.needsResolver;
        } catch (e) {
          console.error('Failed to check domain setup:', e);
        }
      }

      return {
        name,
        type,
        expiry: formatExpiry(expiry, isTLD),
        statusLabel: status.label,
        statusIcon: status.icon,
        isOwner,
        needsResolver,
      };
    })
  )) as Array<MyDomain>;

  allDomains.value = results;
  tlds.value = results.filter(d => d.type === 'TLD').map(d => d.name);

  isLoading.value = false;
}

async function fixResolver(domain: string) {
  showTransaction.value = true;
  transaction.value = { hash: zeroHash, status: undefined };

  try {
    const result = await wallet.setResolverForName(domain);
    transaction.value = result;
    await loadDomains();
  } catch (e) {
    console.error('Failed to setup resolver:', e);
    transaction.value = { hash: zeroHash, status: false };
  }
}
</script>
