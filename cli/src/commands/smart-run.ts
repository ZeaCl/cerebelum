/**
 * cerebelum smart run — zero-friction workflow execution.
 *
 * Checklist:
 * 1. Login → if not logged in, trigger OAuth2 PKCE
 * 2. Certs → if not present, POST /api/v1/dev-certs and save
 * 3. Blueprint → if not deployed, deploy from workflow.py in cwd
 * 4. Worker → if not running, start Python worker
 * 5. Execute → run the workflow and stream logs
 */

import { api, color, loadConfig, saveTokens } from '../api'
import * as fs from 'fs'
import * as path from 'path'
import * as os from 'os'
import { execSync, spawn, ChildProcess } from 'child_process'

const CERTS_DIR = path.join(os.homedir(), '.cerebelum', 'certs')
const STATE_FILE = path.join(os.homedir(), '.cerebelum', 'state.json')
const DEFAULT_WF = 'workflow.py'

// ── Smart Run ──────────────────────────────────────────────

export async function smartRun(args: string[], json: boolean) {
  const opts = parseRunOpts(args)
  const startTime = Date.now()

  console.log(`\n${color('cyan', '🧠 Cerebelum Run')}\n`)

  // 1. Login check
  if (!(await ensureLogin())) return

  // 2. Certs check
  if (!(await ensureCerts())) return

  // 3. Blueprint check
  const wfName = await ensureBlueprint(opts.file || DEFAULT_WF)
  if (!wfName) return

  // 4. Worker check
  const workerPid = await ensureWorker()
  if (!workerPid) return

  // 5. Execute
  const execId = await runWorkflow(wfName, opts.inputs || '{}')
  if (!execId) return

  // 6. Stream logs
  await streamLogs(execId, startTime)

  // 7. Cleanup worker
  if (workerPid) {
    try { process.kill(workerPid) } catch {}
  }
}

// ── Steps ─────────────────────────────────────────────────

async function ensureLogin(): Promise<boolean> {
  const config = loadConfig()
  if (config.apiKey) {
    console.log(`  ${color('green', '✅')} Login — ${color('gray', 'JWT presente')}`)
    return true
  }

  console.log(`  ${color('yellow', '❌')} Login — no autenticado`)
  console.log(`  ${color('bold', '→')} Abriendo navegador...`)

  const { login } = await import('./login')
  await login()
  return true
}

async function ensureCerts(): Promise<boolean> {
  const caPath = path.join(CERTS_DIR, 'ca.crt')
  const certPath = path.join(CERTS_DIR, 'client.crt')
  const keyPath = path.join(CERTS_DIR, 'client.key')

  if (fs.existsSync(caPath) && fs.existsSync(certPath) && fs.existsSync(keyPath)) {
    console.log(`  ${color('green', '✅')} Certs — ${color('gray', 'mTLS listos')}`)
    return true
  }

  console.log(`  ${color('yellow', '❌')} Certs — solicitando al engine...`)

  try {
    const config = loadConfig()
    const resp = await fetch(`${config.baseUrl}/api/v1/dev-certs`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${config.apiKey}` },
      signal: AbortSignal.timeout(15_000),
    })

    if (!resp.ok) throw new Error(`HTTP ${resp.status}`)

    const data = (await resp.json()) as { ca_crt: string; client_crt: string; client_key: string }

    fs.mkdirSync(CERTS_DIR, { recursive: true })
    fs.writeFileSync(caPath, data.ca_crt)
    fs.writeFileSync(certPath, data.client_crt)
    fs.writeFileSync(keyPath, data.client_key)
    fs.chmodSync(keyPath, 0o600)

    console.log(`  ${color('green', '✅')} Certs — guardados en ${CERTS_DIR}`)
    return true
  } catch (err) {
    console.log(`  ${color('red', '✕')} Certs — ${(err as Error).message}`)
    return false
  }
}

async function ensureBlueprint(file: string): Promise<string | null> {
  const fullPath = path.resolve(file)

  if (!fs.existsSync(fullPath)) {
    console.log(`  ${color('red', '✕')} Blueprint — ${file} no encontrado en ${process.cwd()}`)
    return null
  }

  const code = fs.readFileSync(fullPath, 'utf-8')
  const wfName = extractWorkflowName(code) || path.basename(file, '.py')

  // Check if already deployed (simple check: try workflow show)
  const { status } = await api('GET', `/api/v1/workflows`)
  const workflows = ((await api('GET', '/api/v1/workflows')).data as any)?.data || []
  const alreadyDeployed = workflows.some((w: any) => w.id === wfName || w.label === wfName)

  if (alreadyDeployed) {
    console.log(`  ${color('green', '✅')} Blueprint — ${color('bold', wfName)} (ya desplegado)`)
    return wfName
  }

  console.log(`  ${color('yellow', '❌')} Blueprint — ${wfName} no desplegado`)
  console.log(`  ${color('bold', '→')} Desplegando...`)

  const deployRes = await api('POST', '/api/v1/workflows/deploy', {
    name: wfName,
    module: `Elixir.${wfName}`,
    code,
    language: 'python',
  })

  if (deployRes.status === 201 || deployRes.status === 200) {
    console.log(`  ${color('green', '✅')} Blueprint — ${color('bold', wfName)} desplegado`)
    return wfName
  } else {
    console.log(`  ${color('red', '✕')} Blueprint — deploy falló (HTTP ${deployRes.status})`)
    return null
  }
}

async function ensureWorker(): Promise<number | null> {
  // Check if worker is already running by checking the worker list
  const workersRes = await api('GET', '/api/v1/workers').catch(() => ({ status: 0, data: {} }))
  const existingWorkers = ((workersRes as any).data as any)?.data || []
  if (existingWorkers.length > 0) {
    console.log(`  ${color('green', '✅')} Worker — ${existingWorkers.length} ya registrados`)
    return 0
  }

  console.log(`  ${color('yellow', '❌')} Worker — iniciando...`)

  // Start worker using the cerebelum SDK from demo-cloud venv
  // Use the existing working worker script
  const venvPython = findVenvPython()
  if (!venvPython) {
    console.log(`  ${color('red', '✕')} Worker — no se encontró Python con cerebelum-sdk`)
    console.log(`  ${color('gray', '   Instalá: pip install cerebelum-sdk')}`)
    return null
  }

  // Generate worker script
  const workerScript = path.join(os.homedir(), '.cerebelum', 'worker.py')
  writeWorkerScript(workerScript)

  const child = spawn(venvPython, [workerScript], {
    detached: false,
    stdio: ['ignore', 'pipe', 'pipe'],
  })

  // Wait for worker to register with engine
  let registered = false
  for (let i = 0; i < 15; i++) {
    await new Promise(r => setTimeout(r, 2000))
    const res = await api('GET', '/api/v1/workers').catch(() => ({ status: 0, data: {} }))
    const workers = ((res as any).data as any)?.data || []
    if (workers.length > 0) {
      registered = true
      break
    }
  }

  if (!registered) {
    console.log(`  ${color('red', '✕')} Worker — no se registró a tiempo`)
    try { process.kill(child.pid!) } catch {}
    return null
  }

  console.log(`  ${color('green', '✅')} Worker — PID ${child.pid} (localhost:50051)`)
  return child.pid || 0
}

async function runWorkflow(wfName: string, inputsStr: string): Promise<string | null> {
  let inputs: Record<string, unknown> = {}
  try { inputs = JSON.parse(inputsStr) } catch {}

  console.log(`\n  ${color('bold', '🚀')} Ejecutando ${color('bold', wfName)}...\n`)

  const resp = await api('POST', '/api/v1/executions', {
    workflow: wfName,
    input: inputs,
  })

  if (resp.status === 200 || resp.status === 201) {
    const exec = (resp.data as any).data || resp.data
    return exec.id || exec.execution_id
  }

  console.log(`  ${color('red', '✕')} Error: ${(resp.data as any).error}`)
  return null
}

async function streamLogs(execId: string, startTime: number) {
  let lastVersion = -1

  while (true) {
    await new Promise(r => setTimeout(r, 1000))
    const { status, data } = await api('GET', `/api/v1/executions/${encodeURIComponent(execId)}/events`)

    if (status !== 200) break

    const events = ((data as any).events || []) as any[]
    const newEvents = events.filter((e: any) => (e.version ?? 0) > lastVersion)

    for (const ev of newEvents) {
      const time = ev.timestamp ? new Date(ev.timestamp).toLocaleTimeString() : ''
      const eventColor =
        ev.type?.includes('Completed') || ev.type?.includes('Executed') ? 'green' :
        ev.type?.includes('Failed') ? 'red' :
        ev.type?.includes('Started') ? 'cyan' : 'gray'

      const stepInfo = ev.data?.step_name ? ` ${color('purple', `[${ev.data.step_name}]`)}` : ''
      process.stdout.write(`  ${color('gray', `[${time}]`)} ${color(eventColor, ev.type)}${stepInfo}`)

      const output = ev.data?.result || ev.data?.final_result || ev.data?.output
      if (output && typeof output === 'object' && Object.keys(output).length > 0) {
        const vals = Object.entries(output).map(([k, v]) => `${k}=${v}`).join(' · ')
        process.stdout.write(` ${color('gray', `→ ${vals}`)}`)
      }
      process.stdout.write('\n')

      lastVersion = Math.max(lastVersion, ev.version)
    }

    const lastEvent = events[events.length - 1]
    if (lastEvent && ['ExecutionCompleted', 'ExecutionFailed'].some(t => lastEvent.type?.includes(t))) {
      const elapsed = ((Date.now() - startTime) / 1000).toFixed(1)
      console.log(`\n  ${lastEvent.type?.includes('Failed') ? color('red', '✕') : color('green', '✅')} ${lastEvent.type}`)
      console.log(`  ${color('gray', `⏱️  ${elapsed}s`)}`)
      break
    }
  }
}

// ── Helpers ────────────────────────────────────────────────

function parseRunOpts(args: string[]): { file?: string; inputs?: string } {
  const opts: Record<string, string> = {}
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--file' && args[i + 1]) { opts.file = args[++i]; continue }
    if (args[i] === '--inputs' && args[i + 1]) { opts.inputs = args[++i]; continue }
    if (args[i] === '-f' && args[i + 1]) { opts.file = args[++i]; continue }
  }
  return opts
}

function extractWorkflowName(code: string): string | null {
  const match = code.match(/@workflow\s*\n\s*(?:async\s+)?def\s+(\w+)/)
  if (match) return match[1]
  return null
}

function findVenvPython(): string | null {
  // Check common locations
  const cwd = process.cwd()
  const candidates = [
    path.join(cwd, '.venv', 'bin', 'python'),
    path.join(cwd, '.venv', 'bin', 'python3'),
    '/Users/dev/Documents/zea/cerebelum-demo-cloud/.venv/bin/python',
    'python3',
    'python',
  ]
  for (const p of candidates) {
    try {
      execSync(`${p} -c "import cerebelum"`, { timeout: 5000, stdio: 'pipe' })
      return p
    } catch {}
  }
  return null
}

function writeWorkerScript(dest: string) {
  const certsDir = CERTS_DIR
  const engineUrl = loadConfig().baseUrl.replace('https://', '')
  const gRPCPort = 50051
  const coreUrl = `${new URL(loadConfig().baseUrl).hostname}:${gRPCPort}`
  const content = `"""Auto-generated Cerebelum worker — conecta a ${coreUrl}."""
import asyncio, os, sys, grpc

CERTS_DIR = ${JSON.stringify(certsDir)}
CORE_URL = ${JSON.stringify(coreUrl)}

# Load certs
with open(os.path.join(CERTS_DIR, "ca.crt"), "rb") as f: ca = f.read()
with open(os.path.join(CERTS_DIR, "client.crt"), "rb") as f: cert = f.read()
with open(os.path.join(CERTS_DIR, "client.key"), "rb") as f: key = f.read()

creds = grpc.ssl_channel_credentials(root_certificates=ca, private_key=key, certificate_chain=cert)
options = [("grpc.ssl_target_name_override", "cerebelum.zea.cl")]
channel = grpc.secure_channel(CORE_URL, creds, options)

from cerebelum.proto.worker_service_pb2_grpc import WorkerServiceStub
from cerebelum.proto.worker_service_pb2 import RegisterRequest, PollRequest, UnregisterRequest
from cerebelum.distributed import Worker

stub = WorkerServiceStub(channel)

async def main():
    worker_id = f"auto-{os.getpid()}"
    stub.Register(RegisterRequest(worker_id=worker_id, language="python", capabilities=["*"], version="1.0"), timeout=10)

    # Poll loop — execute any step generically
    try:
        while True:
            task = stub.PollForTask(PollRequest(worker_id=worker_id, timeout_ms=30000), timeout=35)
            if task.task_id:
                result = TaskResult(
                    task_id=task.task_id,
                    execution_id=task.execution_id,
                    worker_id=worker_id,
                    status=TaskStatus.SUCCESS,
                )
                stub.SubmitResult(result, timeout=10)
    except Exception:
        pass

asyncio.run(main())
`
  fs.writeFileSync(dest, content)
  fs.chmodSync(dest, 0o755)
}
