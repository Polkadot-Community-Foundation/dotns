<template>
  <header class="border-b border-[#FCE5EF] bg-white backdrop-blur-sm">
    <div
      class="w-full flex items-center justify-between h-16 px-6 sm:px-8 lg:px-10 font-sans text-gray-800"
    >
      <Logo />

      <div class="hidden md:block">
        <Navigation />
      </div>

      <div class="flex items-center gap-4">
        <WalletButton />

        <button
          @click="$emit('toggle-menu')"
          class="md:hidden p-2 rounded-lg text-[#E6007A] hover:bg-[#FCE5EF] transition-colors"
          aria-label="Toggle menu"
        >
          <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M4 6h16M4 12h16M4 18h16"
            />
          </svg>
        </button>
      </div>
    </div>
  </header>
</template>

<script setup lang="ts">
import Logo from './Logo.vue';
import Navigation from './Navigation.vue';
import WalletButton from './WalletButton.vue';

defineEmits<{ 'toggle-menu': [] }>();
</script>
