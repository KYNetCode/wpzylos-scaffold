import { defineConfig } from 'vite';
import tailwindcss from '@tailwindcss/vite';
import vue from '@vitejs/plugin-vue';
// To use React instead of Vue, uncomment the line below and comment out the vue import above:
// import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [
    tailwindcss(),
    vue(),
    // To use React instead of Vue, uncomment react() below and comment out vue() above:
    // react(),
  ],
  build: {
    outDir: 'dist',
    manifest: true,
    rollupOptions: {
      input: {
        app: 'resources/js/app.js',
        admin: 'resources/js/admin.js',
      },
      output: {
        entryFileNames: 'js/[name].js',
        assetFileNames: 'css/[name][extname]',
      },
    },
  },
});
