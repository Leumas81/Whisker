#!/usr/bin/env node
/**
 * Le dernier verrou avant publication.
 *
 * `pnpm verify` accepte des données synthétiques : sans elles, le site ne pourrait pas être
 * construit ni relu tant que le pipeline n'a pas tourné. Mais construire n'est pas publier.
 * Ce contrôle-ci refuse toute mise en ligne dont les chiffres ne décrivent personne.
 */
import fs from "node:fs";
import path from "node:path";
import { dataDir, dataManifest } from "./lib/paths.mjs";

const failures = [];

for (const entry of dataManifest) {
  if (!fs.existsSync(path.join(dataDir, entry.data))) {
    failures.push(`${entry.data} est absent : rien à publier.`);
  }
}

const metaPath = path.join(dataDir, "meta.json");
if (fs.existsSync(metaPath)) {
  const meta = JSON.parse(fs.readFileSync(metaPath, "utf8"));
  if (meta.synthetic) {
    failures.push(
      "meta.synthetic est vrai : ces chiffres sont un jeu de développement.\n" +
        "    Lancez le pipeline sur les données réelles avant de publier.",
    );
  }
  if (meta.unmatchedRate > 0.02) {
    failures.push(`Taux de non-résolution de ${(meta.unmatchedRate * 100).toFixed(2)} %, au-delà du seuil.`);
  }
}

if (failures.length > 0) {
  console.error(`Publication refusée : ${failures.length} problème(s).\n`);
  for (const failure of failures) console.error(`  • ${failure}`);
  process.exit(1);
}

console.log("données réelles et complètes : publication autorisée");
