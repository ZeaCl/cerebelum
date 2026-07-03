import { api, color, printJSON } from '../api'

export async function doctorRun(_json: boolean) {
  console.log(`\n${color('cyan', '🩺 Cerebelum Doctor')}`)
  console.log('═'.repeat(50))

  // 1. HTTP Health
  {
    const { status, data } = await api('GET', '/health')
    if (status === 200 && (data as any).status === 'ok') {
      const d = data as any
      console.log(`  ${color('green', '✅')} HTTP health: ${d.version} (DB: ${d.services?.database}, gRPC: ${d.services?.grpc})`)
    } else {
      console.log(`  ${color('red', '❌')} HTTP health: ${status}`)
    }
  }

  // 2. Workflows
  {
    const { status, data } = await api('GET', '/api/v1/workflows')
    if (status === 200) {
      const wfCount = ((data as any).data || []).length
      console.log(`  ${color('green', '✅')} Workflows: ${wfCount} registered`)
    } else {
      console.log(`  ${color('red', '❌')} Workflows: HTTP ${status}`)
    }
  }

  // 3. Executions
  {
    const { status, data } = await api('GET', '/api/v1/executions')
    if (status === 200) {
      const execCount = ((data as any).data || []).length
      console.log(`  ${color('green', '✅')} Executions: ${execCount} in EventStore`)
    } else {
      console.log(`  ${color('yellow', '⚠️')}  Executions: auth required (HTTP ${status})`)
    }
  }

  // 4. Workers
  {
    const { status, data } = await api('GET', '/api/v1/workers')
    if (status === 200) {
      const wCount = ((data as any).data || []).length
      console.log(`  ${color('green', '✅')} Workers: ${wCount} registered`)
    } else {
      console.log(`  ${color('yellow', '⚠️')}  Workers: auth required (HTTP ${status})`)
    }
  }

  // 5. Auth
  {
    const { status } = await api('GET', '/api/v1/executions', undefined, 'invalid')
    if (status === 401) {
      console.log(`  ${color('green', '✅')} Auth: rejects invalid tokens (401)`)
    } else {
      console.log(`  ${color('yellow', '⚠️')}  Auth: unexpected response ${status}`)
    }
  }

  console.log(`\n  ${color('green', 'Doctor complete.')}`)
  console.log(`  API: ${process.env.CEREBELUM_API_URL || 'http://localhost:4000'}`)
  console.log('')
}
