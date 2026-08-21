#!/usr/bin/env node
/**
 * Contrôle les schémas eux-mêmes, avant même de parler de données.
 *
 * Compile chaque schéma avec ajv — ce qui attrape les `$ref` cassés, les mots-clés inconnus
 * et les constructions invalides — puis vérifie quelques invariants que JSON Schema ne sait
 * pas exprimer tout seul.
 */
import fs from "node:fs";
import path from "node:path";
import { schemasDir, dataManifest, supportSchemas } from "./lib/paths.mjs";
import { createValidator, readSchema, allSchemaFiles } from "./lib/validator.mjs";

const failures = [];

function check(label, condition, detail) {
  if (condition) return;
  failures.push(detail ? `${label}\n    ${detail}` : label);
}

/** Parcourt un schéma et rend chaque sous-schéma rencontré, avec son chemin. */
function* subschemas(node, trail = "") {
  if (Array.isArray(node)) {
    for (const [index, item] of node.entries()) yield* subschemas(item, `${trail}[${index}]`);
    return;
  }
  if (!node || typeof node !== "object") return;
  yield [trail || "<racine>", node];
  for (const [key, value] of Object.entries(node)) yield* subschemas(value, `${trail}/${key}`);
}

// ── Tous les schémas du dossier sont-ils déclarés ? ───────────────────────────────────
const onDisk = fs.readdirSync(schemasDir).filter((file) => file.endsWith(".schema.json")).sort();
const declared = allSchemaFiles().sort();
check(
  "Le dossier schemas/ et la table des contrats divergent.",
  JSON.stringify(onDisk) === JSON.stringify(declared),
  `sur disque : ${onDisk.join(", ")}\n    déclarés : ${declared.join(", ")}`,
);

// ── Chaque schéma compile-t-il ? ──────────────────────────────────────────────────────
const ajv = createValidator();
for (const file of declared) {
  try {
    const compiled = ajv.getSchema(file);
    check(`Le schéma « ${file} » est introuvable dans l'instance ajv.`, Boolean(compiled));
  } catch (error) {
    check(`Le schéma « ${file} » ne compile pas.`, false, String(error.message).split("\n")[0]);
  }
}

// ── Estimate et UnitEstimate doivent garder exactement la même forme ──────────────────
const common = readSchema("common.schema.json");
const estimateKeys = Object.keys(common.$defs.Estimate.properties).sort();
const unitKeys = Object.keys(common.$defs.UnitEstimate.properties).sort();
check(
  "Estimate et UnitEstimate n'ont plus les mêmes champs.",
  JSON.stringify(estimateKeys) === JSON.stringify(unitKeys),
  `Estimate : ${estimateKeys.join(", ")}\n    UnitEstimate : ${unitKeys.join(", ")}`,
);

// ── Band ne doit jamais porter d'estimation ponctuelle (§6.6) ─────────────────────────
check(
  "Band a gagné un champ « point ». Aucun montant salarial ponctuel ne doit pouvoir exister.",
  !("point" in common.$defs.Band.properties),
);

// ── `orderedProperties` doit nommer des propriétés réelles ────────────────────────────
for (const file of declared) {
  const schema = readSchema(file);
  for (const [trail, node] of subschemas(schema)) {
    if (!Array.isArray(node.orderedProperties)) continue;
    const known = Object.keys(node.properties ?? {});
    const unknown = node.orderedProperties.filter((name) => !known.includes(name));
    check(
      `${file} ${trail} : orderedProperties nomme des propriétés inexistantes.`,
      unknown.length === 0,
      `inconnues : ${unknown.join(", ")}`,
    );
  }
}

// ── Toute estimation exportée doit porter son intervalle (§1.2) ───────────────────────
for (const entry of dataManifest) {
  const schema = readSchema(entry.schema);
  for (const [trail, node] of subschemas(schema)) {
    if (node.type !== "object" || !node.properties) continue;
    if (!("point" in node.properties)) continue;
    const hasInterval = "lower" in node.properties && "upper" in node.properties;
    check(
      `${entry.schema} ${trail} : un objet porte « point » sans « lower »/« upper ».`,
      hasInterval,
      "Aucun chiffre n'est jamais affiché seul : le contrat doit imposer l'intervalle.",
    );
  }
}

// ── Chaque contrat de données décrit-il bien un fichier ? ─────────────────────────────
for (const entry of dataManifest) {
  const schema = readSchema(entry.schema);
  check(
    `${entry.schema} devrait décrire un objet racine.`,
    schema.type === "object",
    `type déclaré : ${schema.type}`,
  );
  check(`${entry.schema} n'a pas de titre.`, typeof schema.title === "string" && schema.title.length > 0);
}

check(
  "Les schémas de support ne doivent porter que des définitions partagées.",
  supportSchemas.every((file) => !("type" in readSchema(file))),
);

if (failures.length > 0) {
  console.error(`Contrôle des schémas : ${failures.length} problème(s).\n`);
  for (const failure of failures) console.error(`  • ${failure}`);
  process.exit(1);
}

console.log(
  `schémas conformes : ${declared.length} fichiers, ` +
    `${dataManifest.length} contrats de données, ${supportSchemas.length} de support`,
);
