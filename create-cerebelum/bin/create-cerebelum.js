#!/usr/bin/env node
/**
 * create-cerebelum — Scaffold a new Cerebelum workflow project.
 *
 * Usage:
 *   npx @zea.cl/create-cerebelum my-project
 */

const fs = require('fs')
const path = require('path')
const { execSync } = require('child_process')

const args = process.argv.slice(2)
const projectName = args[0]

if (!projectName) {
  console.log('\n🧠  create-cerebelum — Scaffold a new Cerebelum project\n')
  console.log('  Usage: npx @zea.cl/create-cerebelum <project-name>\n')
  console.log('  Example:')
  console.log('    npx @zea.cl/create-cerebelum my-workflow')
  console.log('    cd my-workflow')
  console.log('    python workflow.py')
  console.log('')
  process.exit(0)
}

const projectDir = path.resolve(projectName)
const templateDir = path.resolve(__dirname, '..', 'template')

// ── Create project directory ──
if (fs.existsSync(projectDir)) {
  console.error(`❌ Directory "${projectName}" already exists.`)
  process.exit(1)
}

fs.mkdirSync(projectDir, { recursive: true })
console.log(`\n🧠  Creating Cerebelum project: ${projectName}\n`)

// ── Copy template files ──
const files = fs.readdirSync(templateDir)
for (const file of files) {
  const src = path.join(templateDir, file)
  const dest = path.join(projectDir, file)
  fs.copyFileSync(src, dest)
  console.log(`  ✅ ${file}`)
}

// ── Python venv ──
console.log(`\n  📦 Installing Python dependencies...`)
try {
  execSync('pip install cerebelum-sdk', {
    cwd: projectDir,
    stdio: 'pipe',
  })
  console.log(`  ✅ cerebelum-sdk installed`)
} catch {
  console.log(`  ⚠️  Could not install cerebelum-sdk via pip.`)
  console.log(`     Run: pip install cerebelum-sdk`)
}

// ── Auth hint ──
console.log(`\n  🔐 To use cloud mode, authenticate:`)
console.log(`     npx @zea.cl/cerebelum-cli login`)
console.log(`\n  🚀 Quickstart:`)
console.log(`     cd ${projectName}`)
console.log(`     python workflow.py`)
console.log(`\n  ☁️  Cloud mode:`)
console.log(`     npx @zea.cl/cerebelum-cli deploy workflow.py`)
console.log(`     npx @zea.cl/cerebelum-cli run my_workflow --inputs '{"name":"ZEA"}'`)
console.log('')
