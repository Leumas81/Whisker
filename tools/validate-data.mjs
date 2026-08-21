#!/usr/bin/env node
/**
 * Valide les JSON produits par le pipeline contre leurs schémas.
 *
 * Deux régimes :
 *   sans option   — valide ce qui est présent ; utile tant que le pipeline n'a pas tourné.
 *   --require-all — exige les cinq fichiers ; c'est le régime de la CI du pipeline et du
 *                   déploiement, où l'absence d'un fichier est une panne, pas une étape.
 */
import fs from "node:fs";
import path from "node:path";
import { dataDir, dataManifest } from "./lib/paths.mjs";
import { createValidator, formatErrors } from "./lib/validator.mjs";

const requireAll = process.argv.includes("--require-all");
const ajv = createValidator();
const failures = [];
const report = [];

const present = fs.existsSync(dataDir)
  ? fs.readdirSync(dataDir).filter((file) => file.endsWith(".json"))
  : [];

// Un fichier de données sans contrat n'a rien à faire dans le site.
const known = new Set(dataManifest.map((entry) => entry.data));
for (const file of present) {
  if (!known.has(file)) {
    failures.push(`${file} n'est associé à aucun schéma. Ajoutez-le à tools/lib/paths.mjs ou retirez-le.`);
  }
}

for (const entry of dataManifest) {
  const filePath = path.join(dataDir, entry.data);

  if (!fs.existsSync(filePath)) {
    if (requireAll) failures.push(`${entry.data} est absent alors qu'il est exigé.`);
    else report.push(`  ○ ${entry.data.padEnd(14)} absent — le pipeline n'a pas encore tourné`);
    continue;
  }

  const bytes = fs.statSync(filePath).size;
  let payload;
  try {
    payload = JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch (error) {
    failures.push(`${entry.data} n'est pas un JSON lisible : ${error.message}`);
    continue;
  }

  const validate = ajv.getSchema(entry.schema);
  if (!validate(payload)) {
    failures.push(`${entry.data} ne respecte pas ${entry.schema} :\n${formatErrors(validate.errors)}`);
    continue;
  }

  if (bytes > entry.maxBytes) {
    failures.push(
      `${entry.data} pèse ${(bytes / 1024).toFixed(0)} Ko, au-delà du plafond de ${(entry.maxBytes / 1024).toFixed(0)} Ko. ` +
        `Au-delà, il faut découper par ligue (§2.1).`,
    );
    continue;
  }

  report.push(`  ● ${entry.data.padEnd(14)} valide — ${(bytes / 1024).toFixed(0)} Ko`);
}

for (const line of report) console.log(line);

if (failures.length > 0) {
  console.error(`\nValidation des données : ${failures.length} problème(s).\n`);
  for (const failure of failures) console.error(`  • ${failure}`);
  process.exit(1);
}

const validated = report.filter((line) => line.includes("●")).length;
console.log(`données validées : ${validated}/${dataManifest.length} fichiers`);
