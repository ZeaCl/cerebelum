import { api, color, printJSON } from '../api'
import * as fs from 'fs'

export async function deployWorkflow(file: string, json: boolean) {
  if (!file) {
    console.error(`${color('red', '❌')} Usage: cerebelum deploy <workflow.py>`)
    process.exit(1)
  }

  if (!fs.existsSync(file)) {
    console.error(`${color('red', '❌')} File not found: ${file}`)
    process.exit(1)
  }

  // Read the Python workflow file as a blueprint
  const code = fs.readFileSync(file, 'utf-8')
  const fileName = path.basename(file, '.py')
  const workflowName = extractWorkflowName(code) || fileName

  const { status, data } = await api('POST', '/api/v1/workflows/deploy', {
    name: workflowName,
    module: `Elixir.${workflowName}`,
    code: code,
    language: 'python',
  })

  if (status === 201 || status === 200) {
    const wf = (data as any).data || data
    if (json) {
      printJSON(wf)
    } else {
      console.log(`\n${color('green', '✅')} Blueprint deployed!`)
      console.log(`   Workflow: ${color('bold', workflowName)}`)
      if (wf.id) console.log(`   ID:       ${color('gray', wf.id)}`)
      console.log(`\n   Run: ${color('green', `cerebelum workflow run ${workflowName} --inputs '{"name":"ZEA"}'`)}`)
    }
  } else {
    const err = (data as any).error || `HTTP ${status}`
    console.error(`\n${color('red', '❌')} ${err}`)
    process.exit(1)
  }
}

function extractWorkflowName(code: string): string | null {
  // Look for @workflow decorator or class definition
  const match = code.match(/@workflow\s*\n\s*(?:async\s+)?def\s+(\w+)/)
  if (match) return match[1]

  const classMatch = code.match(/class\s+(\w+).*Workflow/)
  if (classMatch) return classMatch[1]

  return null
}

import * as path from 'path'
