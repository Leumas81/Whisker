#!/usr/bin/env node
/**
 * Génère web/src/generated/types.ts depuis schemas/.
 *
 * Le fichier produit n'est jamais édité à la main. Avec l'option --check, le script
 * régénère en mémoire et compare à la version commitée : c'est le garde-fou qui rend
 * impossible qu'un schéma évolue sans que le site en soit informé.
 */
import fs from "node:fs";
import path from "node:path";
import { compile } from "json-schema-to-typescript";
import { schemasDir, generatedTypesPath, dataManifest } from "./lib/paths.mjs";
import { dedupeTypes } from "./lib/dedupe-types.mjs";

const BANNER = `/**
 * FICHIER GÉNÉRÉ — NE PAS ÉDITER À LA MAIN.
 *
 * Source : schemas/*.schema.json
 * Régénérer : pnpm gen:types
 *
 * Toute modification manuelle sera écrasée, et « pnpm verify » échouera tant que
 * ce fichier ne correspondra pas exactement aux schémas.
 */`;

/**
 * Schéma racine synthétique : il ne décrit aucun fichier réel, il sert uniquement à
 * compiler les cinq contrats en une passe. Compiler fichier par fichier redéclarerait
 * « Estimate » cinq fois.
 */
const rootSchema = {
  $schema: "https://json-schema.org/draft/2020-12/schema",
  $id: "whisker.schema.json",
  title: "WhiskerData",
  description: "Regroupement de tous les jeux de données du site. Type de commodité : aucun fichier ne porte cette forme.",
  type: "object",
  properties: Object.fromEntries(
    dataManifest.map((entry) => [path.basename(entry.data, ".json"), { $ref: entry.schema }]),
  ),
  required: dataManifest.map((entry) => path.basename(entry.data, ".json")),
  additionalProperties: false,
};

async function generate() {
  const body = await compile(rootSchema, "WhiskerData", {
    cwd: schemasDir + path.sep,
    bannerComment: BANNER,
    additionalProperties: false,
    declareExternallyReferenced: true,
    enableConstEnums: false,
    unknownAny: true,
    style: { singleQuote: false, semi: true, printWidth: 100 },
  });
  const { output, divergentNames } = dedupeTypes(body.replace(/\r\n/g, "\n"));
  if (divergentNames.length > 0) {
    console.warn(
      "Types au nom suffixé mais de forme différente — un schéma définit probablement deux fois la même notion :",
      divergentNames.join(", "),
    );
  }
  return output;
}

async function main() {
  const check = process.argv.includes("--check");
  const generated = await generate();

  if (!check) {
    fs.mkdirSync(path.dirname(generatedTypesPath), { recursive: true });
    fs.writeFileSync(generatedTypesPath, generated, "utf8");
    const count = (generated.match(/^export (interface|type) /gm) ?? []).length;
    console.log(`types générés : ${path.relative(process.cwd(), generatedTypesPath)} (${count} déclarations)`);
    return;
  }

  if (!fs.existsSync(generatedTypesPath)) {
    console.error("web/src/generated/types.ts est absent. Lancez « pnpm gen:types ».");
    process.exit(1);
  }

  const committed = fs.readFileSync(generatedTypesPath, "utf8").replace(/\r\n/g, "\n");
  if (committed === generated) {
    console.log("types à jour avec les schémas");
    return;
  }

  const committedLines = committed.split("\n");
  const generatedLines = generated.split("\n");
  const firstDiff = generatedLines.findIndex((line, i) => committedLines[i] !== line);
  console.error("Les types générés ne correspondent plus aux schémas.");
  console.error("");
  console.error(`  Première divergence, ligne ${firstDiff + 1} :`);
  console.error(`    commité : ${JSON.stringify(committedLines[firstDiff] ?? "<fin de fichier>")}`);
  console.error(`    attendu : ${JSON.stringify(generatedLines[firstDiff] ?? "<fin de fichier>")}`);
  console.error("");
  console.error("  Un schéma a changé sans que les types soient régénérés.");
  console.error("  Corrigez avec : pnpm gen:types");
  process.exit(1);
}

main().catch((error) => {
  console.error("Échec de la génération des types :");
  console.error(error);
  process.exit(1);
});
