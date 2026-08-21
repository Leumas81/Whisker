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
- Chaque valeur porte sa source, son URL, sa méthode d'obtention et deux dates : celle de la
  publication et celle du relevé. Des tests vérifient que ces cinq champs sont renseignés,
  qu'aucune URL n'est factice, et que toutes sont en HTTPS.

**Rappel qui commande tout le reste : aucun club ne publie ses salaires.** Ce qui suit se
répartit en deux natures très différentes, et le site ne les présente jamais comme équivalentes.

### Valeurs réglementaires — factuelles

| Valeur | Montant | Source |
|---|---|---|
| Plancher LEC | 60 000 €/an | Règlement LEC de Riot Games |
| Plafond LFL | 250 000 € pour les 5 titulaires | Règlement Financier Sportif LFL, saison 2025 |

Le plancher LEC découle d'un minimum de 1 000 € bruts mensuels majoré de 1 000 € par semaine
de match disputée. Le plafond LFL est projeté à 300 000 € en 2027.

### Valeurs estimées — enquête journalistique

| Valeur | Montant | Précision annoncée |
|---|---|---|
| Moyenne LEC 2025 | 240 000 € | ± 20 000 € dans plus de 95 % des cas |
| Médiane LEC 2025 | 165 000 € | ± 10 000 € |

Source : Sheep Esports, enquête « Everything about LEC salaries unveiled » signée LEC Wooloo,
publiée le 20 janvier 2025. Rémunérations des cinquante joueurs actifs de LEC sur les splits
Summer 2024 et Winter 2025, recoupées auprès de sources confidentielles. Les salaires
individuels n'ont volontairement pas été publiés par l'enquête, et ce site n'en dispose donc
pas davantage.

La même enquête publie des moyennes par poste — mid 345 000 €, jungle 250 000 €, ADC
240 000 €, top 192 000 €, support 168 000 € — qui servent ici de contrôle de plausibilité, pas
de calibration.

### LFL : sources insuffisantes, aucune estimation publiée

La seule fourchette disponible date de novembre 2022 : 1 500 à 12 000 € mensuels sur onze mois
payés, recueillie sur le plateau de *L'Apéritif de Solary* auprès de Paul Arrivé (*L'Équipe*)
et d'un agent de joueurs. Elle précède de trois ans le plafond salarial et décrit un marché
qui n'existe plus sous cette forme.

Un plafond qui majore sans situer, et une fourchette antérieure à ce plafond, ne suffisent pas
à identifier une distribution. **Aucune estimation salariale n'est produite pour la LFL**, et
la page le dit.

### Ce qu'il reste à faire

Sheep Esports a annoncé une nouvelle édition de son enquête pour 2026. Quand elle paraîtra,
les deux ancres LEC devront être remplacées et `retrieved_at` mis à jour ; l'ancienne édition
restera dans l'historique git.

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
