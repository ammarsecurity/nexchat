import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import { readFileSync } from 'fs'
import { resolve } from 'path'

const pkg = JSON.parse(readFileSync(resolve(__dirname, 'package.json'), 'utf-8'))

// https://vite.dev/config/
export default defineConfig({
  plugins: [vue()],
  define: {
    global: 'globalThis',
    __APP_VERSION__: JSON.stringify(pkg.version || '1.0.3'),
  },
  server: {
    port: 5175,
    // If 5175 is taken, Vite picks the next free port (5176, …)
    strictPort: false
  }
})
