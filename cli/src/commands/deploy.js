/**
 * cerebelum deploy — Deploy a workflow blueprint from a Python file.
 */
import fs from 'fs';
import path from 'path';
import { getClient } from '../lib/client.js';
import { zeaFetch } from '../lib/http.js';
import { getGlobalOpts, display } from '../lib/globals.js';
import { handleError } from '../lib/errors.js';
import chalk from 'chalk';

export function register(program) {
  program.command('deploy <file>')
    .description('Deploy a workflow blueprint from a Python file')
    .option('--name <name>', 'Workflow name (default: derived from file)')
    .action(async (file, options) => {
      const opts = getGlobalOpts();

      if (!fs.existsSync(file)) {
        console.error(chalk.red(`❌ File not found: ${file}`));
        process.exit(1);
      }

      const code = fs.readFileSync(file, 'utf-8');
      const fileName = path.basename(file, '.py');
      const workflowName = options.name || extractWorkflowName(code) || fileName;

      try {
        const client = await getClient();

        const body = {
          name: workflowName,
          module: workflowName,
          code,
          language: 'python',
        };

        if (opts.dryRun) {
          console.log(chalk.yellow('⚠️  DRY RUN — would deploy:'));
          console.log(`   POST ${client.apiUrl}/api/v1/workflows/deploy`);
          console.log(`   Name: ${workflowName} (${code.length} bytes)`);
          return;
        }

        const resp = await zeaFetch(`${client.apiUrl}/api/v1/workflows/deploy`, {
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
        const wf = data.data || data;

        if (opts.output === 'json') {
          display(wf, opts);
          return;
        }

        console.log(chalk.green(`\n✅ Blueprint deployed!`));
        console.log(`   Workflow: ${chalk.bold(workflowName)}`);
        if (wf.id) console.log(`   ID:       ${chalk.dim(wf.id)}`);
        console.log('');
        console.log(chalk.dim(`   Run: zea cerebelum workflow run ${workflowName} --inputs '{"name":"ZEA"}'`));
        console.log('');
      } catch (e) {
        handleError(e);
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
