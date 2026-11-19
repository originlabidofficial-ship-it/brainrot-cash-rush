// main.ts — stage the Brainrot Cash Rush entry and write its dossier.
//
// Inputs (read from beside this file): game.rbxl, PLAY.json, src/, screenshots/.
// Output: the same names under MAKEFUN_OUTPUT_DIR (default "/output"), plus
// dossier.json. Dot-prefixed names are skipped at every depth because the
// grader rejects output names that do not start with a letter, digit or "_".

import { copyFileSync, cpSync, existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { basename, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildDossier } from './vendor/makefun-roblox.ts';

/** Directory that holds this driver and every input it stages. */
const ENTRY_DIR = fileURLToPath(new URL('.', import.meta.url));

/** Destination directory; the grader uses /output. */
const OUTPUT_DIR = process.env.MAKEFUN_OUTPUT_DIR ?? '/output';

/** Name of the judge-facing summary written after staging. */
const DOSSIER_FILE = 'dossier.json';

/** Limits passed to the vendored make.fun dossier builder (same as the scorer). */
const DOSSIER_LIMITS = {
  text_max_bytes: 65536,
  screenshots: { max: 4, max_bytes: 262144 },
  max_instances: 500000,
  scripts_max_source_bytes: 8388608,
  scripts_max_path_chars: 1048576,
} as const;

type StagedItem = {
  /** Name under ENTRY_DIR, kept unchanged in the output. */
  readonly name: string;
  /** True when the item is a directory copied recursively. */
  readonly folder: boolean;
  /** False only for screenshots/, which an entry may legitimately omit. */
  readonly required: boolean;
};

/** Staging order: the place, its play metadata, sources, then screenshots. */
const STAGED_ITEMS: readonly StagedItem[] = [
  { name: 'game.rbxl', folder: false, required: true },
  { name: 'PLAY.json', folder: false, required: true },
  { name: 'src', folder: true, required: true },
  { name: 'screenshots', folder: true, required: false },
];

/** Recursive copy filter: keep entries whose own basename is not dotted. */
function keepVisible(path: string): boolean {
  return !basename(path).startsWith('.');
}

/** Copy one file or directory into the output directory. */
function stage(item: StagedItem): void {
  const source = join(ENTRY_DIR, item.name);
  const target = join(OUTPUT_DIR, item.name);

  if (!item.folder) {
    copyFileSync(source, target);
    return;
  }

  // screenshots/ is created even when the entry ships none, so the expected
  // layout always exists. cpSync then fills it when there is something to copy.
  mkdirSync(target, { recursive: true });
  if (!item.required && !existsSync(source)) {
    return;
  }
  cpSync(source, target, { recursive: true, filter: keepVisible });
}

/** Stage every item, then describe the staged directory for the judge. */
function main(): void {
  mkdirSync(OUTPUT_DIR, { recursive: true });
  for (const item of STAGED_ITEMS) {
    stage(item);
  }

  const dossier = buildDossier(OUTPUT_DIR, DOSSIER_LIMITS);
  writeFileSync(join(OUTPUT_DIR, DOSSIER_FILE), dossier);
}

main();
