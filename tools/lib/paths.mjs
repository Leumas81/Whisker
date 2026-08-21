import { fileURLToPath } from "node:url";
import path from "node:path";

export const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
export const schemasDir = path.join(repoRoot, "schemas");
export const dataDir = path.join(repoRoot, "web", "src", "data");
export const generatedTypesPath = path.join(repoRoot, "web", "src", "generated", "types.ts");

/**
 * Correspondance schéma → fichier de données produit par le pipeline.
 * Un fichier présent dans web/src/data/ mais absent de cette table fait échouer la validation :
 * aucune donnée ne peut arriver sur le site sans contrat.
 */
export const dataManifest = [
  { schema: "player.schema.json", data: "players.json", maxBytes: 2_000_000 },
  { schema: "leagues.schema.json", data: "leagues.json", maxBytes: 500_000 },
  { schema: "aging.schema.json", data: "aging.json", maxBytes: 500_000 },
  { schema: "salary.schema.json", data: "salary.json", maxBytes: 200_000 },
  { schema: "meta.schema.json", data: "meta.json", maxBytes: 50_000 },
];

/** Schémas de définitions partagées : pas de fichier de données associé. */
export const supportSchemas = ["common.schema.json"];
