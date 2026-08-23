import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

/**
 * Audit axe-core sur chaque page, aux trois largeurs des projets Playwright.
 *
 * Le §7 exige zéro violation. Un graphique qui ne se lit qu'à l'œil exclut une partie des
 * lecteurs d'un site dont le sujet est précisément la lisibilité d'une estimation.
 */

const PAGES = ["/", "/joueurs", "/vieillissement", "/traduction", "/methode"];

for (const route of PAGES) {
  test(`aucune violation d'accessibilité sur ${route}`, async ({ page }) => {
    await page.goto(route);
    await page.waitForLoadState("networkidle");

    const results = await new AxeBuilder({ page })
      .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"])
      .analyze();

    const summary = results.violations.map(
      (violation) =>
        `${violation.id} (${violation.impact}) — ${violation.help} · ${violation.nodes.length} élément(s)`,
    );
    expect(summary, `Violations détectées sur ${route}`).toEqual([]);
  });
}

test("la fiche joueur est accessible", async ({ page }) => {
  // Les liens vers les fiches vivent dans la vue tableau, pas dans le graphique.
  await page.goto("/joueurs");
  await page.getByRole("button", { name: "Tableau" }).click();
  const href = await page.locator('a[href^="/joueur/"]').first().getAttribute("href");
  test.skip(!href, "Aucune fiche joueur construite.");

  await page.goto(href!);
  await page.waitForLoadState("networkidle");
  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"])
    .analyze();

  expect(results.violations.map((violation) => violation.id)).toEqual([]);
});

test("le forest plot expose une table de données équivalente", async ({ page }) => {
  await page.goto("/");
  const figure = page.locator("figure").first();

  // Le graphique lui-même est annoncé comme image, avec un résumé lisible.
  const svg = figure.locator('svg[role="img"]');
  await expect(svg).toHaveCount(1);
  await expect(svg.locator("title")).not.toBeEmpty();

  // Et les mêmes chiffres existent en table, hors flux visuel.
  const table = figure.locator(".sr-only table");
  await expect(table).toHaveCount(1);
  await expect(table.locator("thead th")).toHaveCount(8);
  expect(await table.locator("tbody tr").count()).toBeGreaterThan(0);
});

test("le graphique ne contient aucun lien, et une route au clavier existe", async ({ page }) => {
  await page.goto("/");

  // Un contenu interactif dans un élément annoncé comme image est inaccessible : le SVG
  // n'en porte aucun. Le clic reste un raccourci souris, posé hors du flux d'accessibilité.
  expect(await page.locator('svg[role="img"] a').count()).toBe(0);

  // Et les mêmes joueurs restent atteignables au clavier.
  await expect(page.getByRole("link", { name: /Voir les/ })).toBeVisible();
});
