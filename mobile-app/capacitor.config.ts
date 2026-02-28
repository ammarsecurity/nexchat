import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.nexchat.app',
  appName: 'NexChat',
  webDir: 'dist',
  android: {
    allowMixedContent: true
  }
};

export default config;
