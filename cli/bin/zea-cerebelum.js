#!/usr/bin/env node

import { Command } from 'commander';
import { readFileSync } from 'fs';

const pkg = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));

// ═══ Command files ══════════════════════════════════════
import { register as registerConfig } from '../src/commands/config.js';
import { register as registerHealth } from '../src/commands/health.js';
import { register as registerDoctor } from '../src/commands/doctor.js';
import { register as registerWorkflow } from '../src/commands/workflow.js';
import { register as registerDeploy } from '../src/commands/deploy.js';
import { register as registerExecution } from '../src/commands/execution.js';
import { register as registerWorker } from '../src/commands/worker.js';
import { register as registerLogs } from '../src/commands/logs.js';
import { register as registerDevCerts } from '../src/commands/dev-certs.js';
import { register as registerRun } from '../src/commands/run.js';

// ═══ Program ════════════════════════════════════════════
const program = new Command();

program
  .name('zea-cerebelum')
  .description('ZEA Cerebelum — Deterministic Workflow Orchestration')
  .version(pkg.version)
  .option('--output <format>', 'Output format: json, table, text', 'table')
  .option('--debug', 'Show HTTP request/response details', false)
  .option('--dry-run', 'Validate without executing', false)
  .option('--quiet', 'Suppress non-essential output', false)
  .option('--no-color', 'Disable ANSI colors', false);

// ═══ Register all commands ══════════════════════════════
registerConfig(program);
registerHealth(program);
registerDoctor(program);
registerWorkflow(program);
registerDeploy(program);
registerExecution(program);
registerWorker(program);
registerLogs(program);
registerDevCerts(program);
registerRun(program);

// ═══ Dynamic command discovery (--zea-discover) ═════
// Used by zea-cli to auto-discover available commands for
// smoke testing, help generation, and validation.
if (process.argv.includes('--zea-discover')) {
  const commands = {};
  function walk(cmds, prefix = '') {
    for (const cmd of cmds) {
      const name = prefix ? prefix + ' ' + cmd.name() : cmd.name();
      if (cmd.description()) commands[name] = cmd.description();
      walk(cmd.commands, name);
    }
  }
  walk(program.commands);
  console.log(JSON.stringify({
    description: 'Deterministic Workflow Orchestration',
    commands
  }, null, 2));
  process.exit(0);
}

// ═══ Agent manifest (--zea-manifest) ═════════════════
// Full metadata export for AI agents and doc generation.
if (process.argv.includes('--zea-manifest')) {
  const PUBLIC_COMMANDS = new Set([
    'health', 'config', 'doctor'
  ]);

  function extractOptions(cmd) {
    return cmd.options.map(o => ({
      name: o.long || o.short,
      short: o.short || null,
      type: o.attributeName?.() || 'string',
      description: o.description || '',
      required: o.required || false,
      default: o.defaultValue
    }));
  }

  function extractArgs(cmd) {
    if (!cmd._args) return [];
    return cmd._args.map(a => ({
      name: a._name,
      required: a.required || false,
      description: a.description || ''
    }));
  }

  const commands = {};
  function walk(cmds, prefix = '') {
    for (const cmd of cmds) {
      const name = prefix ? prefix + ' ' + cmd.name() : cmd.name();
      const isPublic = PUBLIC_COMMANDS.has(name) ||
        [...PUBLIC_COMMANDS].some(p => name.startsWith(p + ' '));

      commands[name] = {
        description: cmd.description() || '',
        options: extractOptions(cmd),
        arguments: extractArgs(cmd),
        auth: !isPublic
      };
      walk(cmd.commands, name);
    }
  }
  walk(program.commands);

  console.log(JSON.stringify({
    service: 'cerebelum',
    version: pkg.version,
    description: 'Deterministic Workflow Orchestration',
    endpoints: {
      default: 'http://cerebelum.zea.localhost',
      env_override: 'CEREBELUM_API_URL | CEREBELUM_URL'
    },
    commands
  }, null, 2));
  process.exit(0);
}

program.parse(process.argv);
