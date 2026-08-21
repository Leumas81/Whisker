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

## Ce qu'on mesure : `metric_std`

*Question : de quoi parle-t-on quand on dit qu'un joueur « performe » ?*

Tous les modèles qui suivent portent sur une même grandeur. La voici, en entier. Sa
définition exécutable vit dans [`pipeline/config/metric.yaml`](../pipeline/config/metric.yaml) :
le code R y lit les formules plutôt que de les recopier, et un test vérifie qu'aucune
constante de la métrique n'existe ailleurs.

### Le principe de sélection

On ne retient que des grandeurs **relatives** : soit à l'adversaire direct, soit à la propre
équipe du joueur. Les grandeurs absolues — dégâts par minute, or total, éliminations brutes —
mesurent surtout l'état de la partie. Une équipe qui gagne gonfle les compteurs de ses cinq
joueurs, y compris celui qui n'a rien fait. Les inclure reviendrait à mélanger l'effet joueur
et l'effet équipe *avant* que le modèle ait la moindre chance de les séparer.

### Les huit composants

| Composant | Formule | Ce qu'il capte |
|---|---|---|
| Différentiel d'or à 15 min | `golddiffat15` | Le cœur de la phase de lane, face à l'adversaire du même poste |
| Différentiel d'expérience | `xpdiffat15` | La pression exercée même sans avantage d'or |
| Différentiel de farm | `csdiffat15` | L'avantage de ressources en lane |
| Part des dégâts | `damageshare` | La contribution offensive au sein de l'équipe |
| Rendement | `damageshare − earnedgoldshare` | Ce qu'on produit moins ce qu'on consomme |
| Participation | `(kills + assists) / éliminations de l'équipe` | La présence sur les temps forts |
| Survie | `−10 × morts / minutes` | Mourir, l'un des rares événements purement individuels |
| Vision | `vspm` | Le travail d'information |

Le **rendement** mérite un mot : positif, il dit que le joueur convertit mieux que ses
coéquipiers les ressources qu'on lui confie. C'est le composant le moins contaminé par la
richesse de l'équipe, puisque les deux parts sont mesurées sur la même base.

### Quels composants comptent pour quel poste

Un composant n'entre dans le calcul d'un poste que s'il y porte du signal.

| | top | jng | mid | adc | sup |
|---|:---:|:---:|:---:|:---:|:---:|
| Or, expérience, rendement, participation, survie | ✓ | ✓ | ✓ | ✓ | ✓ |
| Farm | ✓ | ✓ | ✓ | ✓ | — |
| Part des dégâts | ✓ | ✓ | ✓ | ✓ | — |
| Vision | — | ✓ | — | — | ✓ |

Le farm d'un support est un sous-produit de son objet de départ, pas une performance ; sa
part de dégâts est structurellement au plancher et varie peu. À l'inverse, le score de vision
d'un solo-laner reflète surtout l'économie de wards de son équipe.

**Ces exclusions sont des hypothèses, pas des évidences.** La phase 2 rapporte, pour chaque
composant et chaque poste, la part de variance attribuable au joueur. Un composant écarté qui
se révélerait porteur de signal réintègre le calcul — en changeant une ligne du fichier de
configuration, et rien d'autre.

### Le traitement, en quatre gestes

1. **Winsorisation** aux 1ᵉʳ et 99ᵉ centiles, par poste et par saison. Une partie de soixante
   minutes ne doit pas dominer la moyenne d'un joueur. Les queues sont ramenées, pas jetées.
2. **Centrage-réduction** par poste et par saison, **sur la population LEC de référence**.
   Un zéro signifie donc « joueur LEC moyen à ce poste, cette saison-là ».
3. **Moyenne à poids égaux** des composants retenus.
4. **Nouveau centrage-réduction** du composite, sur la même référence.

Deux de ces gestes demandent une justification.

<details>
<summary><strong>Pourquoi standardiser par saison, et pourquoi contre la LEC</strong></summary>

Standardiser par saison absorbe la dérive du méta — inflation de l'or, évolution de la durée
des parties, changements d'objectifs — qui autrement se confondrait avec un changement de
niveau. Mais cela n'absorbe **pas** les écarts entre ligues à l'intérieur d'une même saison,
qui sont précisément ce que le modèle de force de ligue cherche à estimer. Si l'on
standardisait par ligue-saison, l'effet à mesurer serait effacé avant même d'être estimé.

Prendre la LEC comme référence plutôt que l'échantillon poolé a deux vertus. L'échelle devient
interprétable — « à 0,4 écart-type sous le mid LEC moyen » veut dire quelque chose, « sous la
moyenne d'un mélange LEC-LFL dont la composition change chaque année » ne veut rien dire. Et
l'ajout futur d'une ligue ne déplace pas l'étalon : les estimations passées restent valides.

</details>

<details>
<summary><strong>Pourquoi des poids égaux</strong></summary>

C'est le point où l'on attend un choix, et où le refus d'en faire un est le bon choix.

Des poids que j'aurais fixés au jugé seraient arbitraires, et personne — moi compris — ne
pourrait dire pourquoi le différentiel d'or vaudrait 0,3 et la survie 0,15. Des poids estimés
sur les données seraient instables : huit composants corrélés entre eux, quinze mille lignes,
et une incertitude d'estimation qu'il faudrait ensuite propager jusqu'aux intervalles affichés.

Les poids unitaires sur variables centrées-réduites ont pour eux un résultat classique
(Dawes, 1979, *The robust beauty of improper linear models in decision making*) : sur des
prédicteurs corrélés et des effectifs modestes, ils égalent ou battent régulièrement les poids
estimés en validation externe. Ils ont surtout ceci qu'on ne peut pas les ajuster pour obtenir
le classement qu'on espérait.

**Ce n'est pas un acte de foi.** La phase 2 recalcule le classement avec deux pondérations
alternatives — première composante principale intra-poste, et poids issus d'un modèle
logistique du résultat de la partie. Si les trois classements concordent (ρ de Spearman ≥ 0,95),
le choix des poids n'a pas d'importance et on le dit. S'ils divergent, la divergence est
présentée avant d'être tranchée.

</details>

### De la métrique à l'indice affiché

L'indice de valeur n'est **pas** la moyenne des `metric_std` d'un joueur. C'est son effet
aléatoire estimé par le modèle — donc débarrassé, autant que possible, de la qualité de son
équipe — rapporté à la dispersion des effets joueurs :

```
indice = 50 + 15 × (effet du joueur / écart-type des effets joueurs)
```

Un joueur LEC moyen est à 50. Le meilleur d'une ligue de cinquante titulaires tourne autour
de 80. Les bornes de l'intervalle subissent la même transformation, qui est monotone :
l'ordre et la couverture sont préservés.

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

**D'où viennent les chiffres** — aucun club ne publie ses salaires. Trois valeurs LEC servent
de socle, et leur nature diffère :

| Valeur | Montant | Nature |
|---|---|---|
| Moyenne 2025 | 240 000 € (± 20 000) | Enquête journalistique, sources confidentielles |
| Médiane 2025 | 165 000 € (± 10 000) | Même enquête |
| Plancher | 60 000 € | **Règlement Riot** — pas une estimation |

Les deux premières viennent de l'enquête de Sheep Esports signée LEC Wooloo, publiée le
20 janvier 2025, qui a recoupé la rémunération des cinquante joueurs actifs de LEC sur les
splits Summer 2024 et Winter 2025, avec une précision annoncée de ± 20 000 € dans plus de
95 % des cas. Ce n'est pas une divulgation officielle, et le site le dit.

**Calibration** — la distribution est modélisée par une log-normale identifiée par ces deux
moments :

```
médiane = exp(μ)          →  μ = log(165 000) = 12,014
moyenne = exp(μ + σ²/2)   →  σ = √(2 × (log(240 000) − μ)) = 0,866
```

**Cette loi est inadmissible telle quelle.** Elle place **12,1 %** des joueurs de LEC sous le
plancher réglementaire de 60 000 €, ce qui ne peut pas exister : le plancher est une règle,
pas une tendance. La troncature à gauche prévue au §4.5 n'est donc pas une éventualité, c'est
une obligation. Après ré-identification numérique :

```
μ = 11,782    σ = 0,921    support tronqué à 60 000 €
```

Cette loi restitue exactement les deux ancres — moyenne 240 000 €, médiane 165 000 € — tout
en n'attribuant aucune masse sous le plancher. Un test vérifie qu'aucun quantile, de 0 à 99 %,
ne descend en dessous.

**Contrôle indépendant.** Les moyennes par poste publiées dans la même enquête (mid 345 000 €,
jungle 250 000 €, ADC 240 000 €, top 192 000 €, support 168 000 €) ne servent pas à calibrer :
elles servent à vérifier que la loi obtenue les contient toutes entre ses 5ᵉ et 95ᵉ centiles.

### La LFL n'a pas d'estimation salariale, et c'est le résultat

La LFL ne dispose d'aucune enquête équivalente. Ce qui existe :

- un **plafond réglementaire** de 250 000 € pour les cinq salaires les plus élevés d'une
  équipe, entré en vigueur pour la saison 2025 — il majore la moyenne à 50 000 € par titulaire
  sans dire où elle se situe réellement sous ce plafond ;
- une **fourchette déclarative** de 2022, de 1 500 à 12 000 € mensuels sur onze mois payés,
  recueillie en plateau auprès d'un journaliste de *L'Équipe* et d'un agent de joueurs.

Deux bornes prises à trois ans d'écart, dont l'une précède l'instauration du plafond, ne font
pas une distribution. Les joueurs de LFL sortent donc du pipeline **sans quintile ni
fourchette salariale**, et la page l'affiche en toutes lettres plutôt que de meubler.

La règle est écrite dans la configuration et appliquée par le code : une ligue n'est calibrée
que si elle porte au moins deux moments indépendants relevés sur la même période. Un test
vérifie qu'une ligue déclarée publiable sans ces deux moments fait échouer le pipeline.

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
