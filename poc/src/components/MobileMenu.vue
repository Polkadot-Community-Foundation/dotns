<template>
  <Teleport to="body">
    <Transition
      enter-active-class="transition-opacity duration-200"
      enter-from-class="opacity-0"
      enter-to-class="opacity-100"
      leave-active-class="transition-opacity duration-200"
      leave-from-class="opacity-100"
      leave-to-class="opacity-0"
    >
      <div
        v-if="isOpen"
        @click="$emit('close')"
        class="fixed inset-0 bg-black/40 backdrop-blur-sm z-40 md:hidden"
      />
    </Transition>

    <Transition
      enter-active-class="transition-transform duration-300 ease-out"
      enter-from-class="translate-x-full"
      enter-to-class="translate-x-0"
      leave-active-class="transition-transform duration-300 ease-in"
      leave-from-class="translate-x-0"
      leave-to-class="translate-x-full"
    >
      <div
        v-if="isOpen"
        class="fixed right-0 top-0 bottom-0 w-64 bg-white border-l border-[#FCE5EF] shadow-2xl z-50 md:hidden"
      >
        <div class="flex flex-col h-full font-sans text-gray-800">
          <div class="flex items-center justify-between p-4 border-b border-[#FCE5EF]">
            <span class="text-xl font-bold text-[#E6007A]">Menu</span>
            <button
              @click="$emit('close')"
              class="p-2 rounded-lg text-[#E6007A] hover:bg-[#FCE5EF] transition-colors"
              aria-label="Close menu"
            >
              <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M6 18L18 6M6 6l12 12"
                />
              </svg>
            </button>
          </div>

          <nav class="flex-1 p-4">
            <RouterLink
              v-for="item in navItems"
              :key="item.name"
              :to="item.path"
              class="block w-full text-left px-4 py-3 rounded-lg text-sm font-medium mb-2 transition-all duration-200"
              :class="
                isActive(item.path)
                  ? 'bg-[#FCE5EF] text-[#E6007A]'
                  : 'text-gray-700 hover:bg-[#FCE5EF] hover:text-[#E6007A]'
              "
              @click="$emit('close')"
            >
              {{ item.name }}
            </RouterLink>
          </nav>

          <div class="p-4 border-t border-[#FCE5EF] text-center text-xs text-gray-500">
            © {{ currentYear }} Dotns
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<script setup lang="ts">
import { useWalletStore } from '../store/useWalletStore';
import { ref } from 'vue';
import { useRoute } from 'vue-router';

defineProps<{ isOpen: boolean }>();
defineEmits<{ close: [] }>();

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

const isActive = (path: string) => route.path === path;

const currentYear = new Date().getFullYear();
</script>
