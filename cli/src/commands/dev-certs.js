/**
 * cerebelum dev-certs — Generate mTLS certificates for local worker development.
 *
 * Commands:
 *   dev-certs create    Request dev certificates from the engine
 */
import fs from 'fs/promises';
import path from 'path';
import os from 'os';
import { getClient } from '../lib/client.js';
import { zeaFetch } from '../lib/http.js';
import { getGlobalOpts, display } from '../lib/globals.js';
import { handleError } from '../lib/errors.js';
import chalk from 'chalk';

const CERTS_DIR = path.join(os.homedir(), '.cerebelum', 'certs');

export function register(program) {
  const certsCmd = program.command('dev-certs').description('Manage local development mTLS certificates');

  certsCmd.command('create')
    .description('Generate mTLS certificates for local worker (requires auth)')
    .action(async () => {
      const opts = getGlobalOpts();
      try {
        const client = await getClient();
        const resp = await zeaFetch(`${client.apiUrl}/api/v1/dev-certs`, {
          method: 'POST',
          headers: client.headers,
        });

        if (!resp.ok) {
          const errData = await resp.json().catch(() => ({}));
          throw Object.assign(
            new Error(errData.error || `HTTP ${resp.status}`),
            { status: resp.status }
          );
        }

        const data = await resp.json();
        const caCrt = data.ca_crt || data.caCrt;
        const clientCrt = data.client_crt || data.clientCrt;
        const clientKey = data.client_key || data.clientKey;

        if (opts.output === 'json') {
          display({ saved: true, directory: CERTS_DIR }, opts);
          return;
        }

        await fs.mkdir(CERTS_DIR, { recursive: true });
        await fs.writeFile(path.join(CERTS_DIR, 'ca.crt'), caCrt);
        await fs.writeFile(path.join(CERTS_DIR, 'client.crt'), clientCrt);
        await fs.writeFile(path.join(CERTS_DIR, 'client.key'), clientKey);
        await fs.chmod(path.join(CERTS_DIR, 'client.key'), 0o600);

        console.log(chalk.green('✅ mTLS certificates generated!'));
        console.log(chalk.dim(`   Saved to: ${CERTS_DIR}`));
        console.log(chalk.dim(`   Files: ca.crt, client.crt, client.key`));
      } catch (e) {
        handleError(e);
      }
    });

  certsCmd.command('status')
    .description('Check if mTLS certificates exist locally')
    .action(async () => {
      const caPath = path.join(CERTS_DIR, 'ca.crt');
      const certPath = path.join(CERTS_DIR, 'client.crt');
      const keyPath = path.join(CERTS_DIR, 'client.key');

      const hasCa = await fs.access(caPath).then(() => true).catch(() => false);
      const hasCert = await fs.access(certPath).then(() => true).catch(() => false);
      const hasKey = await fs.access(keyPath).then(() => true).catch(() => false);

      if (hasCa && hasCert && hasKey) {
        console.log(chalk.green('✅ mTLS certificates ready'));
        console.log(chalk.dim(`   Directory: ${CERTS_DIR}`));
      } else {
        console.log(chalk.yellow('❌ mTLS certificates missing'));
        const missing = [];
        if (!hasCa) missing.push('ca.crt');
        if (!hasCert) missing.push('client.crt');
        if (!hasKey) missing.push('client.key');
        console.log(chalk.dim(`   Missing: ${missing.join(', ')}`));
        console.log(chalk.dim(`   Run: zea cerebelum dev-certs create`));
      }
    });
}
