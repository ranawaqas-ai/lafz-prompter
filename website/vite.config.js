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
      },
    },
  },
})
