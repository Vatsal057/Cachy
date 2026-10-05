import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    // Listen on all interfaces so the dev server is reachable from a phone
    // on the same Wi-Fi, e.g. http://<mac-ip>:5173
    host: true,
    port: 5173,
  },
  preview: {
    port: 4173,
  },
});
