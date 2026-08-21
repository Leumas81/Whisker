#!/usr/bin/env node
/**
 * La commande unique du §0.2 : si elle passe, la phase est terminée ; sinon elle ne l'est pas.
 *
 * Les étapes sont ordonnées du moins cher au plus cher, et de la cause à l'effet : un schéma
 * cassé doit se voir avant un test bout-en-bout rouge, sans quoi on débogue le symptôme.
 * Tout est exécuté même si une étape échoue — un rapport partiel n'apprend rien.
 */
import { spawnSync } from "node:child_process";
import process from "node:process";
import path from "node:path";
import { repoRoot } from "./lib/paths.mjs";

/**
 * Les tests R ne tournent que si Rscript est accessible. Travailler sur le site ne demande
 * pas d'installer R, et la CI exécute ces tests dans un job dédié de toute façon — mais
 * quand R est là, autant que la commande unique le couvre aussi.
 */
function findRscript() {
  const explicit = process.env.WHISKER_RSCRIPT;
  if (explicit) return explicit;
  const probe = spawnSync("Rscript --version", { shell: true, stdio: "ignore" });
  return probe.status === 0 ? "Rscript" : null;
}

const rscript = findRscript();

const STEPS = [
  { id: "schemas", label: "Contrats de données cohérents", command: ["node", "tools/check-schemas.mjs"] },
  { id: "types", label: "Types TypeScript à jour avec les schémas", command: ["node", "tools/gen-types.mjs", "--check"] },
  { id: "data", label: "JSON conformes à leurs schémas", command: ["node", "tools/validate-data.mjs"] },
  { id: "lint", label: "Lint", command: ["pnpm", "--filter", "whisker-web", "run", "lint"] },
  { id: "typecheck", label: "Typage strict", command: ["pnpm", "--filter", "whisker-web", "run", "typecheck"] },
  { id: "unit", label: "Tests unitaires", command: ["pnpm", "--filter", "whisker-web", "run", "test:unit"] },
  { id: "build", label: "Build du site", command: ["pnpm", "--filter", "whisker-web", "run", "build"] },
  { id: "e2e", label: "Tests bout-en-bout", command: ["pnpm", "--filter", "whisker-web", "run", "test:e2e"] },
  {
    id: "pipeline",
    label: "Tests du pipeline R",
    command: [rscript ?? "", "tests/testthat.R"],
    cwd: "pipeline",
    skip: rscript
      ? null
      : "Rscript introuvable. Définissez WHISKER_RSCRIPT ou ajoutez R au PATH pour l'inclure.",
  },
];

const only = process.argv.slice(2).filter((argument) => !argument.startsWith("-"));
const steps = only.length > 0 ? STEPS.filter((step) => only.includes(step.id)) : STEPS;

if (steps.length === 0) {
  console.error(`Étapes inconnues : ${only.join(", ")}`);
  console.error(`Étapes disponibles : ${STEPS.map((step) => step.id).join(", ")}`);
  process.exit(1);
}

const results = [];
for (const step of steps) {
  console.log(`\n[1m── ${step.label}[0m`);
  if (step.skip) {
    console.log(`  ignoré : ${step.skip}`);
    results.push({ ...step, ok: true, skipped: true, seconds: 0 });
    continue;
  }
  const started = Date.now();
  // Commande passée en une seule chaîne : combiner `shell: true` et un tableau
  // d'arguments est déprécié depuis Node 22. Aucune de ces commandes n'est paramétrable
  // de l'extérieur, la question de l'échappement ne se pose pas.
  const line = step.command
    .map((part) => (/\s/.test(part) ? `"${part}"` : part))
    .join(" ");
  const outcome = spawnSync(line, {
    cwd: step.cwd ? path.join(repoRoot, step.cwd) : repoRoot,
    stdio: "inherit",
    shell: true,
  });
  results.push({
    ...step,
    ok: outcome.status === 0,
    seconds: (Date.now() - started) / 1000,
  });
}

console.log("\n[1m── Récapitulatif[0m");
for (const result of results) {
  const mark = result.skipped ? "[33m○[0m" : result.ok ? "[32m✓[0m" : "[31m✗[0m";
  const timing = result.skipped ? "ignoré" : `${result.seconds.toFixed(1)} s`;
  console.log(`  ${mark} ${result.label.padEnd(42)} ${timing}`);
}

const failed = results.filter((result) => !result.ok);
if (failed.length > 0) {
  console.error(`\n${failed.length} étape(s) en échec : ${failed.map((step) => step.id).join(", ")}`);
  process.exit(1);
}

console.log(`\n[32mTout est au vert[0m — ${results.length} étapes.`);
