import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  // Android applicationId (iOS bundle: com.nexchat.userapp — see ios/App/App.xcodeproj)
  appId: 'site.nexchat.app',
  appName: 'NexChat – نيكس شات',
  webDir: 'dist',
  android: {
    allowMixedContent: true
  },
  ios: {
    /* scrollable = لا يضيف الـ WebView مسافة آمنة تلقائياً، نتحكم بها عبر CSS فقط (نتجنب فراغ مزدوج من الأعلى) */
    contentInset: 'scrollable',
    backgroundColor: '#0D0D1A'
  },
  plugins: {
    App: {
      disableBackButtonHandler: false,
    }
  }
};

export default config;
