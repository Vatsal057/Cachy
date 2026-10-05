import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.vatxzz.cachy',
  appName: 'Cachy',
  webDir: 'dist',
  // Match the app theme so there's no white flash on launch.
  backgroundColor: '#181818',
};

export default config;
