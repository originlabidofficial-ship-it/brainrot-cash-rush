// Driver for the roblox-brainrot-01 entry. The playable place is game.rbxl, built from the Rojo
// project beside this file. The job here is to stage the entry for the judge and to write the
// dossier that describes what was staged.
//
// The staged output is: <out>/game.rbxl, <out>/PLAY.json, <out>/src/, <out>/screenshots/ and
// <out>/dossier.json. The grader only accepts output names that begin with a letter, a digit or _
// and otherwise use letters, digits, '.', '_' or '-'. A dot-prefixed name such as .gitkeep or
// .DS_Store would therefore fail the entry, so copying filters those out at every depth.
//
// The destination is /output by default. Set MAKEFUN_OUTPUT_DIR to stage somewhere else:
//   mkdir -p out && MAKEFUN_OUTPUT_DIR=out node main.ts

import { copyFileSync, cpSync, existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { basename, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildDossier } from './vendor/makefun-roblox.ts';

/** The directory holding this driver; every input is read from beside it. */
const ENTRY_DIR = fileURLToPath(new URL('.', import.meta.url));

/** Where the staged entry goes: the grader's /output, or the local override. */
const OUTPUT_DIR = process.env.MAKEFUN_OUTPUT_DIR ?? '/output';

/** Basename of the summary the judge reads. */
const DOSSIER_NAME = 'dossier.json';

/**
 * cpSync filter: keep an entry only when its own name is not hidden. Applied recursively, so a
 * hidden file or a whole hidden folder is skipped wherever it appears.
 */
function keepVisible(path: string): boolean {
  return !basename(path).startsWith('.');
}

/** A file or folder moved from ENTRY_DIR into OUTPUT_DIR. */
interface StagedItem {
  /** Name relative to ENTRY_DIR, reused unchanged under OUTPUT_DIR. */
  readonly name: string;
  /** False for screenshots/: an entry may ship no screenshots at all. */
  readonly required: boolean;
  /** True when the source is a folder that should be copied recursively. */
  readonly folder: boolean;
}

/**
 * The staging list, in the order used by the entry: the place, its play metadata, the server and
 * client sources, then the optional screenshots. Each keeps its own name in the output.
 */
const STAGED_ITEMS: readonly StagedItem[] = [
  { name: 'game.rbxl', required: true, folder: false },
  { name: 'PLAY.json', required: true, folder: false },
  { name: 'src', required: true, folder: true },
  { name: 'screenshots', required: false, folder: true },
];

/** Copy one staged item into OUTPUT_DIR, creating the destination folder on the way. */
function stage(item: StagedItem): void {
  const from = join(ENTRY_DIR, item.name);
  const to = join(OUTPUT_DIR, item.name);

  if (!item.folder) {
    copyFileSync(from, to);
    return;
  }

  // screenshots/ is part of the expected layout even when the entry has none to offer.
  mkdirSync(to, { recursive: true });
  if (!item.required && !existsSync(from)) return;

  cpSync(from, to, { recursive: true, filter: keepVisible });
}

/** Stage the whole entry, then describe the staged directory with the vendored make.fun helper. */
function main(): void {
  // The driver may be pointed at a directory that does not exist yet.
  mkdirSync(OUTPUT_DIR, { recursive: true });
  for (const item of STAGED_ITEMS) {
    stage(item);
  }

  // Caps mirror the scorer's reference/gate.json. text_max_bytes decides how much dossier text is
  // kept; the remaining caps reject exactly the entries the scorer would reject (too many or too
  // large screenshots, an oversized place, or oversized script sources and paths).
  const dossier = buildDossier(OUTPUT_DIR, { text_max_bytes: 65536, screenshots: { max: 4, max_bytes: 262144 }, max_instances: 500000, scripts_max_source_bytes: 8388608, scripts_max_path_chars: 1048576 });
  writeFileSync(join(OUTPUT_DIR, DOSSIER_NAME), dossier);
}

main();
