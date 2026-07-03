import { color, loadConfig } from '../api'
import * as fs from 'fs'
import * as path from 'path'
import * as os from 'os'

export async function login() {
  const config = loadConfig()
  const configDir = path.join(os.homedir(), '.cerebelum')
  const configFile = path.join(configDir, 'config.json')

  console.log(`\n${color('cyan', '🔐 Cerebelum Login')}`)
  console.log('═'.repeat(50))
  console.log(`\n  ${color('bold', '1.')} Open your browser and login at:`)
  console.log(`     ${color('green', `${config.authUrl}/login`)}`)
  console.log(`\n  ${color('bold', '2.')} Create a Personal Access Token at:`)
  console.log(`     ${color('green', `${config.authUrl}/settings/tokens`)}`)
  console.log(`\n  ${color('bold', '3.')} Run: ${color('green', 'cerebelum login --token <your_token>')}`)
  console.log(`\n  ${color('bold', '4.')} Or set: ${color('green', 'export CEREBELUM_API_KEY=<your_token>')}`)
  console.log('')
}

export async function loginWithToken(token: string) {
  const configDir = path.join(os.homedir(), '.cerebelum')
  const configFile = path.join(configDir, 'config.json')

  if (!fs.existsSync(configDir)) {
    fs.mkdirSync(configDir, { recursive: true })
  }

  let config: Record<string, string> = {}
  try {
    config = JSON.parse(fs.readFileSync(configFile, 'utf-8'))
  } catch {}

  config.apiKey = token
  fs.writeFileSync(configFile, JSON.stringify(config, null, 2))

  console.log(`${color('green', '✅')} Token saved to ${configFile}`)
  console.log(`   Run ${color('green', 'cerebelum doctor')} to verify`)
}
