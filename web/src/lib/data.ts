import type { AgingFile, LeaguesFile, MetaFile, PlayersFile, SalaryFile } from "~/generated/types";

/**
 * Chargement des données produites par le pipeline, au moment du build uniquement.
 *
 * Rien n'est lu à l'exécution : le site est statique. Les types viennent de
 * src/generated/types.ts, lui-même dérivé des schémas — si le pipeline renomme un champ sans
 * mettre le schéma à jour, la validation échoue en CI avant d'arriver ici.
 *
 * La résolution passe par `import.meta.glob`, que Vite évalue relativement à CE fichier
 * source. Un chemin calculé depuis `import.meta.url` ne survivrait pas au bundling : le module
 * exécuté n'est pas celui qu'on lit, et les données paraîtraient absentes alors qu'elles sont là.
 */
const modules = import.meta.glob<{ default: unknown }>("../data/*.json", { eager: true });

const byName = new Map<string, unknown>(
  Object.entries(modules).map(([path, module]) => [
    path.replace(/^.*\//, "").replace(/\.json$/, ""),
    module.default,
  ]),
);

export type DataFileName = "players" | "leagues" | "aging" | "salary" | "meta";

interface DataShapes {
  players: PlayersFile;
  leagues: LeaguesFile;
  aging: AgingFile;
  salary: SalaryFile;
  meta: MetaFile;
}

const ALL: DataFileName[] = ["players", "leagues", "aging", "salary", "meta"];

/** Vrai si le pipeline a déjà produit ce fichier. */
export function hasData(name: DataFileName): boolean {
  return byName.has(name);
}

/** Vrai si les cinq fichiers sont là. */
export function hasAllData(): boolean {
  return ALL.every(hasData);
}

/**
 * Lit un fichier de données. L'absence est une panne explicite, jamais un objet vide :
 * une page qui se construit sans données afficherait des chiffres inventés par omission.
 */
export function readData<Name extends DataFileName>(name: Name): DataShapes[Name] {
  const payload = byName.get(name);
  if (payload === undefined) {
    throw new Error(
      `Données absentes : ${name}.json n'a pas été produit.\n` +
        `Lancez le pipeline R (pipeline/run_all.R) ou le workflow pipeline.yml.`,
    );
  }
  return payload as DataShapes[Name];
}
