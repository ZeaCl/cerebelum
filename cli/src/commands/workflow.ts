import { api, color, printJSON } from '../api'

export async function workflowList(json: boolean) {
  const { status, data } = await api('GET', '/api/v1/workflows')

  if (status !== 200) {
    console.error(`${color('red', '❌')} Failed to list workflows (HTTP ${status})`)
    process.exit(1)
  }

  const workflows = (data as any).data || []

  if (json) {
    printJSON(workflows)
    return
  }

  if (!workflows.length) {
    console.log(`${color('gray', 'No workflows registered.')}`)
    return
  }

  console.log(`\n${color('bold', 'Available Workflows:')}`)
  console.log('═'.repeat(60))
  for (const wf of workflows) {
    const label = wf.label || wf.id
    const version = wf.version || '?'
    const timeline = wf.timeline || (wf.steps || []).filter((s: any) => !s.hidden).map((s: any) => s.label)
    const steps = Array.isArray(timeline) ? timeline.join(` ${color('gray', '→')} `) : 'no steps'

    console.log(`\n  ${color('purple', '•')} ${color('bold', label)} ${color('gray', `(v${version})`)}`)
    console.log(`    ${color('gray', wf.id)}`)
    console.log(`    ${steps}`)
  }
  console.log(`\n${color('gray', `Total: ${workflows.length} workflows`)}`)
}

export async function workflowShow(id: string, json: boolean) {
  if (!id) {
    console.error(`${color('red', '❌')} Usage: cerebelum workflow show <id>`)
    process.exit(1)
  }

  const { status, data } = await api('GET', `/api/v1/workflows/${encodeURIComponent(id)}`)

  if (status !== 200) {
    console.error(`${color('red', '❌')} Workflow not found (HTTP ${status})`)
    process.exit(1)
  }

  const wf = (data as any).data

  if (json) {
    printJSON(wf)
    return
  }

  const steps = wf.steps || []
  const visible = steps.filter((s: any) => !s.hidden)

  console.log(`\n${color('bold', wf.label || id)}`)
  console.log('═'.repeat(50))
  console.log(`  ID:      ${color('gray', wf.id)}`)
  console.log(`  Version: ${wf.version || '?'}`)
  console.log(`  Worker:  ${wf.worker_url || color('gray', 'Elixir-native')}`)
  console.log(`\n  Steps:`)
  for (const s of visible) {
    const hidden = s.hidden ? ` ${color('gray', '(hidden)')}` : ''
    console.log(`    ${color('purple', '→')} ${s.label} ${color('gray', `(${s.name})`)}${hidden}`)
  }
  console.log('')
}

export async function workflowRun(_sub: string, module: string, inputsStr: string, json: boolean) {
  if (!module) {
    console.error(`${color('red', '❌')} Usage: cerebelum workflow run <module> [--inputs '{...}']`)
    process.exit(1)
  }

  let inputs: Record<string, unknown> = {}
  try {
    inputs = JSON.parse(inputsStr)
  } catch {
    console.error(`${color('red', '❌')} Invalid JSON inputs: ${inputsStr}`)
    process.exit(1)
  }

  const { status, data } = await api('POST', '/api/v1/executions', {
    workflow: module,
    input: inputs,
  })

  if (status === 201) {
    const exec = (data as any).data
    if (json) {
      printJSON(exec)
    } else {
      console.log(`\n${color('green', '✅')} Workflow started!`)
      console.log(`   ID:     ${color('bold', exec.id)}`)
      console.log(`   Status: ${color('yellow', exec.status)}`)
    }
  } else {
    const err = (data as any).error || `HTTP ${status}`
    console.error(`\n${color('red', '❌')} ${err}`)
    process.exit(1)
  }
}
