import { api, color, printJSON } from '../api'

export async function executionStatus(id: string, json: boolean) {
  if (!id) {
    console.error(`${color('red', '❌')} Usage: cerebelum execution status <id>`)
    process.exit(1)
  }

  const { status, data } = await api('GET', `/api/v1/executions/${encodeURIComponent(id)}`)

  if (status === 404) {
    console.error(`${color('red', '❌')} Execution not found`)
    process.exit(1)
  }
  if (status !== 200) {
    console.error(`${color('red', '❌')} HTTP ${status}`)
    process.exit(1)
  }

  const exec = (data as any).data

  if (json) {
    printJSON(exec)
    return
  }

  const statusColor =
    exec.status === 'completed' ? 'green' :
    exec.status === 'failed' || exec.status === 'stopped' ? 'red' :
    exec.status === 'waiting_for_approval' ? 'yellow' :
    exec.status === 'running' ? 'cyan' : 'gray'

  const progress = exec.total_visible_steps > 0
    ? ` (${exec.visible_step}/${exec.total_visible_steps})`
    : ''

  console.log(`\n${color('bold', 'Execution')} ${color('gray', id.slice(0, 12) + '...')}`)
  console.log('═'.repeat(50))
  console.log(`  Status:   ${color(statusColor, exec.status.toUpperCase())}`)
  console.log(`  Workflow: ${exec.workflow_module?.replace('Elixir.', '') || exec.workflow_id}`)
  console.log(`  Step:     ${exec.current_step_label || '—'}${progress}`)
  console.log(`  Events:   ${exec.events_applied}`)
  console.log(`  Started:  ${exec.started_at ? new Date(exec.started_at).toLocaleString() : '—'}`)
  if (exec.duration_ms) console.log(`  Duration: ${exec.duration_ms}ms`)

  if (exec.error) {
    console.log(`\n  ${color('red', 'Error:')}`)
    printJSON(exec.error)
  }

  if (exec.status === 'waiting_for_approval') {
    console.log(`\n  ${color('yellow', '⏸️  Waiting for human approval')}`)
    console.log(`  ${color('gray', 'Run:')} cerebelum execution approve ${id}`)
  }
  console.log('')
}

export async function executionEvents(id: string, json: boolean) {
  if (!id) {
    console.error(`${color('red', '❌')} Usage: cerebelum execution events <id>`)
    process.exit(1)
  }

  const { status, data } = await api('GET', `/api/v1/executions/${encodeURIComponent(id)}/events`)

  if (status !== 200) {
    console.error(`${color('red', '❌')} Execution not found (HTTP ${status})`)
    process.exit(1)
  }

  const events = (data as any).data || []

  if (json) {
    printJSON(events)
    return
  }

  console.log(`\n${color('bold', 'Event Timeline')} ${color('gray', `(${events.length} events)`)}`)
  console.log('═'.repeat(60))

  for (const ev of events) {
    const eventColor =
      ev.type?.includes('Completed') || ev.type?.includes('Resumed') ? 'green' :
      ev.type?.includes('Failed') ? 'red' :
      ev.type?.includes('Paused') ? 'yellow' :
      'purple'

    const time = ev.timestamp ? new Date(ev.timestamp).toLocaleTimeString() : ''
    console.log(`  ${color('gray', `[v${ev.version}]`)} ${color(eventColor, ev.type)} ${color('gray', time)}`)

    if (ev.data && Object.keys(ev.data).length > 0) {
      const relevant = { ...ev.data }
      delete relevant.workflow_module
      delete relevant.execution_id
      delete relevant.timestamp
      if (Object.keys(relevant).length > 0) {
        console.log(`    ${color('gray', JSON.stringify(relevant).slice(0, 80))}`)
      }
    }
  }
  console.log('')
}

export async function executionStop(id: string, json: boolean) {
  if (!id) {
    console.error(`${color('red', '❌')} Usage: cerebelum execution stop <id>`)
    process.exit(1)
  }

  const { status, data } = await api('POST', `/api/v1/executions/${encodeURIComponent(id)}/stop`)

  if (status !== 200) {
    console.error(`${color('red', '❌')} Failed to stop (HTTP ${status})`)
    process.exit(1)
  }

  const result = (data as any).data
  if (json) {
    printJSON(result)
  } else {
    console.log(`${color('green', '✅')} Execution stopped: ${result.id}`)
  }
}

export async function executionResume(id: string, json: boolean) {
  if (!id) {
    console.error(`${color('red', '❌')} Usage: cerebelum execution resume <id>`)
    process.exit(1)
  }

  const { status, data } = await api('POST', `/api/v1/executions/${encodeURIComponent(id)}/resume`)

  if (status === 409) {
    console.log(`${color('yellow', '⚠️')} Already running`)
    return
  }
  if (status !== 200) {
    const err = (data as any).error || `HTTP ${status}`
    console.error(`${color('red', '❌')} ${err}`)
    process.exit(1)
  }

  const result = (data as any).data
  if (json) {
    printJSON(result)
  } else {
    console.log(`${color('green', '✅')} Execution resumed: ${result.status}`)
  }
}

export async function executionApprove(id: string, responseStr: string, json: boolean) {
  if (!id) {
    console.error(`${color('red', '❌')} Usage: cerebelum execution approve <id> [--response '{...}']`)
    process.exit(1)
  }

  let response: Record<string, unknown> = { decision: 'approved' }
  try {
    response = JSON.parse(responseStr)
  } catch {
    console.error(`${color('red', '❌')} Invalid JSON: ${responseStr}`)
    process.exit(1)
  }

  const { status, data } = await api('POST', `/api/v1/executions/${encodeURIComponent(id)}/approve`, { response })

  if (status !== 200) {
    const err = (data as any).error || `HTTP ${status}`
    console.error(`${color('red', '❌')} ${err}`)
    process.exit(1)
  }

  const result = (data as any).data
  if (json) {
    printJSON(result)
  } else {
    console.log(`${color('green', '✅')} Approved — status: ${result.status}`)
  }
}
