<template>
  <main class="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-16 sm:py-24 font-sans text-center">
    <div class="mb-12 animate-fade-in">
      <h1 class="text-4xl sm:text-5xl md:text-6xl font-extrabold text-gray-900 mb-4">
        Find Your <span class="text-[#E6007A]">.dot</span> Handle
      </h1>
      <p class="text-lg sm:text-xl text-gray-600 max-w-2xl mx-auto">
        Search for available handles or verify existing registrations on Polkadot.
      </p>
    </div>

    <SearchInput />
  </main>
</template>

<script setup lang="ts">
import SearchInput from '../components/SearchInput.vue';
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
</style>
