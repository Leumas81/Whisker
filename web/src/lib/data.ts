import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import type { AgingFile, LeaguesFile, MetaFile, PlayersFile, SalaryFile } from "~/generated/types";

/**
 * Chargement des données produites par le pipeline, au moment du build uniquement.
 *
 * Rien n'est lu à l'exécution : le site est statique. Les types viennent de
 * src/generated/types.ts, lui-même dérivé des schémas — si le pipeline renomme un champ
 * sans mettre le schéma à jour, la validation échoue en CI avant d'arriver ici.
 */
const dataDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "data");

export type DataFileName = "players" | "leagues" | "aging" | "salary" | "meta";

interface DataShapes {
  players: PlayersFile;
  leagues: LeaguesFile;
  aging: AgingFile;
  salary: SalaryFile;
  meta: MetaFile;
}

function filePath(name: DataFileName): string {
  return path.join(dataDir, `${name}.json`);
}

/** Vrai si le pipeline a déjà produit ce fichier. */
export function hasData(name: DataFileName): boolean {
  return fs.existsSync(filePath(name));
}

/** Vrai si les cinq fichiers sont là. */
export function hasAllData(): boolean {
  return (["players", "leagues", "aging", "salary", "meta"] satisfies DataFileName[]).every(hasData);
}

/**
 * Lit un fichier de données. L'absence est une panne explicite, jamais un objet vide :
 * une page qui se construit sans données afficherait des chiffres inventés par omission.
 */
export function readData<Name extends DataFileName>(name: Name): DataShapes[Name] {
  const target = filePath(name);
  if (!fs.existsSync(target)) {
    throw new Error(
      `Données absentes : ${name}.json n'a pas été produit.\n` +
        `Lancez le pipeline R (pipeline/run_all.R) ou le workflow pipeline.yml.`,
    );
  }
  return JSON.parse(fs.readFileSync(target, "utf8")) as DataShapes[Name];
}
