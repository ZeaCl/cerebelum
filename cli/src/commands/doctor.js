/**
 * cerebelum doctor — Full integration diagnostic.
 *
 * Checks: connectivity, auth, workflows, executions, workers.
 */
import { loadConfig, getClient } from '../lib/client.js';
import { zeaFetch } from '../lib/http.js';
import chalk from 'chalk';

let passes = 0;
let warnings = 0;
let failures = 0;

function pass(msg) { passes++; console.log(`   ✅ ${msg}`); }
function warn(msg) { warnings++; console.log(`   ⚠️  ${msg}`); }
function fail(msg) { failures++; console.log(`   ❌ ${msg}`); }

export function register(program) {
  program.command('doctor')
    .description('Full integration diagnostic: connectivity, auth, workflows, workers')
    .action(async () => {
      let apiUrl = 'http://cerebelum.zea.localhost';
      try {
        const config = await loadConfig();
        apiUrl = config.cerebelumUrl || apiUrl;
      } catch {}
      apiUrl = process.env.CEREBELUM_API_URL || process.env.CEREBELUM_URL || apiUrl;

      console.log('');
      console.log(chalk.cyan(`🩺 Cerebelum Doctor — ${apiUrl}`));
      console.log('');

      // ── 1. Connectivity ──────────────────────────
      console.log('── Connectivity ────────────────────────────');
      let healthData = null;
      try {
        const resp = await zeaFetch(`${apiUrl}/health`);
        if (resp.ok) {
          healthData = await resp.json();
          pass(`Cerebelum reachable (v${healthData.version || '?.?.?'})`);

          if (healthData.services) {
            if (healthData.services.database) {
              if (healthData.services.database === 'ok') pass('Database: ok');
              else fail(`Database: ${healthData.services.database}`);
            }
            if (healthData.services.grpc) {
              if (healthData.services.grpc === 'ok') pass('gRPC: ok');
              else warn(`gRPC: ${healthData.services.grpc}`);
            }
          }
        } else {
          fail(`Cerebelum returned HTTP ${resp.status}`);
        }
      } catch (e) {
        if (e.code === 'ENOTFOUND' || e.code === 'ECONNREFUSED') {
          fail(`Cannot reach ${apiUrl}`);
          console.log('');
          console.log(chalk.dim('   💡 Try: docker compose up -d'));
        } else {
          fail(`Connection error: ${e.message}`);
        }
      }

      if (!healthData) {
        printSummary();
        return;
      }

      // ── 2. Authentication ────────────────────────
      console.log('── Authentication ──────────────────────────');
      let client = null;
      try {
        client = await getClient(true); // allow unauthenticated for health checks
        if (client.token) {
          pass('Token found in config');

          try {
            const userResp = await zeaFetch(`${client.authUrl}/oauth/userinfo`, {
              headers: client.headers,
            });
            if (userResp.ok) {
              const userinfo = await userResp.json();
              pass(`Authenticated as ${userinfo.email}`);
            } else if (userResp.status === 401) {
              warn('Token expired or invalid');
              console.log(chalk.dim('   💡 Run: zea login'));
            }
          } catch {
            warn('Could not verify token with auth server');
          }
        } else {
          warn('No token found');
          console.log(chalk.dim('   💡 Run: zea login'));
        }
      } catch {
        warn('No token found');
        console.log(chalk.dim('   💡 Run: zea login'));
      }

      // ── 3. Workflows ─────────────────────────────
      console.log('── Workflows ───────────────────────────────');
      try {
        const headers = client?.headers || { 'Content-Type': 'application/json' };
        const wfResp = await zeaFetch(`${apiUrl}/api/v1/workflows`, { headers });
        if (wfResp.ok) {
          const wfData = await wfResp.json();
          const workflows = wfData.data || [];
          pass(`${workflows.length} workflows registered`);
          for (const wf of workflows.slice(0, 5)) {
            const label = wf.label || wf.id;
            const steps = (wf.timeline || wf.steps || []).length;
            console.log(chalk.dim(`     • ${label} (${steps} steps)`));
          }
          if (workflows.length > 5) {
            console.log(chalk.dim(`     ... and ${workflows.length - 5} more`));
          }
        } else {
          warn(`Workflows endpoint returned HTTP ${wfResp.status}`);
        }
      } catch {
        warn('Could not fetch workflows');
      }

      // ── 4. Workers ───────────────────────────────
      console.log('── Workers ─────────────────────────────────');
      try {
        const headers = client?.headers || { 'Content-Type': 'application/json' };
        const wResp = await zeaFetch(`${apiUrl}/api/v1/workers`, { headers });
        if (wResp.ok) {
          const wData = await wResp.json();
          const workers = wData.data || [];
          pass(`${workers.length} workers registered`);
          for (const w of workers) {
            console.log(chalk.dim(`     • ${w.id} @ ${w.url || 'local'}`));
          }
        } else {
          warn(`Workers endpoint returned HTTP ${wResp.status}`);
        }
      } catch {
        warn('Could not fetch workers');
      }

      // ── 5. Executions ────────────────────────────
      console.log('── Executions ──────────────────────────────');
      try {
        const headers = client?.headers || { 'Content-Type': 'application/json' };
        const execResp = await zeaFetch(`${apiUrl}/api/v1/executions`, { headers });
        if (execResp.ok) {
          const execData = await execResp.json();
          const executions = execData.data || [];
          pass(`${executions.length} executions in EventStore`);

          const running = executions.filter(e =>
            e.status === 'running' || e.status === 'waiting_for_approval'
          );
          if (running.length > 0) {
            console.log(chalk.dim(`     ${running.length} active`));
          }
        } else if (execResp.status === 401) {
          warn('Executions require authentication');
          console.log(chalk.dim('   💡 Run: zea login'));
        } else {
          warn(`Executions endpoint returned HTTP ${execResp.status}`);
        }
      } catch {
        warn('Could not fetch executions');
      }

      printSummary();
    });
}

function printSummary() {
  console.log('');
  console.log('── Summary ──────────────────────────────────');
  const total = passes + warnings + failures;
  console.log(`   ✅ ${passes}  ⚠️  ${warnings}  ❌ ${failures}  (${total} checks)`);

  if (failures === 0 && warnings === 0) {
    console.log('');
    console.log(chalk.green('   🎉 All systems operational!'));
    process.exit(0);
  } else if (failures > 0) {
    console.log('');
    console.log(chalk.red('   🔴 Some checks failed. Review the ❌ items above.'));
    process.exit(1);
  } else {
    console.log('');
    console.log(chalk.yellow('   🟡 Minor warnings — system is functional.'));
    process.exit(0);
  }
}
