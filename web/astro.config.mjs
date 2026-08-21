// @ts-check
import { defineConfig } from "astro/config";
import react from "@astrojs/react";
import tailwindcss from "@tailwindcss/vite";

/**
 * Site entièrement statique : aucune route serveur, aucun endpoint.
 * React n'est chargé que sur les îlots qui en ont besoin (forest plot, filtres, courbes).
 */
export default defineConfig({
  site: "https://whisker.pages.dev",
  output: "static",
  trailingSlash: "ignore",
  integrations: [react()],
  vite: {
    plugins: [tailwindcss()],
  },
  build: {
    format: "directory",
    inlineStylesheets: "auto",
  },
  devToolbar: { enabled: false },
});
