import { describe, expect, it } from "vitest";
import { dedupeTypes } from "../../../tools/lib/dedupe-types.mjs";

/**
 * La passe de fusion réécrit le fichier de types. Une erreur y produirait un fichier
 * syntaxiquement cassé ou, pire, silencieusement amputé — d'où ces tests.
 */

const ESTIMATE = `/**
 * Une estimation.
 */
export interface Estimate {
  point: number;
  lower: number;
  upper: number;
}
`;

const CLONE = ESTIMATE.replace("Estimate {", "Estimate1 {");

describe("fusion des types clonés", () => {
  it("supprime un clone identique et réécrit ses références", () => {
    const source = `${ESTIMATE}${CLONE}export interface Player {\n  valueIndex: Estimate1;\n}\n`;
    const { output, mergedNames, divergentNames } = dedupeTypes(source);

    expect(mergedNames).toEqual(["Estimate1"]);
    expect(divergentNames).toEqual([]);
    expect(output).not.toContain("Estimate1");
    expect(output).toContain("valueIndex: Estimate;");
    expect(output.match(/^export interface Estimate \{/gm)).toHaveLength(1);
  });

  it("conserve et signale un type suffixé de forme différente", () => {
    const divergent = `export interface Estimate1 {\n  point: number;\n}\n`;
    const source = `${ESTIMATE}${divergent}`;
    const { output, mergedNames, divergentNames } = dedupeTypes(source);

    expect(mergedNames).toEqual([]);
    expect(divergentNames).toEqual(["Estimate1"]);
    expect(output).toContain("Estimate1");
  });

  it("laisse intact un fichier sans clone", () => {
    const source = `${ESTIMATE}export interface Player {\n  valueIndex: Estimate;\n}\n`;
    expect(dedupeTypes(source).output).toBe(source);
  });

  it("ne confond pas un nom qui se termine par un chiffre sans type de base", () => {
    const source = `export interface Top10 {\n  rang: number;\n}\n`;
    const { output, mergedNames } = dedupeTypes(source);
    expect(mergedNames).toEqual([]);
    expect(output).toBe(source);
  });

  it("traverse une ligne vide entre deux déclarations", () => {
    const source = `export type IsoDate = string;\n\nexport type IsoDate1 = string;\n\nexport interface Meta {\n  date: IsoDate1;\n}\n`;
    const { output, mergedNames } = dedupeTypes(source);
    expect(mergedNames).toEqual(["IsoDate1"]);
    expect(output).toContain("date: IsoDate;");
    expect(output).not.toContain("IsoDate1");
  });

  it("ne découpe pas une interface à son premier point-virgule", () => {
    const source = `export interface Player {\n  name: string;\n  games: number;\n}\nexport interface Team {\n  name: string;\n}\n`;
    const { output } = dedupeTypes(source);
    expect(output).toBe(source);
    expect(output).toContain("games: number;");
  });

  it("refuse de réécrire un fichier dont le découpage est incohérent", () => {
    // Alias sans point-virgule : son motif s'étend jusqu'au suivant et engloberait
    // l'interface intercalée. Plutôt que de découper au mauvais endroit, on s'arrête.
    const source =
      `export type Casse = number\n` +
      `export interface Intercalee {\n  x: number;\n}\n` +
      `export type Suivant = string;\n`;
    expect(() => dedupeTypes(source)).toThrow(/chevauchent/);
  });
});
