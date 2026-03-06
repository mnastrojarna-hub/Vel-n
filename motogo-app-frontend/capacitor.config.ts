import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'cz.motogo24.app',
  appName: 'MotoGo24',
  webDir: 'www',
  android: {
    webContentsDebuggingEnabled: true,
  },
  server: {
    androidScheme: 'https',
  },
  plugins: {
    StatusBar: {
      backgroundColor: '#1a1a2e',
      style: 'DARK',
    },
    Keyboard: {
      resize: 'body',
      scrollAssist: true,
    },
  },
};

export default config;
