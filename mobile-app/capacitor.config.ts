import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'site.nexchat.app',
  appName: 'NexChat – نيكس شات',
  webDir: 'dist',
  android: {
    allowMixedContent: true
  },
  plugins: {
    App: {
      disableBackButtonHandler: false, // false حتى يعترض Capacitor زر الرجوع ويطلق حدث backButton
    }
  }
};

export default config;
