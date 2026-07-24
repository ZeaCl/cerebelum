/**
 * cerebelum worker — Manage Python workers.
 *
 * Commands:
 *   worker list    List registered workers
 */
import { getClient } from '../lib/client.js';
import { zeaFetch } from '../lib/http.js';
import { getGlobalOpts, display } from '../lib/globals.js';
import { handleError } from '../lib/errors.js';
import chalk from 'chalk';

export function register(program) {
  const workerCmd = program.command('worker').description('Manage Python workers');

  workerCmd.command('list')
    .description('List registered Python workers')
    .action(async () => {
      const opts = getGlobalOpts();
      try {
        const client = await getClient(true);
        const resp = await zeaFetch(`${client.apiUrl}/api/v1/workers`, {
          headers: client.headers,
        });

        if (!resp.ok) {
          throw Object.assign(new Error(`HTTP ${resp.status}`), { status: resp.status });
        }

        const data = await resp.json();
        const workers = data.data || [];

        if (opts.output === 'json') {
          display(workers, opts);
          return;
        }

        if (!workers.length) {
          console.log(chalk.dim('\nNo Python workers registered (Elixir-native only).'));
          console.log(chalk.dim('   Start one: python -m cerebelum.worker\n'));
          return;
        }

        console.log(chalk.cyan(`\n🐍 Python Workers (${workers.length})\n`));
        for (const w of workers) {
          console.log(`  ${chalk.magenta('•')} ${w.id} ${chalk.dim(`@ ${w.url || 'local'}`)}`);
          if (w.workflow_count !== undefined) {
            console.log(`    ${w.workflow_count} workflows`);
          }
        }
        console.log('');
      } catch (e) {
        handleError(e);
      }
    });
}
