<template>
  <footer
    class="w-full fixed bottom-0 left-0 border-t border-gray-200 bg-white text-gray-600 text-sm py-4 flex items-center justify-center font-sans"
  >
    © {{ currentYear }} Dotns. All rights reserved.
  </footer>
</template>

<script setup lang="ts">
const currentYear = new Date().getFullYear();
</script>
