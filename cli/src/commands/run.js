/**
 * cerebelum run — Execute a local workflow.py end-to-end.
 *
 * Flow:
 *   1. Verify auth (read from shared config, no login)
 *   2. Deploy blueprint if needed
 *   3. Execute the workflow
 *   4. Stream logs
 *
 * This is the "zero-friction" path for local development.
 * For advanced control, use individual commands (deploy, workflow run, logs).
 */
import fs from 'fs';
import path from 'path';
import { getClient } from '../lib/client.js';
import { zeaFetch } from '../lib/http.js';
import { getGlobalOpts } from '../lib/globals.js';
import { handleError } from '../lib/errors.js';
import chalk from 'chalk';

export function register(program) {
  program.command('run [file]')
    .description('Run a local workflow.py end-to-end (deploy + execute + logs)')
    .option('--inputs <json>', 'JSON inputs for the workflow', '{}')
    .option('--no-follow', 'Do not stream logs after starting')
    .action(async (file, options) => {
      const opts = getGlobalOpts();
      const wfFile = file || 'workflow.py';

      if (!fs.existsSync(wfFile)) {
        console.error(chalk.red(`\n❌ File not found: ${wfFile}`));
        console.log(chalk.dim(`   Usage: zea cerebelum run [file.py]`));
        console.log(chalk.dim(`   Default: workflow.py in current directory`));
        process.exit(1);
      }

      const startTime = Date.now();
      console.log(chalk.cyan(`\n🧠 Cerebelum Run — ${wfFile}\n`));

      // 1. Auth
      let client;
      try {
        client = await getClient();
        console.log(`  ${chalk.green('✅')} Auth — ${chalk.dim('JWT presente')}`);
      } catch {
        console.log(`  ${chalk.red('❌')} Auth — no autenticado`);
        console.log(chalk.dim('     Run: zea login'));
        process.exit(1);
      }

      // 2. Read + deploy
      const code = fs.readFileSync(wfFile, 'utf-8');
      const wfName = extractWorkflowName(code) || path.basename(wfFile, '.py');

      console.log(`  ${chalk.bold('→')} Deploying ${chalk.bold(wfName)}...`);

      try {
        const deployResp = await zeaFetch(`${client.apiUrl}/api/v1/workflows/deploy`, {
          method: 'POST',
          headers: client.headers,
          body: JSON.stringify({ name: wfName, module: wfName, code, language: 'python' }),
        });

        if (!deployResp.ok) {
          const err = await deployResp.json().catch(() => ({}));
          console.log(`  ${chalk.red('❌')} Deploy failed: ${err.error || `HTTP ${deployResp.status}`}`);
          process.exit(1);
        }
        console.log(`  ${chalk.green('✅')} Blueprint deployed`);
      } catch (e) {
        console.log(`  ${chalk.red('❌')} Deploy failed: ${e.message}`);
        process.exit(1);
      }

      // 3. Parse inputs
      let inputs = {};
      try {
        inputs = JSON.parse(options.inputs);
      } catch {
        console.error(chalk.red(`❌ Invalid JSON inputs: ${options.inputs}`));
        process.exit(1);
      }

      // 4. Execute
      console.log(`  ${chalk.bold('→')} Executing...\n`);

      let execId;
      try {
        const execResp = await zeaFetch(`${client.apiUrl}/api/v1/executions`, {
          method: 'POST',
          headers: client.headers,
          body: JSON.stringify({ workflow: wfName, input: inputs }),
        });

        if (!execResp.ok) {
          const err = await execResp.json().catch(() => ({}));
          console.log(`  ${chalk.red('❌')} Execution failed: ${err.error || `HTTP ${execResp.status}`}`);
          process.exit(1);
        }

        const data = await execResp.json();
        execId = data.data?.id || data.execution_id;
        console.log(`  ${chalk.green('🚀')} Execution started: ${chalk.bold(execId)}`);
      } catch (e) {
        console.log(`  ${chalk.red('❌')} Execute failed: ${e.message}`);
        process.exit(1);
      }

      // 5. Stream logs
      if (!execId) {
        console.log(chalk.yellow('⚠️  Could not get execution ID'));
        process.exit(1);
      }

      let lastVersion = -1;
      const pollInterval = 1500;

      while (true) {
        await sleep(pollInterval);

        try {
          const eventsResp = await zeaFetch(`${client.apiUrl}/api/v1/executions/${encodeURIComponent(execId)}/events`, {
            headers: client.headers,
          });

          if (!eventsResp.ok) break;

          const eventsData = await eventsResp.json();
          const events = eventsData.events || eventsData.data || [];
          const newEvents = events.filter((e) => (e.version ?? 0) > lastVersion);

          for (const ev of newEvents) {
            const time = ev.timestamp ? new Date(ev.timestamp).toLocaleTimeString() : '';
            const eventColor =
              ev.type?.includes('Completed') || ev.type?.includes('Executed') || ev.type?.includes('Resumed') ? chalk.green :
              ev.type?.includes('Failed') ? chalk.red :
              ev.type?.includes('Started') ? chalk.cyan :
              ev.type?.includes('Paused') || ev.type?.includes('Waiting') ? chalk.yellow : chalk.gray;

            const stepInfo = ev.data?.step_name ? ` ${chalk.magenta(`[${ev.data.step_name}]`)}` : '';
            process.stdout.write(`  ${chalk.dim(`[${time}]`)} ${eventColor(ev.type)}${stepInfo}`);

            const output = ev.data?.result || ev.data?.final_result || ev.data?.output;
            if (output && typeof output === 'object' && Object.keys(output).length > 0) {
              const vals = Object.entries(output)
                .map(([k, v]) => `${k}=${typeof v === 'string' ? v.slice(0, 40) : v}`)
                .join(' · ');
              process.stdout.write(` ${chalk.dim(`→ ${vals}`)}`);
            }
            process.stdout.write('\n');
            lastVersion = Math.max(lastVersion, ev.version);
          }

          const lastEvent = events[events.length - 1];
          if (lastEvent && ['ExecutionCompleted', 'ExecutionFailed', 'ExecutionCancelled'].some(
            (t) => lastEvent.type?.includes(t)
          )) {
            const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);
            const icon = lastEvent.type?.includes('Failed') ? '❌' : '✅';
            console.log(`\n  ${icon} ${lastEvent.type}`);
            console.log(`  ${chalk.dim(`⏱️  ${elapsed}s`)}`);
            console.log('');
            break;
          }

          if (options.noFollow) {
            console.log(`\n  ${chalk.dim('Stream logs:')} zea cerebelum logs ${execId} --follow\n`);
            break;
          }
        } catch {
          if (!options.noFollow) {
            // Network hiccup, keep polling
            process.stdout.write(chalk.dim('.'));
          } else {
            break;
          }
        }
      }
    });
}

function extractWorkflowName(code) {
  const match = code.match(/@workflow\s*\n\s*(?:async\s+)?def\s+(\w+)/);
  if (match) return match[1];
  const classMatch = code.match(/class\s+(\w+).*Workflow/);
  if (classMatch) return classMatch[1];
  return null;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
