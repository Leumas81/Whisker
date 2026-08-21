/**
 * Fusionne les types clonés produits par json-schema-to-typescript.
 *
 * Le générateur redéclare un type sous un nom suffixé (« UnitEstimate1 ») dès qu'une
 * référence porte un mot-clé frère du `$ref`. Ces clones sont structurellement identiques
 * à leur type de base et ne font qu'encombrer un fichier importé dans tout le site.
 *
 * La fusion n'a lieu que si les corps sont rigoureusement identiques. Si deux types portent
 * des noms voisins mais des formes différentes, ils sont conservés tous les deux et signalés :
 * c'est le symptôme d'un vrai problème de schéma, pas du bruit à masquer.
 */

/**
 * Un bloc JSDoc, sans jamais traverser sa propre fermeture. Sans cette précaution le
 * préfixe optionnel avale tout le texte séparant deux déclarations.
 */
const JSDOC = String.raw`(?:^/\*\*(?:(?!\*/)[\s\S])*\*/\n)?`;

/** Ce qui suit une déclaration : une autre déclaration, ou la fin du fichier. */
const NEXT = String.raw`\n*(?=/\*\*|export |(?![\s\S]))`;

/** Interface : se termine à l'accolade fermante en début de ligne. */
const INTERFACE = new RegExp(
  JSDOC + String.raw`^export interface ([A-Za-z0-9_]+) \{\n[\s\S]*?\n\}\n` + NEXT,
  "gm",
);

/** Alias : se termine au point-virgule qui précède la déclaration suivante. */
const ALIAS = new RegExp(
  JSDOC + String.raw`^export type ([A-Za-z0-9_]+) =[\s\S]*?;\n` + NEXT,
  "gm",
);

function splitDeclarations(source) {
  const blocks = [];
  for (const pattern of [INTERFACE, ALIAS]) {
    pattern.lastIndex = 0;
    for (const match of source.matchAll(pattern)) {
      blocks.push({
        name: match[1],
        text: match[0],
        start: match.index,
        end: match.index + match[0].length,
      });
    }
  }
  return blocks.sort((a, b) => a.start - b.start);
}

export function dedupeTypes(source) {
  const blocks = splitDeclarations(source);

  // Deux blocs qui se chevauchent signalent une extraction fautive : mieux vaut ne rien
  // toucher que de découper le fichier au mauvais endroit.
  for (let i = 1; i < blocks.length; i += 1) {
    if (blocks[i].start < blocks[i - 1].end) {
      throw new Error(
        `Découpage des déclarations incohérent : « ${blocks[i - 1].name} » et « ${blocks[i].name} » se chevauchent.`,
      );
    }
  }

  const byName = new Map(blocks.map((block) => [block.name, block]));
  const merged = [];
  const divergentNames = [];

  for (const block of blocks) {
    const suffix = /^([A-Za-z_][A-Za-z0-9_]*?)\d+$/.exec(block.name);
    if (!suffix) continue;
    const base = byName.get(suffix[1]);
    if (!base) continue;

    // Comparaison à espace de fin près : une déclaration peut être suivie d'une ligne vide
    // sans que sa forme en soit changée.
    if (block.text.replaceAll(block.name, base.name).trimEnd() === base.text.trimEnd()) {
      merged.push({ ...block, base: base.name });
    } else {
      divergentNames.push(block.name);
    }
  }

  let output = source;
  for (const block of [...merged].sort((a, b) => b.start - a.start)) {
    output = output.slice(0, block.start) + output.slice(block.end);
  }
  for (const block of merged) {
    output = output.replaceAll(new RegExp(`\\b${block.name}\\b`, "g"), block.base);
  }

  // Post-condition : plus aucune trace des noms fusionnés, sans quoi le fichier référencerait
  // un type qui n'existe plus.
  for (const block of merged) {
    if (new RegExp(`\\b${block.name}\\b`).test(output)) {
      throw new Error(`Le type fusionné « ${block.name} » est encore référencé après réécriture.`);
    }
  }

  return { output, mergedNames: merged.map((block) => block.name), divergentNames };
}
