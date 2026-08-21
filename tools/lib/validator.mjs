import fs from "node:fs";
import path from "node:path";
import Ajv2020 from "ajv/dist/2020.js";
import addFormats from "ajv-formats";
import { schemasDir, dataManifest, supportSchemas } from "./paths.mjs";

/**
 * `orderedProperties` — mot-clé maison.
 *
 * JSON Schema ne sait pas comparer deux propriétés entre elles ; or la contrainte
 * `lower <= point <= upper` est le cœur du contrat de données de WHISKER. Plutôt que
 * de dupliquer la règle dans le code R et dans le code TypeScript, on la déclare dans
 * le schéma sous forme d'annotation et on écrit un seul vérificateur générique qui la lit.
 * Le schéma reste la source unique de vérité.
 */
const orderedProperties = {
  keyword: "orderedProperties",
  type: "object",
  schemaType: "array",
  errors: true,
  validate: function ordered(names, data) {
    ordered.errors = [];
    for (let i = 0; i < names.length - 1; i += 1) {
      const a = data[names[i]];
      const b = data[names[i + 1]];
      if (typeof a !== "number" || typeof b !== "number") continue;
      if (a > b) {
        ordered.errors.push({
          keyword: "orderedProperties",
          message: `« ${names[i]} » (${a}) doit être inférieur ou égal à « ${names[i + 1]} » (${b})`,
          params: { property: names[i], next: names[i + 1] },
        });
        return false;
      }
    }
    return true;
  },
};

/**
 * `fieldNote` — annotation sans effet de validation.
 *
 * Un `description` placé à côté d'un `$ref` écrase la documentation du type référencé
 * et pousse le générateur à cloner ce type sous un nom numéroté. La note propre au champ
 * vit donc ici : lisible dans le schéma, exploitable côté R, invisible du générateur.
 */
const fieldNote = { keyword: "fieldNote", schemaType: "string", valid: true };

export function readSchema(fileName) {
  return JSON.parse(fs.readFileSync(path.join(schemasDir, fileName), "utf8"));
}

export function allSchemaFiles() {
  return [...supportSchemas, ...dataManifest.map((entry) => entry.schema)];
}

/** Construit une instance ajv chargée de tous les schémas du dépôt. */
export function createValidator() {
  const ajv = new Ajv2020({ allErrors: true, strict: true, strictTypes: true });
  addFormats(ajv);
  ajv.addKeyword(orderedProperties);
  ajv.addKeyword(fieldNote);
  for (const file of allSchemaFiles()) {
    ajv.addSchema(readSchema(file), file);
  }
  return ajv;
}

export function formatErrors(errors) {
  if (!errors) return "aucune erreur détaillée";
  return errors
    .map((error) => `  ${error.instancePath || "<racine>"} : ${error.message}`)
    .join("\n");
}
