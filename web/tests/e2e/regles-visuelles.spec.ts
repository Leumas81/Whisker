import { expect, test } from "@playwright/test";

/**
 * La règle absolue du §5.2 : --mark n'appartient qu'aux estimations ponctuelles.
 *
 * Le test inspecte les couleurs calculées de tous les éléments de la page. Un élément a le
 * droit de porter --mark seulement s'il est, ou descend d'un élément, marqué
 * `data-estimate-mark`. Cet attribut est le contrat entre le composant et ce test :
 * il n'existe que sur les marqueurs d'estimation.
 */

const MARK = "rgb(180, 39, 92)";
const PAGES = ["/"];

for (const route of PAGES) {
  test(`--mark reste réservée aux estimations sur ${route}`, async ({ page }) => {
    await page.goto(route);

    const offenders = await page.evaluate((mark) => {
      const properties = ["color", "backgroundColor", "borderTopColor", "borderRightColor", "borderBottomColor", "borderLeftColor", "outlineColor", "fill", "stroke"] as const;
      const found: string[] = [];

      for (const element of Array.from(document.querySelectorAll("*"))) {
        if (element.closest("[data-estimate-mark]")) continue;

        const styles = getComputedStyle(element);
        for (const property of properties) {
          if (styles[property] !== mark) continue;

          // Une bordure de largeur nulle ou un fond transparent ne peignent rien.
          if (property.startsWith("border")) {
            const side = property.replace("border", "").replace("Color", "");
            const width = styles.getPropertyValue(`border-${side.toLowerCase()}-width`);
            const style = styles.getPropertyValue(`border-${side.toLowerCase()}-style`);
            if (width === "0px" || style === "none") continue;
          }

          const label = element.tagName.toLowerCase() + (element.className ? `.${String(element.className).split(" ")[0]}` : "");
          found.push(`${label} → ${property}`);
        }
      }
      return found;
    }, MARK);

    expect(
      offenders,
      "La couleur d'accent ne doit servir qu'au point estimé : ni bouton, ni lien, ni titre, ni fond.",
    ).toEqual([]);
  });
}

test("le mouvement se limite à l'animation du forest plot", async ({ page }) => {
  await page.goto("/");

  const animated = await page.evaluate(() => {
    const names: string[] = [];
    for (const element of Array.from(document.querySelectorAll("*"))) {
      const styles = getComputedStyle(element);
      if (styles.animationName !== "none" && styles.animationName !== "") {
        names.push(styles.animationName);
      }
    }
    return names;
  });

  const allowed = new Set(["dessin-intervalle"]);
  expect(animated.filter((name) => !allowed.has(name))).toEqual([]);
});
