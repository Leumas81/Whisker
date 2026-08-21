import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

/**
 * Le fichier de types est un artefact : il ne se relit pas à la main. Ces tests vérifient
 * qu'il existe, qu'il est propre, et qu'il expose bien les formes dont le site dépend.
 */
const typesPath = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
  "..",
  "src",
  "generated",
  "types.ts",
);

const source = fs.readFileSync(typesPath, "utf8");

describe("types générés", () => {
  it("porte l'avertissement de non-édition", () => {
    expect(source).toContain("NE PAS ÉDITER À LA MAIN");
    expect(source).toContain("pnpm gen:types");
  });

  it("expose les cinq contrats de données", () => {
    for (const name of ["PlayersFile", "LeaguesFile", "AgingFile", "SalaryFile", "MetaFile"]) {
      expect(source).toMatch(new RegExp(`^export interface ${name} `, "m"));
    }
  });

  it("ne déclare Estimate qu'une seule fois", () => {
    const declarations = source.match(/^export interface Estimate /gm) ?? [];
    expect(declarations).toHaveLength(1);
  });

  it("ne contient aucun type cloné sous un nom suffixé", () => {
    const clones = source.match(/^export (?:interface|type) [A-Za-z_]+\d+\b/gm) ?? [];
    expect(clones).toEqual([]);
  });

  it("rend obligatoires les trois composantes d'une estimation", () => {
    const block = /export interface Estimate \{([\s\S]*?)\n\}/.exec(source)?.[1] ?? "";
    expect(block).toMatch(/\bpoint: number;/);
    expect(block).toMatch(/\blower: number;/);
    expect(block).toMatch(/\bupper: number;/);
    expect(block).not.toMatch(/\?:/);
  });

  it("interdit une estimation ponctuelle dans une fourchette salariale", () => {
    const block = /export interface Band \{([\s\S]*?)\n\}/.exec(source)?.[1] ?? "";
    expect(block).not.toMatch(/\bpoint\b/);
  });
});
