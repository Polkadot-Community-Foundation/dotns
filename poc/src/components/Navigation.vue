<template>
  <nav class="flex items-center gap-1 font-sans">
    <RouterLink
      v-for="item in navItems"
      :key="item.name"
      :to="item.path"
      class="px-4 py-2 rounded-lg text-sm font-medium transition-all duration-200"
      :class="
        isActive(item.path)
          ? 'bg-[#FCE5EF] text-[#E6007A]'
          : 'text-gray-600 hover:bg-[#FCE5EF] hover:text-[#E6007A]'
      "
    >
      {{ item.name }}
    </RouterLink>
  </nav>
</template>

<script setup lang="ts">
import { useWalletStore } from '../store/useWalletStore';
import { ref, watch } from 'vue';
import { useRoute } from 'vue-router';

const route = useRoute();
const wallet = useWalletStore();

const navItems = ref(
  wallet.isConnected
    ? [
        { name: 'Search', path: '/' },
        { name: 'Lookup', path: '/lookup' },
        { name: 'Profile', path: '/profile' },
      ]
    : [
        { name: 'Search', path: '/' },
        { name: 'Lookup', path: '/lookup' },
      ]
);
watch(
  () => wallet.isConnected,
  isConnected => {
    navItems.value = isConnected
      ? [
          { name: 'Search', path: '/' },
          { name: 'Lookup', path: '/lookup' },
          { name: 'Profile', path: '/profile' },
        ]
      : [
          { name: 'Search', path: '/' },
          { name: 'Lookup', path: '/lookup' },
        ];
  }
);
const isActive = (path: string) => route.path === path;
</script>
