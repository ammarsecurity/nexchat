import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.nexchat.app',
  appName: 'NexChat',
  webDir: 'dist',
  android: {
    allowMixedContent: true
  },
  plugins: {
    App: {
      disableBackButtonHandler: true
    }
  }
};

export default config;
