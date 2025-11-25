<template>
  <div class="min-h-screen bg-white">
    <AppHeader @toggle-menu="toggleMobileMenu" />

    <main class="transition-all duration-300">
      <RouterView />
    </main>

    <AppFooter />
    <MobileMenu :is-open="isMobileMenuOpen" @close="toggleMobileMenu" />
  </div>
</template>

<script setup lang="ts">
import { onBeforeMount, ref } from 'vue';
import { RouterView } from 'vue-router';
import AppHeader from './components/AppHeader.vue';
import AppFooter from './components/AppFooter.vue';
import MobileMenu from './components/MobileMenu.vue';
import { useWalletStore } from './store/useWalletStore';

const walletStore = useWalletStore();
const isMobileMenuOpen = ref(false);
const toggleMobileMenu = () => (isMobileMenuOpen.value = !isMobileMenuOpen.value);

onBeforeMount(async () => {
  await walletStore.init();
});
</script>
