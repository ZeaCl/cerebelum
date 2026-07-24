/**
 * cerebelum health — Check Cerebelum engine health status (no auth required).
 */
import { zeaFetch } from '../lib/http.js';
import { getGlobalOpts } from '../lib/globals.js';
import { handleError } from '../lib/errors.js';
import { loadConfig } from '../lib/client.js';
import chalk from 'chalk';

export function register(program) {
  program.command('health')
    .description('Check Cerebelum engine health status (no auth required)')
    .action(async () => {
      const opts = getGlobalOpts();
      try {
        let apiUrl = 'http://cerebelum.zea.localhost';
        try {
          const config = await loadConfig();
          if (config.cerebelumUrl) apiUrl = config.cerebelumUrl;
        } catch { /* use default */ }

        apiUrl = process.env.CEREBELUM_API_URL || process.env.CEREBELUM_URL || apiUrl;

        const response = await zeaFetch(`${apiUrl}/health`);

        if (!response.ok) {
          console.error(chalk.red(`❌ Cerebelum returned HTTP ${response.status}`));
          process.exit(1);
        }

        const data = await response.json();

        if (opts.output === 'json') {
          console.log(JSON.stringify(data, null, 2));
          process.exit(data.status === 'ok' ? 0 : 1);
        }

        const statusIcon = data.status === 'ok' ? '✅' : '⚠️';

        console.log(chalk.cyan(`\n🧠 Cerebelum ${data.version || '?.?.?'} — ${apiUrl}`));
        console.log(`   Status:   ${statusIcon} ${(data.status || 'unknown').toUpperCase()}`);

        if (data.services) {
          if (data.services.database) {
            const dbIcon = data.services.database === 'ok' ? '✅' : '❌';
            console.log(`   Database: ${dbIcon} ${data.services.database}`);
          }
          if (data.services.grpc) {
            const grpcIcon = data.services.grpc === 'ok' ? '✅' : '❌';
            console.log(`   gRPC:     ${grpcIcon} ${data.services.grpc}`);
          }
        }

        if (data.checks) {
          for (const [name, result] of Object.entries(data.checks)) {
            const icon = result === 'ok' ? '✅' : '❌';
            console.log(`   ${name.padEnd(12)} ${icon} ${result}`);
          }
        }

        if (data.errors && data.errors.length > 0) {
          console.log(chalk.red('   Errors:'));
          for (const err of data.errors) {
            console.log(chalk.red(`     - ${err}`));
          }
        }

        console.log('');

        if (data.status !== 'ok') {
          console.log('   Run: zea cerebelum doctor');
          process.exit(1);
        }
      } catch (e) {
        if (e.code === 'ENOTFOUND' || e.code === 'ECONNREFUSED') {
          let url = 'http://cerebelum.zea.localhost';
          try {
            const config = await loadConfig();
            url = config.cerebelumUrl || url;
          } catch {}
          url = process.env.CEREBELUM_API_URL || process.env.CEREBELUM_URL || url;
          console.error(chalk.red(`❌ Cannot reach Cerebelum at ${url}`));
          console.error('   Is it running? Try: docker compose up -d');
        } else {
          handleError(e);
        }
        process.exit(1);
      }
    });
}
