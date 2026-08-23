import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { expect, test } from "@playwright/test";

/**
 * Contrôles sur l'artefact construit, pas sur les sources.
 *
 * Ils ne dépendent d'aucun navigateur mais vivent ici parce qu'ils ont besoin de dist/,
 * qui n'existe qu'après le build — c'est-à-dire à cette étape de « pnpm verify ».
 */

const webRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const distDir = path.join(webRoot, "dist");
const dataDir = path.join(webRoot, "src", "data");

/**
 * Les séparateurs de milliers français sont des espaces insécables. On les construit par
 * code plutôt que de les écrire : une espace invisible dans un fichier source est un piège,
 * et le lint la refuse à juste titre.
 */
const NBSP = String.fromCharCode(0x00a0);
const NARROW_NBSP = String.fromCharCode(0x202f);
const SPACES = `\\s${NBSP}${NARROW_NBSP}`;


function walk(directory: string): string[] {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const full = path.join(directory, entry.name);
    return entry.isDirectory() ? walk(full) : [full];
  });
}

function pageText(file: string): string {
  return fs
    .readFileSync(file, "utf8")
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;|&#160;/g, " ")
    .replace(/\s+/g, " ");
}

test.describe.configure({ mode: "serial" });

test("le build existe", () => {
  expect(fs.existsSync(distDir), "dist/ est absent : lancez « pnpm build ».").toBe(true);
});

test("aucune donnée fictive n'atteint la production", () => {
  const suspects = walk(distDir)
    .map((file) => path.relative(distDir, file))
    .filter((file) => /\.(mock|fixture|sample|fake|demo)\./i.test(path.basename(file)));

  expect(
    suspects,
    "Un fichier d'exemple s'est glissé dans le build. Aucune donnée fictive ne doit atteindre la production.",
  ).toEqual([]);
});

test("aucun montant salarial nominatif n'est publié", () => {
  const playersFile = path.join(dataDir, "players.json");
  if (!fs.existsSync(playersFile)) {
    test.skip(true, "Aucun joueur exporté : le contrôle s'appliquera dès que le pipeline aura tourné.");
    return;
  }

  const { players } = JSON.parse(fs.readFileSync(playersFile, "utf8")) as {
    players: { name: string }[];
  };
  const names = players.map((player) => player.name).filter((name) => name.length >= 3);
  if (names.length === 0) return;

  const AMOUNT = new RegExp(`\\d[\\d${SPACES}.,]{2,}\\s?(?:€|EUR)`, "g");
  const escaped = names.map((name) => name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"));
  const NAME = new RegExp(`\\b(?:${escaped.join("|")})\\b`, "g");

  /**
   * Le §6.6 autorise la fourchette et interdit le montant ponctuel. Un montant est donc
   * acceptable s'il est apparié à un autre par un séparateur d'intervalle ; il ne l'est
   * pas s'il apparaît seul à proximité d'un nom de joueur.
   */
  const SEPARATOR = new RegExp(`^[${SPACES}]*(?:–|—|-|à|to)[${SPACES}]*$`);

  const offenders: string[] = [];
  for (const file of walk(distDir).filter((candidate) => candidate.endsWith(".html"))) {
    const text = pageText(file);
    const amounts = [...text.matchAll(AMOUNT)].map((match) => ({
      start: match.index,
      end: match.index + match[0].length,
      text: match[0],
    }));
    if (amounts.length === 0) continue;

    const paired = new Set<number>();
    for (let index = 0; index < amounts.length - 1; index += 1) {
      const gap = text.slice(amounts[index]!.end, amounts[index + 1]!.start);
      if (SEPARATOR.test(gap)) {
        paired.add(index);
        paired.add(index + 1);
      }
    }

    const nameSpans = [...text.matchAll(NAME)].map((match) => match.index);
    for (const [index, amount] of amounts.entries()) {
      if (paired.has(index)) continue;
      const nearby = nameSpans.some((position) => Math.abs(position - amount.start) <= 160);
      if (nearby) {
        offenders.push(
          `${path.relative(distDir, file)} : « ${text.slice(Math.max(0, amount.start - 60), amount.end + 20).trim()} »`,
        );
      }
    }
  }

  expect(
    offenders.slice(0, 5),
    "Un montant en euros isolé apparaît près d'un nom de joueur. Seuls le quintile et la fourchette sont autorisés (§6.6).",
  ).toEqual([]);
});

test("une fourchette reste autorisée à côté d'un nom", () => {
  // Contrôle du contrôle : si le test précédent refusait aussi les fourchettes, il
  // interdirait ce que le brief autorise, et passerait pour de mauvaises raisons.
  const playerPages = walk(distDir).filter((file) =>
    file.includes(`${path.sep}joueur${path.sep}`),
  );
  if (playerPages.length === 0) {
    test.skip(true, "Aucune fiche joueur construite.");
    return;
  }
  const BAND = new RegExp(`\\d[\\d${SPACES}.,]*\\s?€\\s*–`);
  const withBand = playerPages.filter((file) => BAND.test(pageText(file)));
  expect(withBand.length, "Aucune fourchette salariale n'apparaît sur les fiches joueur.").toBeGreaterThan(0);
});

test("chaque page affiche la traçabilité du pipeline", () => {
  const metaFile = path.join(dataDir, "meta.json");
  if (!fs.existsSync(metaFile)) {
    test.skip(true, "meta.json sera produit par le pipeline.");
    return;
  }

  const meta = JSON.parse(fs.readFileSync(metaFile, "utf8")) as { pipelineCommit: string };
  const short = meta.pipelineCommit.slice(0, 7);
  const pages = walk(distDir).filter((file) => file.endsWith(".html"));

  const missing = pages
    .filter((file) => !fs.readFileSync(file, "utf8").includes(short))
    .map((file) => path.relative(distDir, file));

  expect(missing, "Chaque estimation doit être traçable jusqu'au commit qui l'a produite.").toEqual([]);
});

test("des données synthétiques sont annoncées sur chaque page", () => {
  const metaFile = path.join(dataDir, "meta.json");
  if (!fs.existsSync(metaFile)) {
    test.skip(true, "meta.json sera produit par le pipeline.");
    return;
  }
  const meta = JSON.parse(fs.readFileSync(metaFile, "utf8")) as { synthetic: boolean };
  if (!meta.synthetic) return;

  const pages = walk(distDir).filter((file) => file.endsWith(".html"));
  const silent = pages
    .filter((file) => !pageText(file).includes("Jeu de développement"))
    .map((file) => path.relative(distDir, file));

  expect(
    silent,
    "Tant que les données sont synthétiques, chaque page doit le dire sans qu'on ait à cliquer.",
  ).toEqual([]);
});
