<template>
  <main class="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 py-16 font-sans text-gray-800">
    <div v-if="isLoading" class="animate-fade-in">
      <div class="text-center mb-10">
        <div class="w-24 h-24 rounded-full bg-gray-200 mx-auto mb-6 shimmer"></div>
        <div class="h-8 bg-gray-300 w-48 mx-auto mb-3 rounded shimmer"></div>
        <div class="h-4 bg-gray-300 w-64 mx-auto mb-2 rounded shimmer"></div>
        <div class="h-4 bg-gray-300 w-32 mx-auto mb-6 rounded shimmer"></div>
        <div class="h-10 bg-gray-300 w-32 mx-auto rounded-lg shimmer"></div>
      </div>

      <div class="grid gap-6">
        <div class="bg-white border border-gray-200 rounded-xl shadow-sm p-6">
          <div class="h-6 bg-gray-300 w-32 mb-4 rounded shimmer"></div>
          <div class="flex gap-3">
            <div class="h-8 bg-gray-200 w-24 rounded-full shimmer"></div>
            <div class="h-8 bg-gray-200 w-28 rounded-full shimmer"></div>
          </div>
        </div>

        <div class="bg-white border border-gray-200 rounded-xl shadow-sm p-6">
          <div class="h-6 bg-gray-300 w-32 mb-4 rounded shimmer"></div>
          <div class="grid sm:grid-cols-2 gap-4">
            <div>
              <div class="h-4 bg-gray-200 w-16 mb-2 rounded shimmer"></div>
              <div class="h-4 bg-gray-300 w-full rounded shimmer"></div>
            </div>
            <div>
              <div class="h-4 bg-gray-200 w-16 mb-2 rounded shimmer"></div>
              <div class="h-4 bg-gray-300 w-32 rounded shimmer"></div>
            </div>
            <div>
              <div class="h-4 bg-gray-200 w-16 mb-2 rounded shimmer"></div>
              <div class="h-4 bg-gray-300 w-20 rounded shimmer"></div>
            </div>
          </div>
        </div>

        <div class="bg-white border border-gray-200 rounded-xl shadow-sm p-6">
          <div class="h-6 bg-gray-300 w-32 mb-4 rounded shimmer"></div>
          <div class="flex flex-wrap gap-3">
            <div class="h-8 bg-gray-200 w-32 rounded shimmer"></div>
            <div class="h-8 bg-gray-200 w-28 rounded shimmer"></div>
            <div class="h-8 bg-gray-200 w-36 rounded shimmer"></div>
          </div>
        </div>

        <div class="bg-white border border-gray-200 rounded-xl shadow-sm p-6">
          <div class="h-6 bg-gray-300 w-32 mb-4 rounded shimmer"></div>
          <div class="space-y-3">
            <div class="h-12 bg-gray-200 rounded shimmer"></div>
            <div class="h-12 bg-gray-200 rounded shimmer"></div>
            <div class="h-12 bg-gray-200 rounded shimmer"></div>
            <div class="h-12 bg-gray-200 rounded shimmer"></div>
          </div>
        </div>
      </div>
    </div>

    <div v-else class="animate-fade-in text-center">
      <img
        :src="blockieSrc"
        alt=""
        class="w-24 h-24 sm:w-28 sm:h-28 rounded-full border-4 border-[#E6007A] mx-auto mb-6 object-cover"
      />

      <h1 class="text-3xl sm:text-4xl font-extrabold text-gray-900 mb-1">{{ name }}</h1>

      <p class="text-gray-600 text-sm sm:text-base mb-1">
        {{ showFullDescription ? description : truncatedDescription }}
      </p>

      <button
        v-if="isTruncated"
        @click="showFullDescription = !showFullDescription"
        class="text-[#E6007A] hover:underline text-xs sm:text-sm"
      >
        {{ showFullDescription ? 'View less' : 'View more' }}
      </button>

      <a
        v-if="url"
        :href="url"
        target="_blank"
        rel="noopener noreferrer"
        class="text-[#E6007A] hover:underline text-sm block"
      >
        Personal Profile
      </a>

      <button
        v-if="isOwner"
        @click="showEditModal = true"
        class="mt-4 px-4 py-2 rounded-lg bg-[#E6007A] hover:bg-[#d1006f] text-white text-sm font-medium"
      >
        Edit Profile
      </button>
    </div>

    <div v-if="!isLoading && owner" class="mt-10 grid gap-6">
      <section class="bg-white border border-gray-200 rounded-xl shadow-sm p-6 text-left">
        <h2 class="text-lg font-semibold mb-4 text-gray-900">Accounts</h2>
        <div class="flex flex-wrap gap-3">
          <a
            v-if="twitter"
            :href="`https://x.com/${twitter}`"
            target="_blank"
            rel="noopener noreferrer"
            class="px-3 py-1 rounded-full bg-[#E6007A]/10 text-[#E6007A] text-sm font-medium"
          >
            @{{ twitter }}
          </a>
          <a
            v-if="github"
            :href="`https://github.com/${github}`"
            target="_blank"
            rel="noopener noreferrer"
            class="px-3 py-1 rounded-full bg-[#E6007A]/10 text-[#E6007A] text-sm font-medium"
          >
            {{ github }}
          </a>
          <p v-if="!twitter && !github" class="text-gray-500 text-sm italic">No linked accounts.</p>
        </div>
      </section>

      <section class="bg-white border border-gray-200 rounded-xl shadow-sm p-6 text-left">
        <h2 class="text-lg font-semibold mb-4 text-gray-900">Ownership</h2>
        <div class="grid sm:grid-cols-2 gap-4">
          <div>
            <p class="text-gray-500 text-sm">Owner</p>
            <a
              :href="`${explorer}/account/${owner}`"
              target="_blank"
              rel="noopener noreferrer"
              class="font-mono text-[#E6007A] text-sm break-all mt-1 hover:underline"
            >
              {{ owner }}
            </a>
          </div>
          <div>
            <p class="text-gray-500 text-sm">Expiry</p>
            <p class="text-gray-700 text-sm mt-1">{{ expiry || '—' }}</p>
          </div>
          <div>
            <p class="text-gray-500 text-sm">Parent</p>
            <p class="text-gray-700 text-sm mt-1">{{ parent }}</p>
          </div>
        </div>
      </section>

      <section class="bg-white border border-gray-200 rounded-xl shadow-sm p-6 text-left">
        <h2 class="text-lg font-semibold mb-4 text-gray-900">Other Records</h2>
        <div class="flex flex-wrap gap-3">
          <div
            v-for="(value, key) in records"
            :key="key"
            class="px-3 py-1 rounded bg-gray-100 text-gray-700 text-xs sm:text-sm font-mono truncate max-w-full"
          >
            <span class="font-semibold text-[#E6007A] mr-1">{{ key }}:</span>
            <template v-if="key === 'com.x'">
              <a
                :href="`https://x.com/${value}`"
                target="_blank"
                rel="noopener noreferrer"
                class="underline text-[#E6007A]"
              >
                @{{ value }}
              </a>
            </template>
            <template v-else-if="key === 'com.github'">
              <a
                :href="`https://github.com/${value}`"
                target="_blank"
                rel="noopener noreferrer"
                class="underline text-[#E6007A]"
              >
                {{ value }}
              </a>
            </template>
          </div>
          <p v-if="!Object.keys(records).length" class="text-gray-500 text-sm italic">
            No records found.
          </p>
        </div>
      </section>

      <section
        v-if="allDomains.length > 0"
        class="bg-white border border-gray-200 rounded-xl shadow-sm p-6 text-left"
      >
        <h2 class="text-lg font-semibold mb-4 text-gray-900">Domains</h2>
        <DomainTable
          :domains="allDomains"
          @renew="handleRenew"
          @register="handleRegister"
          @edit="handleEdit"
          :showActions="false"
          :resolve="() => console.log"
        />
      </section>
    </div>

    <EditRecordsModal
      :open="showEditModal"
      :twitter="twitter"
      :github="github"
      :description="description"
      :url="url"
      :name="name"
      @close="showEditModal = false"
      @save="handleSave"
    />

    <TransactionStatus
      :open="showTxStatus"
      :handle="name + '.dot'"
      :transaction="transaction"
      @close="showTxStatus = false"
    />
    <SetupDomainModal
      :open="showSetupModal"
      :name="setupDomain"
      :needsReclaim="setupNeeds.needsReclaim"
      :needsResolver="setupNeeds.needsResolver"
      @close="showSetupModal = false"
      @complete="handleSetupComplete"
    />
  </main>
</template>

<script setup lang="ts">
import { ref, onBeforeMount, computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useWalletStore } from '@/store/useWalletStore';
import { zeroAddress, zeroHash, getAddress, type Address } from 'viem';
import makeBlockie from 'ethereum-blockies-base64';
import { formatTimestamp } from '@/utils';
import EditRecordsModal from '../components/EditRecordsModal.vue';
import TransactionStatus from '../components/TransactionStatus.vue';
import DomainTable from '../components/DomainTable.vue';
import SetupDomainModal from '../components/SetupDomainModal.vue';
import type { ProfileRecord, TransactionResult, MyDomain, ResolverStatus } from '@/type';
import { useNetworkStore } from '@/store/useNetworkStore';
import { useDomainStore } from '@/store/useDomainStore';
import { useUserStoreManager } from '@/store/useUserStoreManager';
import { useResolverStore } from '@/store/useResolverStore';

const route = useRoute();
const router = useRouter();
const wallet = useWalletStore();
const networkStore = useNetworkStore();
const domainStore = useDomainStore();
const userStore = useUserStoreManager();
const resolverStore = useResolverStore();

const name = ref(route.params.name as string);
if (name.value && !name.value.includes('.dot')) {
  name.value = name.value + '.dot';
}
const isLoading = ref(true);
const owner = ref<string | null>(null);
const expiry = ref<string | null>(null);
const parent = ref('dot');
const twitter = ref<string | null>(null);
const github = ref<string | null>(null);
const url = ref<string | null>(null);
const description = ref<string | null>(null);
const records = ref<Record<string, string>>({});
const allDomains = ref<MyDomain[]>([]);
const gracePeriod = ref<bigint>(0n);

const showEditModal = ref(false);
const showTxStatus = ref(false);
const transaction = ref<TransactionResult>({ hash: zeroHash, status: false });

const showSetupModal = ref(false);
const setupDomain = ref('');
const setupNeeds = ref<ResolverStatus>({ needsReclaim: false, needsResolver: false, fixed: false });

const explorer = computed(() => networkStore.currentNetwork?.blockExplorerUrls?.[0] || '');

const isOwner = computed(
  () => wallet.address && owner.value && getAddress(wallet.address) === getAddress(owner.value)
);

const blockieSrc = computed(() =>
  owner.value && owner.value !== zeroAddress ? makeBlockie(owner.value) : '/default-avatar.svg'
);

const showFullDescription = ref(false);
const MAX_LEN = 50;

const truncatedDescription = computed(() => {
  if (!description.value) return '';
  if (description.value.length <= MAX_LEN) return description.value;
  return description.value.slice(0, MAX_LEN) + '...';
});

const isTruncated = computed(() => {
  return description.value && description.value.length > MAX_LEN;
});

function getEnsLevel(name: string) {
  const withoutTld = name.endsWith('.dot') ? name.slice(0, -4) : name;
  return withoutTld.split('.').length;
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

async function loadDomains(ownerAddress: Address) {
  try {
    gracePeriod.value = await domainStore.getGracePeriod();
    const names = await userStore.getSubdomainsForAddress(ownerAddress);

    const results = await Promise.all(
      names.map(async name => {
        const type = getType(name);
        const isTLD = type === 'TLD';
        let expiry = 0n;

        if (isTLD) {
          expiry = await domainStore.nameExpires(name);
        }

        const status = calculateStatus(expiry, isTLD);
        const domainOwner = await userStore.getUser(name);
        const isOwner = !!(
          ownerAddress &&
          domainOwner &&
          getAddress(ownerAddress) === getAddress(domainOwner)
        );

        let needsReclaim = false;
        let needsResolver = false;
        if (isOwner) {
          try {
            const setup = await resolverStore.checkDomainSetup(name);
            needsReclaim = setup.needsReclaim ?? false;
            needsResolver = setup.needsResolver;
          } catch (e) {
            console.error('Failed to check domain setup:', e);
            needsReclaim = false;
            needsResolver = false;
          }
        }

        return {
          name,
          type,
          expiry: formatExpiry(expiry, isTLD),
          statusLabel: status.label,
          statusIcon: status.icon,
          isOwner,
          needsReclaim,
          needsResolver,
        };
      })
    );

    allDomains.value = results as MyDomain[];
  } catch (error) {
    console.error('Failed to load domains:', error);
    allDomains.value = [];
  }
}

async function handleSetup(domain: string) {
  try {
    const setup = await resolverStore.checkDomainSetup(domain);
    setupDomain.value = domain;
    setupNeeds.value = setup;
    showSetupModal.value = !setupNeeds.value.fixed;
  } catch (e) {
    console.error('Failed to check domain setup:', e);
  }
}

function handleSetupComplete(result: TransactionResult) {
  showSetupModal.value = false;
  transaction.value = result;
  showTxStatus.value = true;
  if (owner.value) {
    loadDomains(owner.value as Address);
  }
}

onBeforeMount(async () => {
  try {
    isLoading.value = true;

    const [ownerAddress, expiryTimestamp] = await Promise.all([
      userStore.getUser(name.value),
      domainStore.nameExpires(name.value),
    ]);

    owner.value = ownerAddress;
    expiry.value = formatTimestamp(expiryTimestamp);

    if (ownerAddress !== zeroAddress) {
      const keys = ['com.x', 'com.github', 'description', 'url'];
      const values = await Promise.all(keys.map(k => resolverStore.getText(name.value, k)));

      twitter.value = values[0]!;
      github.value = values[1]!;
      description.value = values[2]!;
      url.value = values[3]!;

      records.value = {};
      keys.slice(0, 2).forEach((key, i) => {
        if (values[i]) records.value[key] = values[i] as string;
      });
      await loadDomains(ownerAddress);
    }
  } catch (error: any) {
    console.error('onBeforeMount: ', error);
  } finally {
    await handleSetup(name.value);
    isLoading.value = false;
  }
});

function handleRenew() {
  router.push('/profile');
}

function handleRegister() {
  router.push('/');
}

function handleEdit(domainName: string) {
  router.push(`/whois/${domainName}`);
}

async function handleSave(updated: ProfileRecord) {
  if (!isOwner.value) return;

  try {
    const setup = await resolverStore.checkDomainSetup(name.value);

    if (setup.needsReclaim || setup.needsResolver) {
      setupDomain.value = name.value;
      setupNeeds.value = setup;
      showSetupModal.value = true;
      showEditModal.value = false;
      return;
    }

    showTxStatus.value = true;
    transaction.value = { hash: zeroHash, status: undefined };

    let data = [
      { key: 'com.x', value: updated.twitter },
      { key: 'com.github', value: updated.github },
      { key: 'description', value: updated.description },
      { key: 'url', value: updated.url },
    ];

    const tx = await resolverStore.setProfileRecordsMulticall(name.value, data);
    transaction.value = tx;

    if (tx.status) {
      description.value = updated.description || null;
      twitter.value = updated.twitter || null;
      github.value = updated.github || null;
      url.value = updated.url || null;

      records.value = {};
      if (twitter.value) records.value['com.x'] = twitter.value;
      if (github.value) records.value['com.github'] = github.value;
      if (description.value) records.value['description'] = description.value;
      if (url.value) records.value['url'] = url.value;
    }
  } catch (e) {
    console.error('Failed to save:', e);
    transaction.value = { hash: zeroHash, status: false };
    showTxStatus.value = true;
  } finally {
    showEditModal.value = false;
  }
}
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

@keyframes shimmer {
  0% {
    background-position: -450px 0;
  }

  100% {
    background-position: 450px 0;
  }
}

.shimmer {
  background: linear-gradient(to right, #f1f1f1 4%, #e5e5e5 25%, #f1f1f1 36%);
  background-size: 1000px 100%;
  animation: shimmer 1.5s infinite linear;
}
</style>
