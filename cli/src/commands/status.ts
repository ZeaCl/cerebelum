import { api, color, printJSON, loadConfig } from '../api'
import * as fs from 'fs'
import * as path from 'path'
import * as os from 'os'

const STATE_FILE = path.join(os.homedir(), '.cerebelum', 'state.json')

// ── Status ──────────────────────────────────────────────────

export async function showStatus() {
  const config = loadConfig()

  console.log(`\n${color('cyan', '🧠 Cerebelum Status')}\n`)

  // Auth
  console.log(`  Auth:    ${config.apiKey ? color('green', '✅ autenticado') : color('red', '❌ no autenticado')}`)

  // Certs
  const certsDir = path.join(os.homedir(), '.cerebelum', 'certs')
  const hasCerts = fs.existsSync(path.join(certsDir, 'ca.crt'))
  console.log(`  Certs:   ${hasCerts ? color('green', '✅ mTLS listos') : color('yellow', '❌ no generados')}`)

  // Blueprints
  try {
    const { data } = await api('GET', '/api/v1/workflows')
    const workflows = (data as any)?.data || []
    console.log(`  Blueprints: ${workflows.length} desplegados`)
    for (const w of workflows) {
      console.log(`    ${color('purple', '•')} ${w.label || w.id} ${color('gray', `(v${w.version || '?'})`)}`)
    }
  } catch {
    console.log(`  Blueprints: ${color('gray', 'no disponible')}`)
  }

  // Workers
  try {
    const { data } = await api('GET', '/api/v1/workers')
    const workers = (data as any)?.data || []
    console.log(`  Workers:  ${workers.length} registrados`)
    for (const w of workers) {
      console.log(`    ${color('green', '•')} ${w.id} ${color('gray', `@ ${w.url}`)}`)
    }
  } catch {
    console.log(`  Workers:  ${color('gray', 'no disponible')}`)
  }

  // Last executions
  const state = loadState()
  if (state.lastExecutions?.length) {
    console.log(`\n  ${color('bold', 'Últimas ejecuciones:')}`)
    for (const exec of state.lastExecutions.slice(0, 5)) {
      const statusColor = exec.status === 'completed' ? 'green' : exec.status === 'failed' ? 'red' : 'yellow'
      console.log(`    ${color(statusColor, '•')} ${exec.id.slice(0, 12)}... ${exec.status} ${color('gray', `(${exec.workflow})`)}`)
    }
  }

  console.log('')
}

// ── Logs (no args) ──────────────────────────────────────────

export async function showLastLogs(follow: boolean) {
  const state = loadState()
  const lastExec = state.lastExecutions?.[0]

  if (!lastExec) {
    console.log(`\n${color('gray', 'No hay ejecuciones recientes.')}`)
    console.log(`  Ejecutá ${color('green', 'cerebelum run')} primero.\n`)
    return
  }

  const { executionLogs } = await import('./logs')
  await executionLogs(lastExec.id, follow, false)
}

// ── State Management ────────────────────────────────────────

export function saveExecutionState(execId: string, workflow: string, status: string) {
  const state = loadState()
  state.lastExecutions = [
    { id: execId, workflow, status, time: new Date().toISOString() },
    ...(state.lastExecutions || []).slice(0, 19),
  ]
  fs.mkdirSync(path.dirname(STATE_FILE), { recursive: true })
  fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2))
}

function loadState(): { lastExecutions?: Array<{ id: string; workflow: string; status: string; time: string }> } {
  try {
    return JSON.parse(fs.readFileSync(STATE_FILE, 'utf-8'))
  } catch {
    return {}
  }
}
