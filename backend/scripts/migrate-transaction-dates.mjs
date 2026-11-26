import { open, readFile, realpath } from 'node:fs/promises';
import { basename, dirname, isAbsolute, relative, resolve, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { parseArgs } from 'node:util';
import { runDateMigration, validateScope, decisionsFor, validId } from './date-migration.mjs';
import { createFirestoreAdapter, migrationTarget } from './date-migration-firestore.mjs';

const REPO = fileURLToPath(new URL('../../', import.meta.url));
export const HELP = `R-DATE v2 migration (default: dry-run, no database writes)
Required: --project ID --uid UID --from YYYY-MM-DD --until YYYY-MM-DD --report PATH
Optional: --decisions PATH --limit 1..5000 --batch-size 1..100 --after-id ID
Apply: --apply --confirm-project ID --decisions PATH --journal NEW_PATH
Cloud access requires --allow-cloud; no cloud target is inferred.
The scan is bounded to one UID, ordered by document ID. Date range refers to
legacy UTC instants, not an inferred source timezone. Reports/journals must be
new files outside the Git application folder. Never share them publicly.`;

export function parseOptions(args, env = process.env) {
  const { values } = parseArgs({ args, strict: true, allowPositionals: false, options: {
    project: { type: 'string' }, uid: { type: 'string' }, from: { type: 'string' }, until: { type: 'string' },
    report: { type: 'string' }, decisions: { type: 'string' }, journal: { type: 'string' },
    limit: { type: 'string', default: '500' }, 'batch-size': { type: 'string', default: '100' }, 'after-id': { type: 'string' },
    apply: { type: 'boolean', default: false }, 'confirm-project': { type: 'string' },
    'allow-cloud': { type: 'boolean', default: false }, help: { type: 'boolean', default: false },
  } });
  if (values.help) return { help: true };
  const scope = validateScope({ projectId: values.project, uid: values.uid, from: values.from, until: values.until });
  const limit = Number(values.limit);
  const batchSize = Number(values['batch-size']);
  if (!values.report?.trim() || !Number.isInteger(limit) || limit < 1 || limit > 5000
    || !Number.isInteger(batchSize) || batchSize < 1 || batchSize > 100
    || (values['after-id'] !== undefined && !validId(values['after-id']))) throw new Error('INVALID_OPTIONS');
  if (values.apply && (values['confirm-project'] !== scope.projectId || !values.decisions || !values.journal)) throw new Error('APPLY_REQUIRES_CONFIRMATION_DECISIONS_JOURNAL');
  if (!values.apply && values.journal) throw new Error('JOURNAL_REQUIRES_APPLY');
  migrationTarget(scope.projectId, env.FIRESTORE_EMULATOR_HOST, values['allow-cloud']);
  return { scope, limit, batchSize, afterId: values['after-id'], apply: values.apply,
    allowCloud: values['allow-cloud'], report: values.report, journal: values.journal, decisions: values.decisions };
}

// Resolve the parent too, so a junction/symlink cannot redirect private output
// back into the Git tree. Exclusive creation never overwrites a prior receipt.
async function privateOutput(path) {
  const absolute = resolve(path);
  const parent = await realpath(dirname(absolute));
  const target = resolve(parent, basename(absolute));
  const rel = relative(await realpath(REPO), target);
  if (!rel || (!rel.startsWith(`..${sep}`) && !isAbsolute(rel))) throw new Error('OUTPUT_MUST_BE_OUTSIDE_REPOSITORY');
  return { path: target, handle: await open(target, 'wx', 0o600) };
}

export async function main(args = process.argv.slice(2)) {
  const options = parseOptions(args);
  if (options.help) { process.stdout.write(`${HELP}\n`); return 0; }
  const manifest = options.decisions ? JSON.parse(await readFile(options.decisions, 'utf8')) : undefined;
  decisionsFor(options.scope, manifest); // Reject target/decision mistakes before opening the SDK.
  const output = await privateOutput(options.report);
  let journalOutput;
  let adapter;
  try {
    if (options.apply) journalOutput = await privateOutput(options.journal);
    adapter = createFirestoreAdapter(options.scope, options);
    const journal = journalOutput && { append: async (entry) => {
      await journalOutput.handle.writeFile(`${JSON.stringify(entry)}\n`);
      await journalOutput.handle.sync();
    } };
    const report = await runDateMigration({ ...options, manifest, adapter, journal });
    await output.handle.writeFile(`${JSON.stringify(report, null, 2)}\n`);
    await output.handle.sync();
    process.stdout.write(`${JSON.stringify({ mode: report.mode, counts: report.counts, scan: report.scan })}\n`);
    return report.counts.error > 0 ? 2 : 0;
  } finally {
    await adapter?.close();
    await journalOutput?.handle.close();
    await output.handle.close();
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  main().then((code) => { process.exitCode = code; }).catch(() => {
    // SDK errors can contain credentials, document paths, or record contents.
    process.stderr.write('DATE_MIGRATION_FAILED: periksa target, input, akses dan output privat; tidak ada retry otomatis.\n');
    process.exitCode = 1;
  });
}
