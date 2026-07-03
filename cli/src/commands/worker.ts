import { api, color, printJSON } from '../api'

export async function workerList(json: boolean) {
  const { status, data } = await api('GET', '/api/v1/workers')

  if (status !== 200) {
    console.error(`${color('red', '❌')} Failed to list workers (HTTP ${status})`)
    process.exit(1)
  }

  const workers = (data as any).data || []

  if (json) {
    printJSON(workers)
    return
  }

  if (!workers.length) {
    console.log(`${color('gray', 'No Python workers registered (Elixir-native only).')}`)
    return
  }

  console.log(`\n${color('bold', 'Python Workers:')}`)
  console.log('═'.repeat(60))
  for (const w of workers) {
    console.log(`  ${color('purple', '•')} ${w.id} ${color('gray', `@ ${w.url}`)}`)
    console.log(`    ${w.workflow_count} workflows`)
  }
  console.log(`\n${color('gray', `Total: ${workers.length} workers`)}`)
}
