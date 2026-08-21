# Journal des décisions techniques

Une entrée par décision qui serait coûteuse à défaire. Le format est fixe : ce qui a été
décidé, pourquoi, et ce qui ferait changer d'avis. Les décisions sans conséquence ne sont
pas consignées — ce fichier doit rester lisible d'un bout à l'autre.

---

## D-001 — La racine du dépôt est `LOL_Whisker/`, pas `whisker/`

**Décidé.** L'arborescence du brief (§2.3) place tout sous `whisker/`. Le dépôt étant déjà
créé dans `LOL_Whisker/`, ce dossier fait office de racine ; aucun niveau `whisker/`
intermédiaire n'est ajouté.

**Pourquoi.** Un dossier `LOL_Whisker/whisker/` n'apporterait rien et allongerait tous les
chemins. La structure interne, elle, suit le brief à la lettre.

**Ce qui ferait changer d'avis.** Rien.

---

## D-002 — Un sixième schéma, `common.schema.json`, porte les définitions partagées

**Décidé.** Aux cinq schémas du brief s'ajoute `common.schema.json`, qui définit `Estimate`,
`UnitEstimate`, `Band`, `Role`, `LeagueId`, `Reliability`, `Season`, `Slug` et `IsoDate`.

**Pourquoi.** Le §3.3 exige que `Estimate` soit « défini une fois et référencé partout via
`$ref` ». Il fallait bien un fichier pour l'héberger. Le placer dans l'un des cinq schémas
métier aurait créé une dépendance arbitraire entre contrats.

**Écart au brief.** Un fichier de plus dans `schemas/`, signalé ici comme demandé au §0.3.

---

## D-003 — La contrainte `lower ≤ point ≤ upper` passe par un mot-clé maison

**Décidé.** JSON Schema ne sait pas comparer deux propriétés d'un même objet. La contrainte
est déclarée dans le schéma sous la forme `"orderedProperties": ["lower", "point", "upper"]`
et vérifiée par un mot-clé ajv générique, écrit une fois dans `tools/lib/validator.mjs`.

**Pourquoi.** Les alternatives étaient toutes pires : dupliquer la règle en TypeScript et en R
(dérive garantie), ou la reléguer hors du schéma (qui cesserait d'être la source unique de
vérité). Ici la règle vit dans le schéma, et le vérificateur ne la connaît pas — il lit
l'annotation. Le même mécanisme servira côté R en phase 3.

**Ce qui ferait changer d'avis.** Une future version de JSON Schema exprimant les
comparaisons inter-propriétés.

---

## D-004 — Les notes propres à un champ passent par `fieldNote`, pas `description`

**Décidé.** Un `description` placé à côté d'un `$ref` est déplacé dans un mot-clé
d'annotation `fieldNote`, sans effet de validation.

**Pourquoi.** `json-schema-to-typescript` clone le type référencé sous un nom suffixé
(`UnitEstimate1`, `UnitEstimate2`…) dès qu'une référence porte un mot-clé frère, et la
description du champ écrase alors celle du type. On obtenait quatre `UnitEstimate`
identiques. La note reste lisible dans le schéma et exploitable par le code R.

---

## D-005 — Une passe de fusion nettoie les types clonés restants

**Décidé.** `tools/lib/dedupe-types.mjs` fusionne les déclarations suffixées dont le corps
est **rigoureusement identique** à celui du type de base, et réécrit les références.

**Pourquoi.** Le générateur clone dès qu'un mot-clé frère existe, y compris `fieldNote`.
Un fichier importé dans tout le site ne doit pas exposer `UnitEstimate3`.

**Garde-fous.** La fusion refuse d'opérer si le découpage des déclarations est incohérent,
signale les types suffixés de forme *différente* au lieu de les masquer, et vérifie en
post-condition qu'aucun nom fusionné n'est encore référencé. Sept tests unitaires couvrent
ces cas, dont deux bugs réellement rencontrés pendant l'écriture.

---

## D-006 — `pnpm verify` est un script Node, pas une chaîne de commandes

**Décidé.** `tools/verify.mjs` exécute les huit étapes séquentiellement et affiche un
récapitulatif chiffré.

**Pourquoi.** Un enchaînement `a && b && c` s'arrête à la première erreur : on ne sait pas si
les étapes suivantes passaient. Le script les exécute toutes et rend un tableau. Il accepte
aussi un nom d'étape (`node tools/verify.mjs types`) pour rejouer un seul contrôle.

---

## D-007 — Vite est épinglé en `^6.4.1`

**Décidé.** Une surcharge pnpm force une seule version de Vite dans l'arbre.

**Pourquoi.** Astro 5.18 dépend de Vite 6 ; `@tailwindcss/vite` accepte Vite 5 à 8 et tirait
Vite 7. Deux Vite, donc deux jeux de types incompatibles, et `astro check` échouait sur la
configuration elle-même.

**Ce qui ferait changer d'avis.** Le passage d'Astro à Vite 7 : la surcharge devra suivre.

---

## D-008 — `data-estimate-mark` est le contrat entre les composants et le test de couleur

**Décidé.** Tout élément peignant `--mark` doit porter, lui ou un ascendant, l'attribut
`data-estimate-mark`. Un test Playwright inspecte les couleurs calculées de tous les autres
éléments et échoue s'il en trouve un.

**Pourquoi.** La règle du §5.2 (« `--mark` ne sert qu'aux estimations ponctuelles ») n'est
vérifiable par une machine que si les marqueurs sont reconnaissables. L'attribut le dit
explicitement, plutôt que de laisser le test deviner à partir de noms de classes.

**Vérifié.** Le test a été mis en échec volontairement en repeignant le titre de la page
d'accueil : il détecte la violation et nomme l'élément fautif.

---

## D-009 — L'intégration React reste installée sans îlot

**Décidé.** `@astrojs/react` est configuré dès la phase 0, bien qu'aucun îlot n'existe encore.

**Pourquoi.** Le build produit un fragment client de 195 Ko qu'aucune page ne référence —
il n'est donc jamais servi. Le retirer pour le réintroduire en phase 5 ne ferait qu'ajouter
un aller-retour de configuration.

**À revoir.** En phase 7, si Lighthouse s'en plaint.

---

## D-010 — `validate:data` tolère l'absence de données, sauf en CI de pipeline

**Décidé.** Par défaut le script valide ce qui existe et signale ce qui manque. Le drapeau
`--require-all`, employé par `pipeline.yml`, exige les cinq fichiers.

**Pourquoi.** Tant que le pipeline n'a pas tourné, exiger les données bloquerait `pnpm verify`
sans rien apprendre. Là où l'absence est une panne — après exécution du pipeline, avant
déploiement — le drapeau la traite comme telle. Un fichier présent dans `web/src/data/` mais
absent de la table des contrats fait toujours échouer la validation, dans les deux régimes.

---

## D-011 — Les seuils du brief sont encodés dans les schémas, pas seulement documentés

**Décidé.** `games` a un minimum de 10, `unmatchedRate` un maximum de 0,02, `salaryQuintile`
est borné à 1–5, et `Band` n'a structurellement pas de champ `point`.

**Pourquoi.** Le §3.4 dit qu'en dessous de 10 games un joueur n'est pas exporté, le §3.2 que
le pipeline échoue au-delà de 2 % de non-résolution, le §6.6 qu'aucun montant ponctuel ne
doit exister. Écrites dans le schéma, ces règles sont vérifiées à chaque export plutôt que
confiées à la vigilance du code qui produit les données.

---

## D-012 — Les paquets R s'installent en binaire, jamais depuis les sources

**Décidé.** `pipeline/bootstrap.R` passe `type = "binary"` à `renv::install`.

**Pourquoi.** Les dépôts source et binaire de CRAN ne sont pas au même niveau. Sur cette
machine, le binaire proposait `httr2` 1.2.2 et `rlang` 1.2.0 pendant que la source proposait
`httr2` 1.3.0, lequel exige `rlang >= 1.3.0`. renv mélangeait les deux et l'installation
échouait sur un conflit d'espace de noms. En binaire exclusif, l'ensemble est cohérent.
Sous Linux, Posit sert également des binaires : la CI est logée à la même enseigne.

---

## D-013 — `pipeline/_dependencies.R` déclare les paquets pour renv

**Décidé.** Un fichier jamais exécuté liste les `library()` du projet, avec l'usage et la
phase de chaque paquet.

**Pourquoi.** renv détecte les dépendances en lisant les appels `library()`. Tant que les
étapes des phases 1 à 3 sont des squelettes, il n'en trouve aucun et déclare le projet
désynchronisé à chaque lancement de R. Ce fichier est l'idiome renv pour ce cas, et il rend
lisible d'un coup d'œil ce dont le pipeline dépend et pourquoi.

---

## D-014 — `pnpm verify` inclut les tests R quand R est disponible, et les saute sinon

**Décidé.** L'étape `pipeline` de `verify` cherche `Rscript` sur le `PATH` ou dans
`WHISKER_RSCRIPT`. Absent, elle est marquée « ignorée » sans faire échouer la commande.

**Pourquoi.** Le §0.2 veut une commande unique qui exécute tout. Mais imposer une
installation de R à qui ne touche qu'au site serait une friction inutile, et la CI exécute
ces tests dans un job dédié de toute façon. L'étape est donc incluse quand elle peut l'être,
et son absence est annoncée à l'écran plutôt que silencieuse.

---

## D-015 — La trajectoire par saison porte des intervalles, pas des points nus

**Écart au brief, signalé.** L'exemple de `player.schema.json` au §3.3 montre
`history[].valueIndex` comme un nombre seul (`66.0`). Le schéma en fait un `Estimate`.

**Pourquoi.** Le §6.3 demande une « trajectoire par saison avec barres d'incertitude », ce
qui suppose un intervalle par point, et le §1.2 pose qu'aucun chiffre n'est jamais affiché
seul. Un scalaire dans l'historique aurait rendu l'un des deux irréalisable. Le coût est
négligeable : deux nombres de plus par saison et par joueur.
