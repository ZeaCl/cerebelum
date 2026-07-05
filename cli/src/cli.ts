import { color, printJSON } from './api'
import { login, loginWithToken } from './commands/login'
import { smartRun } from './commands/smart-run'
import { showStatus, showLastLogs } from './commands/status'
import { deployWorkflow } from './commands/deploy'
import { executionLogs } from './commands/logs'
import { workflowList, workflowShow, workflowRun } from './commands/workflow'
import { executionStatus, executionEvents, executionStop, executionResume, executionApprove } from './commands/execution'
import { workerList } from './commands/worker'
import { doctorRun } from './commands/doctor'

const USAGE = `
${color('cyan', '🧠 Cerebelum')} ${color('gray', '— Deterministic Workflow Orchestration')}

${color('bold', 'Usage:')}
  ${color('green', 'npx @zea.cl/cerebelum-cli')} <command> [args...]

${color('bold', 'Commands:')}
  ${color('green', 'login')}                    Authenticate with Thalamus (ZEA)
  ${color('green', 'deploy')} <file>            Deploy workflow blueprint
  ${color('green', 'workflow list')}            List registered workflows
  ${color('green', 'workflow show')} <id>       Show workflow details
  ${color('green', 'run')} <module>             Execute workflow [--inputs '{...}']
  ${color('green', 'logs')} <id>               Get execution logs [--follow]
  ${color('green', 'execution status')} <id>    Get execution status
  ${color('green', 'execution events')} <id>    Get event timeline
  ${color('green', 'execution stop')} <id>      Stop running execution
  ${color('green', 'execution resume')} <id>    Resume paused execution
  ${color('green', 'execution approve')} <id>   Approve HITL step
  ${color('green', 'worker list')}              List Python workers
  ${color('green', 'doctor')}                   Run health checks

${color('bold', 'Options:')}
  --json                    Machine-readable JSON output
  --follow, -f              Follow logs in real-time
  --token <token>           API token for login
  --inputs '{...}'          JSON inputs for workflow run
  --help                    Show this help

${color('bold', 'Environment:')}
  CEREBELUM_API_URL         API base URL (default: https://cerebelum.zea.cl)
  CEREBELUM_API_KEY         API key for authenticated endpoints
`

export async function main(argv: string[]) {
  const jsonMode = argv.includes('--json')
  const args = argv.filter(a => a !== '--json')

  if (args.length === 0 || args[0] === '--help' || args[0] === '-h') {
    console.log(USAGE)
    return
  }

  const [cmd, sub, ...rest] = args

  const parseOpts = () => {
    const opts: Record<string, string> = {}
    for (let i = 0; i < rest.length; i++) {
      if (rest[i].startsWith('--') && rest[i + 1] && !rest[i + 1].startsWith('--')) {
        opts[rest[i].slice(2)] = rest[++i]
      }
    }
    return opts
  }

  switch (cmd) {
    case 'login': {
      const opts = parseOpts()
      if (opts.token) {
        return loginWithToken(opts.token)
      }
      return login()
    }
    case 'deploy':
      return deployWorkflow(sub, jsonMode)
    case 'run': {
      return smartRun(rest, jsonMode)
    }
    case 'status':
      return showStatus()
    case 'logs': {
      if (!sub) return showLastLogs(rest.includes('--follow') || rest.includes('-f'))
      const logOpts = parseOpts()
      return executionLogs(sub, rest.includes('--follow') || rest.includes('-f') || args.includes('--follow') || args.includes('-f'), jsonMode)
    }
    case 'workflow': {
      switch (sub) {
        case 'list':
          return workflowList(jsonMode)
        case 'show':
          return workflowShow(rest[0], jsonMode)
        case 'run': {
          const opts = parseOpts()
          return workflowRun(sub, rest[0], opts.inputs || '{}', jsonMode)
        }
        default:
          // cerebelum workflow run <module> (sub IS the module)
          const opts2 = parseOpts()
          return workflowRun('run', sub, opts2.inputs || '{}', jsonMode)
      }
    }
    case 'execution': {
      switch (sub) {
        case 'status': return executionStatus(rest[0], jsonMode)
        case 'events': return executionEvents(rest[0], jsonMode)
        case 'stop': return executionStop(rest[0], jsonMode)
        case 'resume': return executionResume(rest[0], jsonMode)
        case 'approve': {
          const opts = parseOpts()
          return executionApprove(rest[0], opts.response || '{}', jsonMode)
        }
        default:
          console.log(USAGE)
      }
      break
    }
    case 'worker':
      if (sub === 'list') return workerList(jsonMode)
      console.log(USAGE)
      break
    case 'doctor':
      return doctorRun(jsonMode)
    default:
      console.log(USAGE)
  }
}
