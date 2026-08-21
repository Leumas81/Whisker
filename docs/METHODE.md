# Méthode

Ce document est la page `/methode` du site. Il est écrit pour être lu sans formation en
statistique : chaque modèle y répond à une question, sur des données nommées, avec ses
limites énoncées. Les détails techniques vont dans les sections repliables.

Il se remplit au fil de la phase 2, en même temps que les modèles. Ce qui suit est le plan
arrêté, avec les points d'arbitrage identifiés — pas des résultats.

---

## Ce que veut dire un intervalle ici

Toutes les estimations du site sont accompagnées d'un intervalle à **80 %**, et jamais à 95 %.

Sur des effectifs de quelques dizaines de games, un intervalle à 95 % serait si large qu'il
cesserait d'informer : il dirait « entre médiocre et excellent » pour presque tout le monde.
À 80 %, l'intervalle reste lisible tout en restant honnête. Le niveau est affiché partout où
un intervalle apparaît ; il n'est jamais sous-entendu.

Les intervalles viennent d'un bootstrap paramétrique sur les effets aléatoires,
2 000 réplications.

---

## Force de ligue

*Question : à performance égale, jouer en LFL vaut-il autant que jouer en LEC ?*

**Modèle** — `metric_std ~ position + (1 | player) + (1 | team:season) + (1 | league:season)`.
Le BLUP du terme `league:season` donne la force relative de chaque ligue, saison par saison.

**Le problème central** — sans point d'ancrage, l'effet de ligue et l'effet joueur sont
confondus : une ligue peut sembler forte parce qu'elle est forte, ou parce que ses joueurs
le sont. Deux choses permettent de les séparer :

1. les joueurs qui changent de ligue et qu'on observe des deux côtés ;
2. les rencontres internationales — Worlds, MSI, EMEA Masters.

**Ces deux sources sont rapportées séparément, jamais moyennées.** Si elles divergent
fortement, c'est un signal à documenter, pas une moyenne à prendre.

<!-- Phase 2 : tableau de coefficients, diagnostics, comparaison des deux identifications. -->

---

## Équivalence inter-ligues

*Question : ce joueur de LFL, il vaudrait quoi en LEC ?*

**Modèle** — sur le sous-échantillon des transitions :
`metric_after ~ metric_before * transition_type + age + (1 | player)`.

**Le biais de sélection** — on n'observe après transition que les joueurs jugés assez bons
pour monter. Les autres n'ont pas de « après ». L'échantillon n'est donc pas représentatif,
et l'équivalence estimée est probablement optimiste.

Deux traitements possibles, à arbitrer par le propriétaire :

- **Correction** par modèle de sélection : probit de promotion, puis ratio de Mills.
- **Documentation** : ne pas corriger, mais afficher le biais et sa direction.

<!-- Phase 2 : les deux estimations, côte à côte, pour arbitrage. -->

---

## Décomposition joueur / équipe

*Question : ce joueur est bon, ou c'est son équipe qui le porte ?*

**Calcul** — `playerShare = σ²_player / (σ²_player + σ²_team:season)`, estimé globalement puis
par rôle.

**Une mise en garde qui accompagne toujours ce chiffre** — la part joueur sera mécaniquement
plus faible pour les supports, dont les métriques dépendent davantage du contexte. Cela ne
veut pas dire qu'un support compte moins que son équipe : cela veut dire que ce qu'on mesure
chez lui est plus contextuel. **Aucune comparaison inter-rôles n'est présentée sans cet
avertissement.**

---

## Vieillissement

*Question : à quel âge un joueur décline, selon son rôle ?*

**Modèle** — `mgcv::gam(metric_std ~ s(age, by = position, k = 6) + s(player, bs = "re") + league_strength)`.

**Le biais de survie** — les joueurs faibles quittent le circuit. Passé un certain âge, il ne
reste que les bons, et la courbe remonte artificiellement. Ce n'est pas un rebond de
performance, c'est une disparition des mauvais.

Deux courbes sont donc toujours exportées et affichables ensemble :

- **tous les joueurs** — sujette au biais ;
- **joueurs à N saisons minimum** — le biais est atténué, au prix d'un échantillon réduit.

L'encart sur ce biais est visible sans clic sur la page vieillissement.

---

## Estimation salariale

*Question : combien gagne-t-il, en ordre de grandeur ?*

**Calibration** — la distribution salariale d'une ligue est modélisée par une log-normale,
identifiée par ses ancres publiques :

```
médiane = exp(μ)          →  μ = log(165 000) = 12,014
moyenne = exp(μ + σ²/2)   →  σ = √(2 × (log(240 000) − μ)) = 0,867
```

On vérifie ensuite que `P(X < plancher) < 5 %`. Sinon la log-normale est tronquée à gauche
et ré-identifiée numériquement.

**L'hypothèse forte, affichée sur le site** — l'attribution individuelle se fait par
correspondance de rangs : le meilleur joueur reçoit le salaire le plus élevé. Cette monotonie
parfaite entre performance et salaire est **fausse en pratique** — l'ancienneté, la valeur
marketing et la qualité de la négociation comptent, et ne se lisent nulle part dans les
statistiques de jeu.

**C'est précisément pourquoi aucun montant ponctuel n'est jamais affiché à côté d'un nom.**
Seuls un quintile et une fourchette le sont, accompagnés de la mention : *« Estimation
statistique. Aucun salaire réel n'est connu de ce site. »* Un test automatisé fait échouer le
build si un montant en euros apparaît près d'un nom de joueur.

---

## Fiabilité d'une estimation

Le nombre de games détermine ce qu'on peut dire d'un joueur :

| Games | Fiabilité | Ce que le site en fait |
|---|---|---|
| ≥ 60 | élevée | Affichage normal |
| 25 – 59 | moyenne | Intervalle plus large, sans alerte |
| 10 – 24 | faible | Bandeau « échantillon limité », exclu des classements par défaut |
| < 10 | — | Non exporté |

Ces seuils sont inscrits dans le schéma de données, pas seulement dans ce document : un
joueur à moins de 10 games ne peut pas être exporté, la validation le refuse.
