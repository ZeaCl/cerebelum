/**
 * cerebelum execution — Manage workflow executions.
 *
 * Commands:
 *   execution list             List executions [--status] [--workflow] [--limit]
 *   execution status <id>      Show execution status
 *   execution events <id>      Show event timeline
 *   execution stop <id>        Stop a running execution
 *   execution resume <id>      Resume a paused execution
 *   execution approve <id>     Approve a HITL step [--response '{"decision":"approved"}']
 */
import { getClient } from '../lib/client.js';
import { zeaFetch } from '../lib/http.js';
import { getGlobalOpts, display } from '../lib/globals.js';
import { handleError } from '../lib/errors.js';
import chalk from 'chalk';

export function register(program) {
  const execCmd = program.command('execution').description('Manage workflow executions');

  execCmd.command('list')
    .description('List executions with optional filters')
    .option('--status <status>', 'Filter by status: running, completed, failed, waiting_for_approval')
    .option('--workflow <name>', 'Filter by workflow name')
    .option('--limit <n>', 'Max results', '50')
    .option('--offset <n>', 'Pagination offset', '0')
    .action(async (options) => {
      const opts = getGlobalOpts();
      try {
        const client = await getClient();
        const params = new URLSearchParams();
        if (options.status) params.set('status', options.status);
        if (options.workflow) params.set('workflow', options.workflow);
        if (options.limit) params.set('limit', options.limit);
        if (options.offset) params.set('offset', options.offset);

        const query = params.toString() ? '?' + params.toString() : '';
        const resp = await zeaFetch(`${client.apiUrl}/api/v1/executions${query}`, {
          headers: client.headers,
        });

        if (!resp.ok) {
          throw Object.assign(new Error(`HTTP ${resp.status}`), { status: resp.status });
        }

        const data = await resp.json();
        const executions = data.executions || data.data || [];

        if (opts.output === 'json') {
          display({ executions, total: data.total }, opts);
          return;
        }

        if (!executions.length) {
          console.log(chalk.dim('\nNo executions found.'));
          if (options.status) console.log(chalk.dim(`   Filter: status=${options.status}`));
          if (options.workflow) console.log(chalk.dim(`   Filter: workflow=${options.workflow}`));
          console.log('');
          return;
        }

        console.log(chalk.cyan(`\n📊 Executions (${data.total || executions.length} total)\n`));

        for (const exec of executions) {
          const statusColor =
            exec.status === 'completed' ? chalk.green :
            exec.status === 'failed' ? chalk.red :
            exec.status === 'running' ? chalk.cyan :
            exec.status === 'waiting_for_approval' ? chalk.yellow : chalk.gray;

          const id = (exec.execution_id || exec.id || '').slice(0, 12);
          const wf = (exec.workflow || '—').replace('Elixir.', '');
          console.log(`  ${statusColor('●')} ${chalk.dim(id)}...  ${statusColor(exec.status.padEnd(20))}  ${wf}  ${chalk.dim(`(${exec.events_count || '?'} events)`)}`);
        }
        console.log('');
      } catch (e) {
        handleError(e);
      }
    });

  execCmd.command('status <id>')
    .description('Show execution status')
    .action(async (id) => {
      const opts = getGlobalOpts();
      try {
        const client = await getClient();
        const resp = await zeaFetch(`${client.apiUrl}/api/v1/executions/${encodeURIComponent(id)}`, {
          headers: client.headers,
        });

        if (resp.status === 404) {
          console.error(chalk.red(`❌ Execution not found: ${id}`));
          process.exit(1);
        }
        if (!resp.ok) {
          throw Object.assign(new Error(`HTTP ${resp.status}`), { status: resp.status });
        }

        const data = await resp.json();
        const exec = data.data || data;

        if (opts.output === 'json') {
          display(exec, opts);
          return;
        }

        const statusColor =
          exec.status === 'completed' ? chalk.green :
          exec.status === 'failed' || exec.status === 'stopped' ? chalk.red :
          exec.status === 'waiting_for_approval' ? chalk.yellow :
          exec.status === 'running' ? chalk.cyan : chalk.gray;

        const progress = exec.total_visible_steps > 0
          ? ` (${exec.visible_step || '?'}/${exec.total_visible_steps})`
          : '';

        console.log(chalk.cyan(`\n📊 Execution ${chalk.dim(id.slice(0, 12) + '...')}`));
        console.log('═'.repeat(55));
        console.log(`  Status:   ${statusColor((exec.status || 'unknown').toUpperCase())}`);
        console.log(`  Workflow: ${exec.workflow_module?.replace('Elixir.', '') || exec.workflow_id || '—'}`);
        console.log(`  Step:     ${exec.current_step_label || '—'}${progress}`);
        console.log(`  Events:   ${exec.events_applied || '?'}`);
        if (exec.started_at) console.log(`  Started:  ${new Date(exec.started_at).toLocaleString()}`);
        if (exec.duration_ms) console.log(`  Duration: ${exec.duration_ms}ms`);

        if (exec.error) {
          console.log(`\n  ${chalk.red('Error:')}`);
          console.log(chalk.dim(`  ${JSON.stringify(exec.error).slice(0, 200)}`));
        }

        if (exec.status === 'waiting_for_approval') {
          console.log(`\n  ${chalk.yellow('⏸️  Waiting for human approval')}`);
          console.log(chalk.dim(`  Run: zea cerebelum execution approve ${id}`));
        }

        console.log('');
      } catch (e) {
        handleError(e);
      }
    });

  execCmd.command('events <id>')
    .description('Show execution event timeline')
    .action(async (id) => {
      const opts = getGlobalOpts();
      try {
        const client = await getClient();
        const resp = await zeaFetch(`${client.apiUrl}/api/v1/executions/${encodeURIComponent(id)}/events`, {
          headers: client.headers,
        });

        if (!resp.ok) {
          throw Object.assign(new Error(`HTTP ${resp.status}`), { status: resp.status });
        }

        const data = await resp.json();
        const events = data.data || data.events || [];

        if (opts.output === 'json') {
          display(events, opts);
          return;
        }

        console.log(chalk.cyan(`\n📜 Event Timeline ${chalk.dim(`(${events.length} events)`)}`));
        console.log('═'.repeat(60));

        for (const ev of events) {
          const eventColor =
            ev.type?.includes('Completed') || ev.type?.includes('Resumed') ? chalk.green :
            ev.type?.includes('Failed') ? chalk.red :
            ev.type?.includes('Paused') || ev.type?.includes('Waiting') ? chalk.yellow :
            ev.type?.includes('Started') ? chalk.cyan : chalk.magenta;

          const time = ev.timestamp ? new Date(ev.timestamp).toLocaleTimeString() : '';
          console.log(`  ${chalk.dim(`[v${ev.version}]`)} ${eventColor(ev.type)} ${chalk.dim(time)}`);

          if (ev.data && Object.keys(ev.data).length > 0) {
            const relevant = { ...ev.data };
            delete relevant.workflow_module;
            delete relevant.execution_id;
            delete relevant.timestamp;
            if (Object.keys(relevant).length > 0) {
              console.log(`    ${chalk.dim(JSON.stringify(relevant).slice(0, 100))}`);
            }
          }
        }
        console.log('');
      } catch (e) {
        handleError(e);
      }
    });

  execCmd.command('stop <id>')
    .description('Stop a running execution')
    .action(async (id) => {
      const opts = getGlobalOpts();
      try {
        const client = await getClient();

        if (opts.dryRun) {
          console.log(chalk.yellow(`⚠️  DRY RUN — would stop execution ${id}`));
          return;
        }

        const resp = await zeaFetch(`${client.apiUrl}/api/v1/executions/${encodeURIComponent(id)}/stop`, {
          method: 'POST',
          headers: client.headers,
        });

        if (!resp.ok) {
          throw Object.assign(new Error(`HTTP ${resp.status}`), { status: resp.status });
        }

        const data = await resp.json();
        const result = data.data || data;

        if (opts.output === 'json') {
          display(result, opts);
        } else {
          console.log(chalk.green(`✅ Execution stopped: ${result.id || id}`));
        }
      } catch (e) {
        handleError(e);
      }
    });

  execCmd.command('resume <id>')
    .description('Resume a paused execution')
    .action(async (id) => {
      const opts = getGlobalOpts();
      try {
        const client = await getClient();

        if (opts.dryRun) {
          console.log(chalk.yellow(`⚠️  DRY RUN — would resume execution ${id}`));
          return;
        }

        const resp = await zeaFetch(`${client.apiUrl}/api/v1/executions/${encodeURIComponent(id)}/resume`, {
          method: 'POST',
          headers: client.headers,
        });

        if (resp.status === 409) {
          console.log(chalk.yellow('⚠️  Already running'));
          return;
        }
        if (!resp.ok) {
          const errData = await resp.json().catch(() => ({}));
          throw Object.assign(
            new Error(errData.error || `HTTP ${resp.status}`),
            { status: resp.status }
          );
        }

        const data = await resp.json();
        const result = data.data || data;

        if (opts.output === 'json') {
          display(result, opts);
        } else {
          console.log(chalk.green(`✅ Execution resumed: ${result.status || 'running'}`));
        }
      } catch (e) {
        handleError(e);
      }
    });

  execCmd.command('approve <id>')
    .description('Approve a HITL (human-in-the-loop) step')
    .option('--response <json>', 'Approval response data', '{"decision":"approved"}')
    .action(async (id, options) => {
      const opts = getGlobalOpts();
      let response = { decision: 'approved' };
      try {
        response = JSON.parse(options.response);
      } catch {
        console.error(chalk.red(`❌ Invalid JSON: ${options.response}`));
        process.exit(1);
      }

      try {
        const client = await getClient();

        if (opts.dryRun) {
          console.log(chalk.yellow(`⚠️  DRY RUN — would approve execution ${id}`));
          console.log(`   Response: ${JSON.stringify(response)}`);
          return;
        }

        const resp = await zeaFetch(`${client.apiUrl}/api/v1/executions/${encodeURIComponent(id)}/approve`, {
          method: 'POST',
          headers: client.headers,
          body: JSON.stringify({ response }),
        });

        if (!resp.ok) {
          const errData = await resp.json().catch(() => ({}));
          throw Object.assign(
            new Error(errData.error || `HTTP ${resp.status}`),
            { status: resp.status }
          );
        }

        const data = await resp.json();
        const result = data.data || data;

        if (opts.output === 'json') {
          display(result, opts);
        } else {
          console.log(chalk.green(`✅ Approved — status: ${result.status || 'resumed'}`));
        }
      } catch (e) {
        handleError(e);
      }
    });
}
