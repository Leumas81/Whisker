import { expect, test } from "@playwright/test";

test.describe("accueil", () => {
  test("se charge sans erreur de console", async ({ page }) => {
    const errors: string[] = [];
    page.on("console", (message) => {
      if (message.type() === "error") errors.push(message.text());
    });
    page.on("pageerror", (error) => errors.push(error.message));

    await page.goto("/");
    await expect(page).toHaveTitle(/WHISKER/);
    expect(errors).toEqual([]);
  });

  test("annonce l'état réel du pipeline plutôt que des chiffres d'exemple", async ({ page }) => {
    await page.goto("/");
    const state = page.getByTestId("pipeline-state");
    await expect(state).toBeVisible();
    await expect(state).not.toHaveText("");
  });

  test("porte les attributions obligatoires", async ({ page }) => {
    await page.goto("/");
    const footer = page.locator("footer");
    await expect(footer).toContainText("Oracle");
    await expect(footer).toContainText("Leaguepedia");
    // Apostrophe typographique : le site est en français soigné, le test suit.
    await expect(footer).toContainText("n’est pas affilié à Riot Games");
    await expect(footer.getByRole("link", { name: /Oracle/ })).toHaveAttribute(
      "href",
      /oracleselixir\.com/,
    );
  });

  test("est en français et annoncé comme tel", async ({ page }) => {
    await page.goto("/");
    await expect(page.locator("html")).toHaveAttribute("lang", "fr");
  });

  test("ne charge aucune ressource tierce", async ({ page }) => {
    const external: string[] = [];
    page.on("request", (request) => {
      const host = new URL(request.url()).hostname;
      if (host !== "127.0.0.1" && host !== "localhost") external.push(request.url());
    });

    await page.goto("/", { waitUntil: "networkidle" });
    expect(external).toEqual([]);
  });
});
