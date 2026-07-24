/**
 * cerebelum logs — Stream execution logs.
 *
 * Commands:
 *   logs <id>              Get execution logs
 *   logs <id> --follow     Follow logs in real-time
 */
import { getClient } from '../lib/client.js';
import { zeaFetch } from '../lib/http.js';
import { getGlobalOpts, display } from '../lib/globals.js';
import { handleError } from '../lib/errors.js';
import chalk from 'chalk';

export function register(program) {
  program.command('logs <id>')
    .description('Get execution logs')
    .option('--follow, -f', 'Follow logs in real-time')
    .action(async (id, options) => {
      const opts = getGlobalOpts();
      try {
        const client = await getClient();
        let lastVersion = -1;

        while (true) {
          const resp = await zeaFetch(`${client.apiUrl}/api/v1/executions/${encodeURIComponent(id)}/events`, {
            headers: client.headers,
          });

          if (!resp.ok) {
            if (lastVersion === -1) {
              throw Object.assign(new Error(`HTTP ${resp.status}`), { status: resp.status });
            }
            break;
          }

          const data = await resp.json();
          const events = data.events || data.data || [];
          const newEvents = events.filter((e) => (e.version ?? 0) > lastVersion);

          if (newEvents.length > 0) {
            for (const ev of newEvents) {
              if (opts.output === 'json') {
                display(ev, opts);
              } else {
                const eventColor =
                  ev.type?.includes('Completed') || ev.type?.includes('Resumed') || ev.type?.includes('Executed') ? chalk.green :
                  ev.type?.includes('Failed') ? chalk.red :
                  ev.type?.includes('Paused') || ev.type?.includes('Waiting') ? chalk.yellow :
                  ev.type?.includes('Started') ? chalk.cyan : chalk.gray;

                const time = ev.timestamp ? new Date(ev.timestamp).toLocaleTimeString() : '';
                const stepInfo = ev.data?.step_name ? ` ${chalk.magenta(`[${ev.data.step_name}]`)}` : '';
                console.log(`${chalk.dim(`[${time}]`)} ${eventColor(ev.type)}${stepInfo}`);

                const output = ev.data?.result || ev.data?.final_result || ev.data?.output;
                if (output && typeof output === 'object' && Object.keys(output).length > 0) {
                  const vals = Object.entries(output).map(([k, v]) => `${k}=${v}`).join(' · ');
                  console.log(`  ${chalk.dim(`→ ${vals}`)}`);
                }
              }
              lastVersion = Math.max(lastVersion, ev.version);
            }
          }

          // Check if terminal
          const lastEvent = events[events.length - 1];
          if (lastEvent && ['ExecutionCompleted', 'ExecutionFailed', 'ExecutionCancelled'].some(
            (t) => lastEvent.type?.includes(t)
          )) {
            if (!opts.output === 'json') {
              const icon = lastEvent.type?.includes('Failed') ? '❌' : '✅';
              const elapsed = lastEvent.timestamp ? '' : '';
              console.log(`\n  ${icon} ${lastEvent.type}`);
            }
            break;
          }

          if (!options.follow) break;

          // Wait before polling
          await new Promise((resolve) => setTimeout(resolve, 2000));
        }
      } catch (e) {
        handleError(e);
      }
    });
}
