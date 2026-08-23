#!/usr/bin/env node
/**
 * Audit Lighthouse sur le site construit, servi en local.
 *
 * Le §7 exige au moins 95 en Performance et en Accessibilité. Le mesurer localement plutôt
 * qu'après déploiement a deux vertus : le résultat existe avant la mise en ligne, et il ne
 * dépend pas de la latence d'un CDN — donc il est reproductible.
 *
 *   node tools/lighthouse.mjs            contrôle les quatre pages représentatives
 *   node tools/lighthouse.mjs --json     rend le détail brut
 */
import { spawn, spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { repoRoot } from "./lib/paths.mjs";

const PORT = 4433;
const SEUILS = { performance: 95, accessibility: 95 };
const PAGES = [
  ["/", "accueil"],
  ["/joueurs", "joueurs"],
  ["/vieillissement", "vieillissement"],
  ["/methode", "methode"],
];

const distDir = path.join(repoRoot, "web", "dist");
if (!fs.existsSync(distDir)) {
  console.error("web/dist est absent. Lancez « pnpm build » d'abord.");
  process.exit(1);
}

const reportsDir = fs.mkdtempSync(path.join(os.tmpdir(), "whisker-lighthouse-"));

const server = spawn(`pnpm exec astro preview --port ${PORT} --host 127.0.0.1`, {
  cwd: path.join(repoRoot, "web"),
  shell: true,
  stdio: "ignore",
});

const stop = () => {
  server.kill();
  fs.rmSync(reportsDir, { recursive: true, force: true });
};
process.on("exit", stop);

await new Promise((resolve) => setTimeout(resolve, 6000));

const results = [];
for (const [route, name] of PAGES) {
  const report = path.join(reportsDir, `${name}.json`);
  const outcome = spawnSync(
    [
      "npx --yes lighthouse",
      `"http://127.0.0.1:${PORT}${route}"`,
      "--quiet",
      `--chrome-flags="--headless=new --no-sandbox"`,
      "--preset=desktop",
      "--only-categories=performance,accessibility,best-practices,seo",
      "--output=json",
      `--output-path="${report}"`,
    ].join(" "),
    { shell: true, stdio: "ignore" },
  );

  if (outcome.status !== 0 || !fs.existsSync(report)) {
    console.error(`Lighthouse n'a pas pu auditer ${route}.`);
    process.exit(1);
  }

  const payload = JSON.parse(fs.readFileSync(report, "utf8"));
  const score = (key) => Math.round((payload.categories[key]?.score ?? 0) * 100);
  results.push({
    name,
    route,
    performance: score("performance"),
    accessibility: score("accessibility"),
    bestPractices: score("best-practices"),
    seo: score("seo"),
  });
}

stop();

if (process.argv.includes("--json")) {
  console.log(JSON.stringify(results, null, 2));
} else {
  console.log("Page             perf  a11y  b.pr.   seo");
  for (const result of results) {
    console.log(
      `${result.name.padEnd(16)}${String(result.performance).padStart(4)}` +
        `${String(result.accessibility).padStart(6)}` +
        `${String(result.bestPractices).padStart(7)}` +
        `${String(result.seo).padStart(6)}`,
    );
  }
}

const failures = results.flatMap((result) =>
  Object.entries(SEUILS)
    .filter(([key]) => result[key] < SEUILS[key])
    .map(([key]) => `${result.route} : ${key} à ${result[key]}, seuil ${SEUILS[key]}`),
);

if (failures.length > 0) {
  console.error(`\n${failures.length} score(s) sous le seuil du §7 :`);
  for (const failure of failures) console.error(`  • ${failure}`);
  process.exit(1);
}

console.log("\nTous les scores atteignent le seuil du §7 (95 en performance et accessibilité).");
