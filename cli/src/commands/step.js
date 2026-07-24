/**
 * cerebelum step — Manage individual steps within a workflow.
 *
 * Commands:
 *   step list <workflow>              List steps with metadata
 *   step show <workflow> <step>       Show step source code
 *   step update <workflow> <step> <file.py>  Update step code from file
 *   step delete <workflow> <step>     Delete a step
 */
import fs from 'fs';
import { getClient } from '../lib/client.js';
import { zeaFetch } from '../lib/http.js';
import { getGlobalOpts, display } from '../lib/globals.js';
import { handleError } from '../lib/errors.js';
import chalk from 'chalk';

export function register(program) {
  const stepCmd = program.command('step').description('Manage individual workflow steps');

  stepCmd.command('list <workflow>')
    .description('List steps in a workflow')
    .action(async (workflow) => {
      const opts = getGlobalOpts();
      try {
        const client = await getClient();
        const resp = await zeaFetch(
          `${client.apiUrl}/api/v1/workflows/${encodeURIComponent(workflow)}/steps`,
          { headers: client.headers },
        );

        if (resp.status === 404) {
          console.error(chalk.red(`❌ Workflow not found: ${workflow}`));
          process.exit(1);
        }
        if (!resp.ok) {
          throw Object.assign(new Error(`HTTP ${resp.status}`), { status: resp.status });
        }

        const data = await resp.json();
        const steps = data.data?.steps || [];

        if (opts.output === 'json') {
          display(data.data, opts);
          return;
        }

        if (!steps.length) {
          console.log(chalk.dim(`No steps in workflow "${workflow}".`));
          console.log(chalk.dim('   Add one: zea cerebelum step update ' + workflow + ' step_name file.py'));
          return;
        }

        console.log(chalk.cyan(`\n📋 Steps in ${chalk.bold(workflow)} (${steps.length})\n`));
        for (const s of steps) {
          const pos = `[${s.position}]`;
          const icon = s.has_code ? chalk.green('●') : chalk.yellow('○');

          console.log(`  ${icon} ${chalk.dim(pos)} ${chalk.bold(s.name)}`);
        }
        console.log('');
      } catch (e) {
        handleError(e);
      }
    });

  stepCmd.command('show <workflow> <step>')
    .description('Show step source code')
    .action(async (workflow, step) => {
      const opts = getGlobalOpts();
      try {
        const client = await getClient();
        const resp = await zeaFetch(
          `${client.apiUrl}/api/v1/workflows/${encodeURIComponent(workflow)}/steps/${encodeURIComponent(step)}`,
          { headers: client.headers },
        );

        if (resp.status === 404) {
          console.error(chalk.red(`❌ Workflow or step not found: ${workflow}/${step}`));
          process.exit(1);
        }
        if (!resp.ok) {
          throw Object.assign(new Error(`HTTP ${resp.status}`), { status: resp.status });
        }

        const data = await resp.json();

        if (opts.output === 'json') {
          display(data.data, opts);
          return;
        }

        const code = data.data?.code;
        if (code) {
          console.log(chalk.cyan(`\n📝 ${chalk.bold(workflow)} → ${chalk.magenta(step)}\n`));
          console.log(chalk.dim(code));
          console.log('');
        } else {
          console.log(chalk.yellow(`⚠️  Source code not available for ${workflow}/${step}`));
        }
      } catch (e) {
        handleError(e);
      }
    });

  stepCmd.command('update <workflow> <step> <file>')
    .description('Update a step from a Python file')
    .action(async (workflow, step, file) => {
      const opts = getGlobalOpts();

      if (!fs.existsSync(file)) {
        console.error(chalk.red(`❌ File not found: ${file}`));
        process.exit(1);
      }

      const code = fs.readFileSync(file, 'utf-8');

      try {
        const client = await getClient();

        if (opts.dryRun) {
          console.log(chalk.yellow('⚠️  DRY RUN — would update:'));
          console.log(`   PUT ${client.apiUrl}/api/v1/workflows/${workflow}/steps/${step}`);
          console.log(`   File: ${file} (${code.length} bytes)`);
          return;
        }

        const resp = await zeaFetch(
          `${client.apiUrl}/api/v1/workflows/${encodeURIComponent(workflow)}/steps/${encodeURIComponent(step)}`,
          {
            method: 'PUT',
            headers: client.headers,
            body: JSON.stringify({ code }),
          },
        );

        if (!resp.ok) {
          const errData = await resp.json().catch(() => ({}));
          throw Object.assign(
            new Error(errData.error || `HTTP ${resp.status}`),
            { status: resp.status },
          );
        }

        const data = await resp.json();

        if (opts.output === 'json') {
          display(data.data, opts);
          return;
        }

        console.log(chalk.green(`\n✅ Step updated!`));
        console.log(`   Workflow: ${chalk.bold(workflow)}`);
        console.log(`   Step:     ${chalk.magenta(step)}`);
        console.log(`   Code:     ${code.length} bytes from ${chalk.dim(file)}`);
        console.log('');
      } catch (e) {
        handleError(e);
      }
    });

  stepCmd.command('delete <workflow> <step>')
    .description('Delete a step from a workflow')
    .option('--yes', 'Skip confirmation prompt')
    .action(async (workflow, step, options) => {
      const opts = getGlobalOpts();

      // Confirmation
      if (!options.yes && !opts.dryRun) {
        console.log(chalk.yellow(`\n⚠️  This will permanently delete step "${step}" from workflow "${workflow}".`));
        console.log(chalk.dim('   This action cannot be undone.\n'));

        // Simple confirmation via stdin
        const readline = await import('readline');
        const rl = readline.default.createInterface({
          input: process.stdin,
          output: process.stdout,
        });

        const answer = await new Promise((resolve) => {
          rl.question(chalk.yellow('   Are you sure? (yes/no): '), (ans) => {
            rl.close();
            resolve(ans.trim().toLowerCase());
          });
        });

        if (answer !== 'yes') {
          console.log(chalk.dim('\n   Cancelled.\n'));
          process.exit(0);
        }
        console.log('');
      }

      try {
        const client = await getClient();

        if (opts.dryRun) {
          console.log(chalk.yellow('⚠️  DRY RUN — would delete:'));
          console.log(`   DELETE ${client.apiUrl}/api/v1/workflows/${workflow}/steps/${step}`);
          return;
        }

        const resp = await zeaFetch(
          `${client.apiUrl}/api/v1/workflows/${encodeURIComponent(workflow)}/steps/${encodeURIComponent(step)}`,
          {
            method: 'DELETE',
            headers: client.headers,
          },
        );

        if (!resp.ok) {
          const errData = await resp.json().catch(() => ({}));
          throw Object.assign(
            new Error(errData.error || `HTTP ${resp.status}`),
            { status: resp.status },
          );
        }

        const data = await resp.json();

        if (opts.output === 'json') {
          display(data.data, opts);
          return;
        }

        console.log(chalk.green(`\n🗑️  Step deleted!`));
        console.log(`   Workflow: ${chalk.bold(workflow)}`);
        console.log(`   Step:     ${chalk.red(step)}`);
        console.log('');
      } catch (e) {
        handleError(e);
      }
    });
}
