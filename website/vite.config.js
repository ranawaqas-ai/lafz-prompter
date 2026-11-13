import { defineConfig } from 'vite'
import { resolve } from 'path'

export default defineConfig({
  base: './',
  build: {
    outDir: '../docs',
    rollupOptions: {
      input: {
        main: resolve(__dirname, 'index.html'),
        features: resolve(__dirname, 'features.html'),
        'privacy-policy': resolve(__dirname, 'privacy-policy.html'),
        terms: resolve(__dirname, 'terms.html'),
        'teleprompter-for-zoom': resolve(__dirname, 'teleprompter-for-zoom.html'),
        'read-script-looking-at-camera': resolve(__dirname, 'read-script-looking-at-camera.html'),
        'hidden-teleprompter-screen-share': resolve(__dirname, 'hidden-teleprompter-screen-share.html'),
      },
    },
  },
})
