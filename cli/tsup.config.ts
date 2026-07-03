import { defineConfig } from 'tsup'

export default defineConfig({
  entry: { index: 'src/index.ts' },
  format: ['cjs'],
  dts: false,
  clean: true,
  platform: 'node',
  target: 'node18',
})
