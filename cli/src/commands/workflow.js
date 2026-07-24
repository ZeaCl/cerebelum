/**
 * cerebelum workflow — Manage workflow blueprints.
 *
 * Commands:
 *   workflow list               List registered workflows
 *   workflow show <id>          Show workflow details
 *   workflow code <id>          Show workflow source code
 *   workflow run <module>       Execute a workflow [--inputs '{"key":"val"}']
 */
import { getClient } from '../lib/client.js';
import { zeaFetch } from '../lib/http.js';
import { getGlobalOpts, display } from '../lib/globals.js';
import { handleError } from '../lib/errors.js';
import chalk from 'chalk';

export function register(program) {
  const workflowCmd = program.command('workflow').description('Manage workflow blueprints');

  workflowCmd.command('list')
    .description('List registered workflows')
    .action(async () => {
      const opts = getGlobalOpts();
      try {
        const client = await getClient(true);
        const resp = await zeaFetch(`${client.apiUrl}/api/v1/workflows`, {
          headers: client.headers,
        });

        if (!resp.ok) {
          throw Object.assign(new Error(`HTTP ${resp.status}`), { status: resp.status });
        }

        const data = await resp.json();
        const workflows = data.data || [];

        if (opts.output === 'json') {
          display(workflows, opts);
          return;
        }

        if (!workflows.length) {
          console.log(chalk.dim('No workflows registered.'));
          console.log(chalk.dim('   Deploy one: zea cerebelum deploy workflow.py'));
          return;
        }

        console.log(chalk.cyan(`\n📋 Available Workflows (${workflows.length})\n`));
        for (const wf of workflows) {
          const label = wf.label || wf.id;
          const version = wf.version || '?';
          const timeline = wf.timeline || (wf.steps || []).filter((s) => !s.hidden).map((s) => s.label);
          const steps = Array.isArray(timeline) ? timeline.join(` ${chalk.dim('→')} `) : 'no steps';

          console.log(`  ${chalk.magenta('•')} ${chalk.bold(label)} ${chalk.dim(`(v${version})`)}`);
          console.log(`    ${chalk.dim(wf.id)}`);
          console.log(`    ${steps}`);
        }
        console.log('');
      } catch (e) {
        handleError(e);
      }
    });

  workflowCmd.command('show <id>')
    .description('Show workflow details')
    .action(async (id) => {
      const opts = getGlobalOpts();
      try {
        const client = await getClient(true);
        const resp = await zeaFetch(`${client.apiUrl}/api/v1/workflows/${encodeURIComponent(id)}`, {
          headers: client.headers,
        });

        if (resp.status === 404) {
          console.error(chalk.red(`❌ Workflow not found: ${id}`));
          process.exit(1);
        }
        if (!resp.ok) {
          throw Object.assign(new Error(`HTTP ${resp.status}`), { status: resp.status });
        }

        const data = await resp.json();
        const wf = data.data || data;

        if (opts.output === 'json') {
          display(wf, opts);
          return;
        }

        const steps = wf.steps || [];
        const visible = steps.filter((s) => !s.hidden);

        console.log(chalk.cyan(`\n📋 ${chalk.bold(wf.label || id)}`));
        console.log('═'.repeat(50));
        console.log(`  ID:      ${chalk.dim(wf.id)}`);
        console.log(`  Version: ${wf.version || '?'}`);
        console.log(`  Worker:  ${wf.worker_url || chalk.dim('Elixir-native')}`);
        console.log(`\n  Steps:`);
        for (const s of visible) {
          const hidden = s.hidden ? ` ${chalk.dim('(hidden)')}` : '';
          console.log(`    ${chalk.magenta('→')} ${s.label} ${chalk.dim(`(${s.name})`)}${hidden}`);
        }
        console.log('');
      } catch (e) {
        handleError(e);
      }
    });

  workflowCmd.command('code <id>')
    .description('Show workflow source code')
    .action(async (id) => {
      const opts = getGlobalOpts();
      try {
        const client = await getClient(true);
        const resp = await zeaFetch(`${client.apiUrl}/api/v1/workflows/${encodeURIComponent(id)}/code`, {
          headers: client.headers,
        });

        if (resp.status === 404) {
          console.error(chalk.red(`❌ Workflow not found: ${id}`));
          process.exit(1);
        }
        if (!resp.ok) {
          throw Object.assign(new Error(`HTTP ${resp.status}`), { status: resp.status });
        }

        const data = await resp.json();

        if (opts.output === 'json') {
          display(data, opts);
          return;
        }

        const code = data.code || data.data?.code;
        if (code) {
          console.log(chalk.cyan(`\n📝 Source: ${chalk.bold(id)}\n`));
          console.log(chalk.dim(code));
          console.log('');
        } else {
          console.log(chalk.yellow(`⚠️  Source code not available for ${id}`));
          if (data.error) console.log(chalk.dim(`   ${data.error}`));
        }
      } catch (e) {
        handleError(e);
      }
    });

  workflowCmd.command('run <module>')
    .description('Execute a workflow')
    .option('--inputs <json>', 'JSON inputs for the workflow', '{}')
    .action(async (module, options) => {
      const opts = getGlobalOpts();
      let inputs = {};
      try {
        inputs = JSON.parse(options.inputs);
      } catch {
        console.error(chalk.red(`❌ Invalid JSON inputs: ${options.inputs}`));
        process.exit(1);
      }

      try {
        const client = await getClient();
        const body = { workflow: module, input: inputs };

        if (opts.dryRun) {
          console.log(chalk.yellow('⚠️  DRY RUN — would execute:'));
          console.log(`   POST ${client.apiUrl}/api/v1/executions`);
          console.log(`   Body: ${JSON.stringify(body, null, 2)}`);
          return;
        }

        const resp = await zeaFetch(`${client.apiUrl}/api/v1/executions`, {
          method: 'POST',
          headers: client.headers,
          body: JSON.stringify(body),
        });

        if (!resp.ok) {
          const errData = await resp.json().catch(() => ({}));
          throw Object.assign(
            new Error(errData.error || `HTTP ${resp.status}`),
            { status: resp.status }
          );
        }

        const data = await resp.json();
        const exec = data.data || data;

        if (opts.output === 'json') {
          display(exec, opts);
          return;
        }

        const statusColor =
          exec.status === 'completed' ? chalk.green :
          exec.status === 'failed' ? chalk.red :
          exec.status === 'running' ? chalk.cyan :
          chalk.yellow;

        console.log(chalk.green(`\n✅ Workflow started!`));
        console.log(`   ID:     ${chalk.bold(exec.id || exec.execution_id)}`);
        console.log(`   Status: ${statusColor(exec.status || 'started')}`);

        if (exec.id) {
          console.log(chalk.dim(`\n   Stream logs: zea cerebelum logs ${exec.id} --follow`));
        }
        console.log('');
      } catch (e) {
        handleError(e);
      }
    });
}
