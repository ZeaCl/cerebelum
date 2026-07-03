import { api, color, printJSON } from '../api'

export async function executionLogs(id: string, follow: boolean, json: boolean) {
  if (!id) {
    console.error(`${color('red', '❌')} Usage: cerebelum logs <execution_id> [--follow]`)
    process.exit(1)
  }

  let lastVersion = -1

  while (true) {
    const { status, data } = await api('GET', `/api/v1/executions/${encodeURIComponent(id)}/events`)

    if (status !== 200) {
      if (lastVersion === -1) {
        console.error(`${color('red', '❌')} Execution not found (HTTP ${status})`)
        process.exit(1)
      }
      break
    }

    const events = ((data as any).events || (data as any).data || []) as any[]
    const newEvents = events.filter((e: any) => (e.version ?? 0) > lastVersion)

    if (newEvents.length > 0) {
      for (const ev of newEvents) {
        if (json) {
          printJSON(ev)
        } else {
          const eventColor =
            ev.type?.includes('Completed') || ev.type?.includes('Resumed') ? 'green' :
            ev.type?.includes('Failed') ? 'red' :
            ev.type?.includes('Paused') || ev.type?.includes('Waiting') ? 'yellow' :
            ev.type?.includes('Started') ? 'cyan' : 'gray'

          const time = ev.timestamp ? new Date(ev.timestamp).toLocaleTimeString() : ''
          const stepInfo = ev.data?.step_name ? ` ${color('purple', `[${ev.data.step_name}]`)}` : ''
          console.log(`${color('gray', `[${time}]`)} ${color(eventColor, ev.type)}${stepInfo}`)

          const output = ev.data?.result || ev.data?.final_result
          if (output && typeof output === 'object' && Object.keys(output).length > 0) {
            console.log(`  ${color('gray', JSON.stringify(output).slice(0, 120))}`)
          }
        }
        lastVersion = Math.max(lastVersion, ev.version)
      }
    }

    // Check if execution is terminal
    const lastEvent = events[events.length - 1]
    if (lastEvent && ['ExecutionCompleted', 'ExecutionFailed', 'ExecutionCancelled'].some(t => lastEvent.type?.includes(t))) {
      console.log(`\n${color(lastEvent.type?.includes('Failed') ? 'red' : 'green', lastEvent.type)}`)
      break
    }

    if (!follow) break

    // Wait before polling again
    await new Promise(resolve => setTimeout(resolve, 2000))
  }
}
