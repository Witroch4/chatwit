import path from 'path';
import vue from '@vitejs/plugin-vue';
import yaml from '@rollup/plugin-yaml';
import { defineConfig } from 'vite';
import ruby from 'vite-plugin-ruby';
import { aliases, vueOptions } from './vite.shared';

const isLibraryMode = process.env.BUILD_MODE === 'library';
const plugins = isLibraryMode ? [] : [ruby(), vue(vueOptions), yaml()];

export default defineConfig({
  plugins,
  server: {
    host: '0.0.0.0',
    allowedHosts: true,
  },
  css: {
    preprocessorOptions: {
      scss: {
        api: 'modern-compiler',
      },
    },
  },
  build: {
    rollupOptions: {
      output: {
        ...(isLibraryMode
          ? {
              dir: 'public/packs',
              entryFileNames: chunkInfo =>
                chunkInfo.name === 'sdk' ? 'js/sdk.js' : '[name].js',
            }
          : {}),
        inlineDynamicImports: isLibraryMode,
      },
    },
    lib: isLibraryMode
      ? {
          entry: path.resolve(__dirname, './app/javascript/entrypoints/sdk.js'),
          formats: ['iife'],
          name: 'sdk',
        }
      : undefined,
  },
  resolve: { alias: aliases },
});
