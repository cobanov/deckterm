// The hero's animation, built into public/hero as one script and one stylesheet the page links by name.
// `npm run build` here after changing anything in this folder; the built files are committed, so the push to main
// deploys them with no build step.
import { defineConfig } from 'vite'

export default defineConfig({
  esbuild: { jsx: 'automatic' },
  build: {
    outDir: '../public/hero',
    emptyOutDir: true,
    assetsInlineLimit: 8192,
    rollupOptions: {
      input: 'main.tsx',
      output: { entryFileNames: 'hero.js', assetFileNames: 'hero[extname]' },
    },
  },
})
