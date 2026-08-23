// @ts-check
import { defineConfig } from "astro/config";
import react from "@astrojs/react";
import sitemap from "@astrojs/sitemap";
import tailwindcss from "@tailwindcss/vite";

/**
 * Site entièrement statique : aucune route serveur, aucun endpoint.
 * React n'est chargé que sur les îlots qui en ont besoin (forest plot, filtres, courbes).
 */
export default defineConfig({
  site: "https://whisker.pages.dev",
  output: "static",
  trailingSlash: "ignore",
  integrations: [react(), sitemap()],
  vite: {
    plugins: [tailwindcss()],
    server: {
      // docs/METHODE.md est rendu par /methode : il vit à la racine du dépôt, hors de web/.
      fs: { allow: [".."] },
    },
  },
  build: {
    format: "directory",
    inlineStylesheets: "auto",
  },
  devToolbar: { enabled: false },
});
