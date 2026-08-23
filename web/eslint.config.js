import js from "@eslint/js";
import tseslint from "typescript-eslint";
import astro from "eslint-plugin-astro";
import jsxA11y from "eslint-plugin-jsx-a11y";
import globals from "globals";

export default tseslint.config(
  {
    ignores: [
      "dist/**",
      ".astro/**",
      "node_modules/**",
      "test-results/**",
      "playwright-report/**",
      // Fichier généré depuis les schémas : sa forme appartient au générateur, pas au lint.
      "src/generated/**",
    ],
  },

  js.configs.recommended,
  ...tseslint.configs.recommended,
  ...astro.configs.recommended,

  {
    files: ["**/*.{ts,tsx,astro,js,mjs}"],
    languageOptions: {
      globals: { ...globals.browser, ...globals.node },
    },
    rules: {
      "@typescript-eslint/consistent-type-imports": "error",
      "@typescript-eslint/no-unused-vars": [
        "error",
        { argsIgnorePattern: "^_", varsIgnorePattern: "^_", ignoreRestSiblings: true },
      ],
      eqeqeq: ["error", "always"],
      "no-console": ["warn", { allow: ["warn", "error"] }],
    },
  },

  {
    files: ["**/*.tsx"],
    plugins: { "jsx-a11y": jsxA11y },
    rules: {
      ...jsxA11y.configs.recommended.rules,
      /**
       * Une zone défilante doit être atteignable au clavier, sans quoi son contenu est
       * inaccessible à qui ne fait pas défiler à la souris — c'est ce qu'exige la règle
       * « scrollable-region-focusable » d'axe. La règle jsx-a11y l'interdit par défaut sur
       * un conteneur non interactif : les deux se contredisent, et axe a raison. On autorise
       * donc le tabindex sur un conteneur explicitement annoncé comme région.
       */
      "jsx-a11y/no-noninteractive-tabindex": ["error", { roles: ["tabpanel", "region"] }],
    },
  },

  {
    files: ["tests/**/*.{ts,tsx}", "*.config.{ts,mjs,js}"],
    rules: { "no-console": "off" },
  },
);
