<template>
  <table class="min-w-full table-fixed divide-y divide-gray-200 text-sm">
    <thead class="bg-gray-50">
      <tr>
        <th class="px-6 py-3 text-left font-medium text-gray-600 w-[220px]">Domain</th>
        <th class="px-6 py-3 text-left font-medium text-gray-600 w-[120px]">Type</th>
        <th class="px-6 py-3 text-left font-medium text-gray-600 w-[160px]">Expiry</th>
        <th class="px-6 py-3 text-left font-medium text-gray-600 w-[140px]">Status</th>
        <th v-if="showActions" class="px-6 py-3 text-right font-medium text-gray-600 w-[280px]">
          Actions
        </th>
      </tr>
    </thead>

    <tbody class="divide-y divide-gray-100 bg-white">
      <tr v-for="domain in domains" :key="domain.name" class="hover:bg-gray-50 transition">
        <td class="px-6 py-3 font-medium text-gray-800 truncate">
          {{ domain.name }}
        </td>

        <td class="px-6 py-3 text-gray-700">
          {{ domain.type }}
        </td>

        <td class="px-6 py-3 text-gray-600">
          {{ domain.expiry }}
        </td>

        <td class="px-6 py-3">
          <span class="inline-flex items-center gap-2 text-xs font-medium text-gray-700">
            <svg
              v-if="domain.statusIcon === 'check'"
              class="w-3.5 h-3.5 text-gray-400"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
              stroke-width="2.5"
            >
              <path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7" />
            </svg>

            <svg
              v-else-if="domain.statusIcon === 'clock'"
              class="w-3.5 h-3.5 text-gray-400"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
              stroke-width="2"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
              />
            </svg>

            <svg
              v-else-if="domain.statusIcon === 'x'"
              class="w-3.5 h-3.5 text-gray-400"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
              stroke-width="2.5"
            >
              <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
            </svg>

            {{ domain.statusLabel }}
          </span>
        </td>

        <td v-if="showActions" class="px-6 py-3 text-right">
          <div class="inline-flex items-center gap-2 justify-start w-[260px]">
            <button
              v-if="domain.needsResolver && domain.isOwner"
              @click="$emit('setup', domain.name)"
              class="px-3 py-1.5 text-sm font-medium text-orange-600 rounded-md hover:bg-orange-50 transition-colors"
            >
              Add Resolver
            </button>

            <button
              v-if="domain.isOwner"
              @click="$emit('edit', domain.name)"
              class="px-3 py-1.5 text-sm font-medium text-gray-700 rounded-md hover:bg-gray-100 transition-colors"
            >
              Edit
            </button>

            <button
              v-if="
                domain.type === 'TLD' &&
                (domain.statusLabel === 'Active' || domain.statusLabel === 'Grace Period')
              "
              @click="$emit('renew', domain.name)"
              class="px-3 py-1.5 text-sm font-medium text-[#E6007A] rounded-md hover:bg-pink-50 transition-colors"
            >
              Renew
            </button>

            <button
              v-else-if="domain.statusLabel === 'Expired'"
              @click="$emit('register', domain.name)"
              class="px-3 py-1.5 text-sm font-medium text-[#E6007A] rounded-md hover:bg-pink-50 transition-colors"
            >
              Register
            </button>

            <button
              v-if="domain.isOwner && !domain.needsResolver"
              @click="$emit('resolve', domain.name)"
              class="px-3 py-1.5 text-sm font-medium text-purple-600 rounded-md hover:bg-purple-50 transition-colors"
            >
              Resolve
            </button>
          </div>
        </td>
      </tr>
    </tbody>
  </table>
</template>

<script setup lang="ts">
import type { MyDomain } from '@/type';

defineProps<{
  domains: MyDomain[];
  showActions: boolean;
}>();

defineEmits(['renew', 'register', 'edit', 'resolve', 'setup']);
</script>
