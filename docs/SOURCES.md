# Sources de données

Chaque chiffre affiché sur le site remonte à l'une de ces sources, et à un commit précis du
pipeline. Les conditions d'usage sont listées ici pour qu'elles soient vérifiables sans avoir
à lire le code.

---

## Oracle's Elixir — performances joueur/game

- **URL** : <https://oracleselixir.com/tools/downloads>
- **Forme** : un CSV par année. Une ligne par joueur et par game, plus des lignes agrégées
  d'équipe repérées par `position == "team"` — jamais exportées comme joueurs.
- **Période retenue** : 2019 à aujourd'hui.
- **Licence** : usage libre avec attribution. **L'attribution en pied de page est obligatoire
  et vérifiée par un test bout-en-bout.**
- **Colonnes utilisées** : `gameid`, `date`, `league`, `split`, `playername`, `teamname`,
  `position`, `result`, `kills`, `deaths`, `assists`, `golddiffat15`, `xpdiffat15`,
  `csdiffat15`, `damageshare`, `earnedgoldshare`, `dpm`, `vspm`, `wpm`, `gamelength`.

## Leaguepedia — API Cargo : contrats, âges, rosters

- **URL** : `https://lol.fandom.com/api.php?action=cargoquery&format=json`
- **Tables** : `Players`, `Tenures`, `Contracts`.
- **Pagination** : par `offset`, 500 lignes maximum par requête.
- **Politesse, non négociable** : en-tête `User-Agent` identifiant le projet, une seconde de
  pause entre deux requêtes, mise en cache locale des réponses. Ces trois règles sont la
  condition de l'accès ; les enfreindre exposerait le projet à un blocage mérité.
- **Attribution** : obligatoire en pied de page, au même titre qu'Oracle's Elixir.

## Ancres salariales

- **Fichier** : [`pipeline/config/salary_anchors.yaml`](../pipeline/config/salary_anchors.yaml)
- Chaque valeur porte sa source, son URL et sa date de relevé. Aucune n'est écrite en dur
  dans un script, et un test R vérifie que ces trois champs sont renseignés.

> **À faire avant la mise en ligne.** Les trois ancres LEC 2025 (moyenne 240 000 €,
> médiane 165 000 €, plancher 60 000 €) proviennent du brief et pointent pour l'instant vers
> une URL factice. Elles doivent être remplacées par leur source primaire, avec sa date.
> Tant que ce n'est pas fait, la calibration salariale n'est pas publiable.

---

## Ce que le site ne stocke pas

- **Aucune photo de joueur, aucun logo d'équipe.** Droit à l'image et marques déposées :
  le site est en texte seul. Les équipes sont nommées, jamais illustrées.
- **Aucun salaire réel.** Le site ne connaît aucun montant individuel ; il ne produit que des
  quintiles et des fourchettes issues d'une distribution calibrée.
- **Aucun tracker tiers.** Un test bout-en-bout vérifie qu'aucune requête ne sort du domaine.

## Contestation

Un joueur, une équipe ou un agent qui conteste une estimation dispose d'un moyen de contact
sur `/methode`. Une contestation reçue est traitée comme une donnée : elle peut mener à
corriger une correspondance d'identité, à retirer un joueur, ou à documenter une limite.
