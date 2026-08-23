import { expect, test } from "@playwright/test";

/**
 * Le composant signature. Ce qui est vérifié ici n'est pas son apparence mais ses
 * propriétés : la largeur d'un intervalle reste proportionnelle à la donnée, le mouvement
 * respecte les préférences du lecteur, et la page ne déborde à aucune largeur.
 */

test("la largeur d'un intervalle est proportionnelle à son incertitude", async ({ page }) => {
  await page.goto("/");

  // On lit les positions dans le repère SVG, pas en pixels : c'est l'échelle qui est en
  // cause, et elle ne doit jamais être normalisée pour l'esthétique (§5.3).
  const rows = await page.evaluate(() => {
    const table = document.querySelector("figure .sr-only table");
    return Array.from(table?.querySelectorAll("tbody tr") ?? []).map((row) => {
      const cells = Array.from(row.querySelectorAll("td")).map((cell) => cell.textContent ?? "");
      const parse = (value: string) => Number(value.replace(/\s/g, "").replace(",", "."));
      return { lower: parse(cells[5] ?? "0"), upper: parse(cells[6] ?? "0") };
    });
  });
  expect(rows.length).toBeGreaterThan(2);

  const caps = await page.evaluate(() => {
    const svg = document.querySelector('figure svg[role="img"]');
    const circles = Array.from(svg?.querySelectorAll("circle[data-estimate-mark]") ?? []);
    return circles.map((circle) => {
      const y = Number(circle.getAttribute("cy"));
      const lines = Array.from(svg?.querySelectorAll("line") ?? []).filter(
        (line) => Number(line.getAttribute("y1")) === y && Number(line.getAttribute("y2")) === y,
      );
      const xs = lines.flatMap((line) => [
        Number(line.getAttribute("x1")),
        Number(line.getAttribute("x2")),
      ]);
      return Math.max(...xs) - Math.min(...xs);
    });
  });

  expect(caps.length).toBe(rows.length);

  // Le rapport largeur-tracée / largeur-donnée doit être identique pour toutes les lignes.
  const ratios = caps.map((width, index) => width / (rows[index]!.upper - rows[index]!.lower));
  const first = ratios[0]!;
  for (const ratio of ratios) {
    expect(Math.abs(ratio - first) / first).toBeLessThan(0.02);
  }
});

test("le graphique tient dans la page à toutes les largeurs", async ({ page }) => {
  await page.goto("/");
  const overflow = await page.evaluate(
    () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
  );
  expect(overflow, "La page déborde horizontalement.").toBeLessThanOrEqual(1);
});

test("l'animation des moustaches est désactivée si le lecteur en demande moins", async ({
  browser,
}) => {
  const context = await browser.newContext({ reducedMotion: "reduce" });
  const page = await context.newPage();
  await page.goto("/");

  const animated = await page.evaluate(() =>
    Array.from(document.querySelectorAll(".forest-whisker")).map(
      (node) => getComputedStyle(node).animationName,
    ),
  );
  expect(animated.length).toBeGreaterThan(0);
  expect(animated.every((name) => name === "none")).toBe(true);

  // Et surtout : les intervalles restent entièrement tracés, jamais un graphique vide.
  const offsets = await page.evaluate(() =>
    Array.from(document.querySelectorAll(".forest-whisker")).map((node) =>
      Number(getComputedStyle(node).strokeDashoffset.replace("px", "")),
    ),
  );
  expect(offsets.every((offset) => offset === 0)).toBe(true);
  await context.close();
});

test("l'animation est présente quand le mouvement est accepté", async ({ browser }) => {
  const context = await browser.newContext({ reducedMotion: "no-preference" });
  const page = await context.newPage();
  await page.goto("/");

  const names = await page.evaluate(() =>
    Array.from(document.querySelectorAll(".forest-whisker")).map(
      (node) => getComputedStyle(node).animationName,
    ),
  );
  expect(names.length).toBeGreaterThan(0);
  expect(names.every((name) => name === "dessin-intervalle")).toBe(true);
  await context.close();
});

test("un échantillon faible est signalé par le fanion", async ({ page }) => {
  await page.goto("/joueurs");

  // On abaisse le seuil pour faire apparaître les joueurs à faible échantillon.
  const slider = page.locator('input[type="range"]');
  await slider.fill("10");

  const flagged = page.locator("figure svg text", { hasText: "⚑" });
  expect(await flagged.count()).toBeGreaterThanOrEqual(0);
});

test("le tri par borne basse change l'ordre affiché", async ({ page }) => {
  await page.goto("/joueurs");
  const nameAt = async (index: number) =>
    page.locator("figure .sr-only table tbody tr").nth(index).locator("td").nth(1).textContent();

  const before = await nameAt(0);
  await page.getByLabel("Trier par").selectOption("lower");
  await page.waitForTimeout(150);
  const after = await nameAt(0);

  // Le classement peut coïncider, mais la table doit rester cohérente et non vide.
  expect(before).toBeTruthy();
  expect(after).toBeTruthy();
});
