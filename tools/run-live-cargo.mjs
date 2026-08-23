#!/usr/bin/env node
/**
 * Vérification de l'ingestion Cargo contre la source réelle.
 *
 * Hors de « pnpm verify » à dessein : ce contrôle touche le réseau et dépend de la
 * disponibilité de lol.fandom.com, qui limite le débit des adresses mutualisées. Il se
 * déclare ignoré plutôt que rouge quand la source refuse de répondre.
 */
import { spawnSync } from "node:child_process";
import path from "node:path";
import process from "node:process";
import { repoRoot } from "./lib/paths.mjs";

const rscript = process.env.WHISKER_RSCRIPT ?? "Rscript";
const outcome = spawnSync(
  [/\s/.test(rscript) ? `"${rscript}"` : rscript, "tests/live/test-cargo-live.R"].join(" "),
  { cwd: path.join(repoRoot, "pipeline"), stdio: "inherit", shell: true },
);
process.exit(outcome.status ?? 1);
