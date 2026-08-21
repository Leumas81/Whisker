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

function walk(directory: string): string[] {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const full = path.join(directory, entry.name);
    return entry.isDirectory() ? walk(full) : [full];
  });
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
    test.skip(true, "Aucun joueur exporté : le contrôle s'appliquera dès la phase 3.");
    return;
  }

  const { players } = JSON.parse(fs.readFileSync(playersFile, "utf8")) as {
    players: { name: string }[];
  };
  const names = players.map((player) => player.name).filter((name) => name.length >= 3);
  if (names.length === 0) return;

  // Un montant en euros : 60 000 €, 60000€, 165 000 EUR…
  // Les séparateurs de milliers français sont des espaces insécables, écrites en échappement.
  const amount = String.raw`\d[\d\u00A0\u202F\s.,]{2,}\s?(?:€|EUR)`;
  const escaped = names.map((name) => name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"));
  const near = new RegExp(
    `(?:(?:${escaped.join("|")})[\\s\\S]{0,160}?${amount})|(?:${amount}[\\s\\S]{0,160}?(?:${escaped.join("|")}))`,
    "i",
  );

  const offenders: string[] = [];
  for (const file of walk(distDir).filter((file) => file.endsWith(".html"))) {
    const text = fs
      .readFileSync(file, "utf8")
      .replace(/<script[\s\S]*?<\/script>/gi, " ")
      .replace(/<style[\s\S]*?<\/style>/gi, " ")
      .replace(/<[^>]+>/g, " ");
    const hit = near.exec(text);
    if (hit) offenders.push(`${path.relative(distDir, file)} : « ${hit[0].slice(0, 120).trim()} »`);
  }

  expect(
    offenders,
    "Un montant en euros apparaît à côté d'un nom de joueur. Seuls le quintile et la fourchette sont autorisés (§6.6).",
  ).toEqual([]);
});

test("chaque page affiche la traçabilité du pipeline", () => {
  const metaFile = path.join(dataDir, "meta.json");
  if (!fs.existsSync(metaFile)) {
    test.skip(true, "meta.json sera produit en phase 3.");
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
