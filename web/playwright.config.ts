import { defineConfig, devices } from "@playwright/test";

/**
 * Les tests bout-en-bout tournent sur le site construit, pas sur le serveur de développement :
 * c'est l'artefact déployé qu'il s'agit de vérifier.
 *
 * Les trois formats du §7 (375 / 768 / 1440) sont des projets distincts afin qu'une régression
 * responsive nomme la largeur fautive plutôt qu'un test générique.
 */
export default defineConfig({
  testDir: "./tests/e2e",
  fullyParallel: true,
  forbidOnly: Boolean(process.env.CI),
  retries: process.env.CI ? 1 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: process.env.CI ? [["github"], ["list"]] : [["list"]],
  expect: { timeout: 5_000 },

  use: {
    baseURL: "http://127.0.0.1:4321",
    trace: "on-first-retry",
    screenshot: "only-on-failure",
  },

  projects: [
    { name: "mobile-375", use: { ...devices["Desktop Chrome"], viewport: { width: 375, height: 812 } } },
    { name: "tablette-768", use: { ...devices["Desktop Chrome"], viewport: { width: 768, height: 1024 } } },
    { name: "bureau-1440", use: { ...devices["Desktop Chrome"], viewport: { width: 1440, height: 900 } } },
  ],

  webServer: {
    command: "pnpm exec astro preview --port 4321 --host 127.0.0.1",
    url: "http://127.0.0.1:4321",
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
  },
});
