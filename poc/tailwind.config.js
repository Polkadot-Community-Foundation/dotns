/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{vue,js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        'dark-purple': '#2A0A4A', // Approximated from screenshot
        'pink-logo': '#E6007A',   // Polkadot pink
      },
    },
  },
  plugins: [require('tailwindcss-animate')],
}