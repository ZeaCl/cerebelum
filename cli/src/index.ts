#!/usr/bin/env node
import { main } from './cli'

main(process.argv.slice(2)).catch(err => {
  console.error(`\n❌ ${err.message}`)
  process.exit(1)
})
