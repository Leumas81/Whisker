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

---

## D-016 — `metric_std` est un composite relatif à poids égaux, standardisé sur la LEC

**Décidé.** Le brief emploie `metric_std` sans le définir. La définition est fixée dans
`pipeline/config/metric.yaml` : huit composants tous relatifs — à l'adversaire direct ou à la
propre équipe du joueur — winsorisés aux centiles extrêmes, centrés-réduits par poste et par
saison sur la population LEC, puis moyennés à poids égaux sur les seuls composants retenus
pour le poste.

**Pourquoi des grandeurs relatives.** Les compteurs absolus mesurent surtout l'état de la
partie : une équipe qui gagne gonfle les statistiques de ses cinq joueurs. Les inclure
mélangerait l'effet joueur et l'effet équipe avant que le modèle ait la chance de les séparer,
et le §4.3 n'aurait plus rien à décomposer.

**Pourquoi standardiser par saison et non par ligue-saison.** Standardiser par saison absorbe
la dérive du méta sans absorber les écarts entre ligues à l'intérieur d'une saison — qui sont
exactement ce que le §4.1 cherche à estimer. Standardiser par ligue-saison effacerait l'effet
avant de l'estimer. Un test le vérifie sur données synthétiques : un décalage introduit entre
ligues doit survivre à la standardisation.

**Pourquoi la LEC comme référence.** Un zéro veut alors dire « joueur LEC moyen à ce poste
cette saison-là », ce qui donne son sens à l'équivalence du §4.2. Et l'ajout d'une ligue ne
déplace pas l'étalon : les estimations passées restent valides.

**Pourquoi des poids égaux.** Des poids fixés au jugé seraient arbitraires ; des poids estimés
sur huit composants corrélés seraient instables et leur incertitude devrait être propagée
jusqu'aux intervalles affichés. Sur prédicteurs corrélés et effectifs modestes, les poids
unitaires égalent ou battent régulièrement les poids estimés en validation externe
(Dawes, 1979). Ils ont surtout ceci qu'on ne peut pas les ajuster pour obtenir le classement
espéré.

**Ce qui ferait changer d'avis.** La phase 2 recalcule le classement avec deux pondérations
alternatives — première composante principale, et poids issus d'un modèle logistique du
résultat. Un ρ de Spearman inférieur à 0,95 déclenche un arbitrage plutôt qu'un choix
silencieux. De même, la matrice d'inclusion par poste est une hypothèse : la phase 2 rapporte
la part de variance joueur de chaque composant, et un composant écarté à tort réintègre le
calcul en changeant une ligne de configuration.

---

## D-017 — La configuration de la métrique est exécutable, pas décorative

**Décidé.** Le code R évalue le champ `expression` de chaque composant plutôt que de recopier
la formule. Un test vérifie qu'aucune clé de composant, aucun centile et aucun nom de ligue de
référence n'apparaît en littéral dans `pipeline/R/lib/metric.R`.

**Pourquoi.** Un fichier de configuration que le code se contente de commenter n'est pas une
source de vérité : c'est une documentation qui dérive. Ce test est né d'un vrai défaut — la
première version recopiait les huit formules en R, et rien n'aurait signalé une divergence.

---

## D-018 — Les ancres salariales sont sourcées, et leur nature est distinguée

**Décidé.** Les valeurs du brief sont conservées, mais rattachées à leur source primaire et
qualifiées. Deux natures, jamais présentées comme équivalentes : les valeurs **réglementaires**
(plancher LEC de 60 000 €, plafond LFL de 250 000 €) sont factuelles ; les valeurs
**estimées** (moyenne 240 000 €, médiane 165 000 €) viennent d'une enquête de Sheep Esports
signée LEC Wooloo, publiée le 20 janvier 2025 sur les cinquante joueurs actifs de LEC, à
± 20 000 € près.

**Conséquence trouvée en chemin.** Avec ces ancres, la log-normale non tronquée place 12,1 %
des joueurs de LEC sous le plancher réglementaire — ce qui ne peut pas exister. La troncature
à gauche du §4.5 n'est donc pas conditionnelle, elle est obligatoire. La ré-identification
numérique donne μ = 11,782 et σ = 0,921, restituant exactement les deux ancres.

---

## D-019 — La LFL ne reçoit aucune estimation salariale

**Décidé.** Une ligue n'est calibrée que si elle porte au moins deux moments indépendants
relevés sur la même période. La LFL n'en a pas : un plafond réglementaire de 2025 qui majore
la moyenne sans la situer, et une fourchette déclarative de 2022 antérieure à ce plafond.
`salaryQuintile` et `salaryBand` deviennent donc nullables dans le schéma, et le fichier
`salary.json` gagne une liste `excluded` qui nomme les ligues écartées et la raison.

**Pourquoi rendre l'absence explicite.** Un champ nul sans explication se lit comme un bug.
Une ligue nommée dans `excluded` avec sa raison se lit comme une décision. Le §5.6 demande un
site qui dit ce qu'il sait et ce qu'il ignore : c'en est l'application la plus directe.

**Écart au brief, signalé.** Le §3.3 donnait ces deux champs comme toujours présents.

**Ce qui ferait changer d'avis.** Une enquête LFL comparable à celle de Sheep Esports sur la
LEC, ou toute source donnant une médiane sur la même période que le plafond.

---

## D-020 — Oracle's Elixir passe par Google Drive, et les identifiants sont de la configuration

**Décidé.** Les identifiants Drive des fichiers annuels vivent dans `config/leagues.yaml`.
L'étape 01 vérifie que le fichier reçu commence bien par un en-tête CSV portant `gameid`, et
s'arrête en nommant la cause si Google renvoie une page HTML.

**Pourquoi.** Le bucket S3 historique (`oracleselixir-downloadable-match-data`) n'existe plus.
La distribution se fait par Google Drive, dont le quota de téléchargement public s'épuise et
qui répond alors une page HTML avec un code 200. Sans ce contrôle, un fichier HTML se ferait
passer pour un CSV et l'erreur n'apparaîtrait que bien plus loin, sous une forme illisible.

**Ce qui ferait changer d'avis.** Un retour à une distribution par URL stable.

---

## D-021 — Un jeu de développement synthétique traverse les vraies étapes du pipeline

**Décidé.** `pipeline/fixtures/generate.R` fabrique un jeu de la forme exacte du vrai, puis
lui fait traverser les étapes 04 à 08 réelles — mêmes modèles, mêmes validations, mêmes
schémas. `meta.json` porte alors `synthetic: true`.

**Pourquoi.** Les deux sources sont hors d'atteinte depuis certaines machines : quota Drive
épuisé côté Oracle's Elixir, limitation d'IP partagée côté API Cargo. Sans données, ni le
forest plot ni les six pages ne pouvaient être construits ni relus. Faire traverser les vraies
étapes plutôt qu'écrire des JSON à la main a un second effet : cela vérifie que la chaîne de
modélisation fonctionne de bout en bout. Elle a d'ailleurs révélé quatre défauts réels — un
diagnostic `plot.gam` mal appelé, `metric_std` non recalculé à l'export, un quintile supérieur
infini, et des auto-références `$ref` que le validateur R ne sait pas résoudre.

---

## D-022 — Construire n'est pas publier : `meta.synthetic` et `check:release`

**Décidé.** `pnpm verify` accepte des données synthétiques ; `node tools/check-release.mjs`
les refuse. Le workflow de déploiement passe par ce second verrou. Tant que `synthetic` est
vrai, chaque page affiche un bandeau permanent, et un test bout-en-bout vérifie qu'aucune page
ne l'omet.

**Pourquoi.** Le §0.2 interdit que des données fictives atteignent la production. Il ne dit
pas qu'elles ne peuvent pas servir à construire. La distinction est portée par le drapeau, par
le verrou et par le bandeau — trois barrières plutôt qu'une consigne.

---

## D-023 — `--muted` et `--flag` sont assombris par rapport au §5.2

**Écart au brief, signalé.** Les valeurs du §5.2 donnaient 3,85:1 pour `--muted` et 4,14:1
pour `--flag` sur le fond de page, sous le seuil AA de 4,5. Elles passent respectivement à
`#5C6874` et `#8F5C00`, soit 5,26:1 sur le fond de page et 4,62:1 sur les panneaux.

**Pourquoi.** Le §7 exige un audit axe-core sans violation et Lighthouse ≥ 95 en
accessibilité ; les deux sont incompatibles avec les valeurs d'origine. La teinte est
conservée, seule la luminosité change, et le calcul est reproductible.

---

## D-024 — Le forest plot ne contient aucun lien

**Décidé.** Les lignes du graphique sont cliquables à la souris, mais ne sont pas des `<a>` et
n'apparaissent pas dans l'ordre de tabulation. Un lien visible sous le graphique et la vue
tableau de `/joueurs` assurent la navigation au clavier.

**Pourquoi.** Le §5.3 décrit le graphique comme une image (`role="img"`) accompagnée d'une
table équivalente. Un contenu interactif dans un élément annoncé comme atomique est
inaccessible, et un `tabindex` négatif n'y change rien — axe le refuse explicitement. Le
graphique est donc une image, et la navigation vit ailleurs.

---

## D-025 — Le graphique défile plutôt que de s'écraser sur petit écran

**Décidé.** Le SVG a une largeur minimale de 660 unités dans un conteneur défilant, et la
colonne « indice » est placée avant la zone de tracé.

**Pourquoi.** Réduit à 375 px, un repère de 1000 unités ramène les libellés à quatre pixels :
le graphique devient un motif gris. Le défilement horizontal préserve la lisibilité, et
déplacer la valeur à gauche fait que tout ce qui est chiffré reste visible sans geste — seul
le tracé demande à faire glisser.

**Écart au brief.** Le §5.3 demande des dimensions en pourcentage ; elles le restent, avec un
plancher.

---

## D-026 — L'équivalence inter-ligues documente son biais plutôt que de le corriger

**Décidé.** `selectionCorrection` vaut `"none"`. Le biais est affiché en permanence sur
`/traduction`, dans un encadré non masquable.

**Pourquoi.** Le §4.2 laisse le choix entre correction par ratio de Mills et documentation
explicite. Corriger demanderait un probit de promotion sur une population de candidats que les
données ne décrivent pas : on n'observe que les joueurs promus, jamais ceux qu'aucune équipe
n'a retenus. Un modèle de sélection qu'on ne peut pas valider ajouterait une couche
d'hypothèses sans réduire l'incertitude réelle. Le champ existe dans le schéma pour que la
décision inverse reste possible sans changer le contrat.

---

## D-027 — Les sources ne sont pas joignables depuis l'environnement de développement

**Constat, pas décision.** Oracle's Elixir répond « quota dépassé » sur tous les fichiers
Drive, et l'API Cargo de Leaguepedia renvoie « ratelimited » immédiatement depuis cette IP.
Le code d'ingestion est écrit et ses fonctions pures sont testées, mais il n'a jamais tourné
sur les données réelles.

**Ce que cela implique.** Les phases 1 à 3 sont écrites et testées ; elles ne sont pas
*validées sur les vraies données*. Le premier passage du workflow `pipeline.yml` en CI, où le
réseau n'est pas contraint, est l'épreuve qui reste à passer.

---

## D-028 — La pagination Cargo exige un tri explicite

**Décidé.** `whisker_cargo_query` passe systématiquement un `order_by` à l'API — par défaut
le premier champ demandé, sous sa forme qualifiée — et déduplique le résultat en filet.

**Pourquoi.** Sans tri explicite, l'API ne garantit aucun ordre entre deux requêtes, et la
pagination par `offset` rend alors des lignes en double d'une page à l'autre tout en en
omettant d'autres. Constaté sur la source réelle : 590 lignes rendues pour 587 identifiants
distincts. Un pipeline qui compte ses joueurs aurait compté faux, sans jamais lever d'erreur.

**Comment c'est apparu.** En exécutant `tests/live/test-cargo-live.R` contre lol.fandom.com.
C'est précisément ce à quoi sert un contrôle en ligne : aucun test hors réseau ne pouvait
révéler ce comportement.

---

## D-029 — La limitation de débit de l'API Cargo est traitée comme transitoire

**Décidé.** Fandom signale la limitation dans le corps de la réponse, avec un code HTTP 200 :
`req_retry` ne la voit pas. `whisker_cargo_fetch` la reconnaît, purge l'entrée de cache
fautive et réessaie en doublant l'attente, jusqu'à six fois.

**Pourquoi.** Sur une adresse mutualisée, la limitation est intermittente : la même requête
passe quelques secondes plus tard. Abandonner une exécution de pipeline hebdomadaire pour une
seconde de trop serait absurde. Après six tentatives, l'erreur dit explicitement que
l'adresse est probablement mutualisée et que la CI, elle, dispose d'une adresse dédiée.

**Vérifié.** La reprise a été observée à l'œuvre : cinq tentatives, attente portée de 2 à
32 secondes, puis succès.

---

## D-030 — Lighthouse est mesuré localement, sur le site construit

**Décidé.** `pnpm lighthouse` sert `web/dist` en local, audite quatre pages représentatives
et échoue si un score de performance ou d'accessibilité descend sous 95.

**Pourquoi.** Le §7 place cette exigence après le déploiement. La mesurer avant a deux
vertus : le résultat existe sans dépendre d'un hébergeur, et il ne varie pas avec la latence
d'un CDN — donc il est reproductible et attribuable au code.

**Résultat au 23 août 2026.** Accueil, joueurs et méthode à 100 partout. Vieillissement à 96
en performance, le reste à 100 : le coût est le fragment Observable Plot, 259 Ko, chargé sur
cette seule page.

---

## D-033 — Le pipeline s'amorce tout seul à la première poussée, puis se tait

**Décidé.** `pipeline.yml` se déclenche sur poussée vers `main`, mais un job préalable lit
`web/src/data/meta.json` et n'enchaîne que si `synthetic` vaut vrai.

**Pourquoi.** Le premier push doit remplacer les données de développement par les vraies sans
qu'on ait à y penser. Mais relancer quatre modèles mixtes et deux mille réplications de
bootstrap à chaque commit serait absurde. La condition s'éteint d'elle-même au premier passage
réussi : elle amorce, puis elle se tait.

---

## D-034 — Un déploiement suspendu n'est pas un déploiement en échec

**Décidé.** `deploy.yml` évalue `check:release` dans un job séparé et saute la publication
plutôt que d'échouer quand les données ne sont pas publiables. Le motif part dans le résumé
du workflow.

**Pourquoi.** Refuser de publier des données synthétiques est le fonctionnement attendu, pas
une panne. Peindre la CI en rouge à chaque poussée jusqu'au premier passage du pipeline
apprendrait au lecteur à ignorer le rouge — c'est le meilleur moyen de rater une vraie
régression plus tard.

---

## D-035 — Le budget de temps de la CI correspond au travail réel

**Décidé.** Le plafond de `pipeline.yml` passe de 90 à 330 minutes, et le nombre de
réplications de bootstrap devient réglable par `WHISKER_REPLICATES`.

**Pourquoi.** Le tirage des sources, quatre modèles mixtes et deux mille réplications sur
quarante mille lignes ne tiennent pas dans une heure et demie. Un plafond trop bas aurait
produit un échec par expiration qu'on aurait pris pour un défaut du code. Le cache des
réponses de source est conservé entre exécutions : une reprise après échec ne retélécharge rien.

---

## D-036 — La patience sans budget global est un blocage, pas de la robustesse

**Constat.** Le premier passage en CI a tourné **cinq heures et demie** avant d'être annulé
par le plafond, sans produire une seule ligne. La cause n'était pas la source mais mon
réglage : vingt-quatre tentatives plafonnées à cinq minutes, multipliées par une centaine de
pages. Chaque requête était patiente ; l'ensemble ne se terminait jamais.

**Décidé.** Trois bornes, à trois échelles différentes :

- **par requête** — huit tentatives, attente plafonnée à soixante secondes ;
- **par tirage** — un budget global de quarante-cinq minutes, vérifié avant chaque tentative,
  qui s'arrête en disant que le cache permet de reprendre ;
- **par job** — un plafond de CI ramené de 330 à 120 minutes, qui ne couvre plus qu'un
  imprévu au lieu de masquer un blocage.

**Une sonde préalable** ouvre le tirage : une requête minuscule, quelques tentatives. Si elle
échoue, le tirage complet échouerait aussi — autant le dire en deux minutes.

**Vérifié.** Avec un budget de trois minutes, l'exécution s'arrête en **0,6 minute** avec un
message qui nomme la cause. La sonde, elle, était passée — elle a rendu « BrokenBlade ».

---

## D-037 — La limitation de Fandom frappe aussi les adresses de CI

**Constat, contre mon hypothèse précédente.** J'avais écrit que la limitation tenait à
l'adresse mutualisée d'un accès domestique, et que la CI, sur adresse dédiée, n'y serait pas
soumise. L'exécution de cinq heures et demie dit le contraire.

**Ce qu'on observe réellement** : la limitation s'applique par fenêtre et laisse passer
environ une requête sur quatre, quelle que soit l'adresse. Le message d'erreur a été corrigé
en conséquence — il affirmait quelque chose de faux, ce qui est pire que de ne rien dire.

**Conséquence pratique.** La pause entre deux requêtes passe d'une à deux secondes : elle
déclenche nettement moins souvent la limitation, et coûte moins cher que les reprises qu'elle
évite. Le cache sur disque rend une reprise après échec presque gratuite, ce qui fait du
tirage complet une opération à reprendre plutôt qu'à réussir d'un coup.

---

## D-038 — Un tirage complet demande plusieurs exécutions, et le pipeline en tient compte

**Constat.** Après avoir borné le tirage, l'exécution en CI a échoué en dix-neuf minutes sur
« limitation de débit persistante après 8 tentatives ». Le budget de quarante-cinq minutes
n'était même pas consommé : c'est **une seule page** qui avait épuisé ses essais et fait
tomber tout le travail. Sur une source qui ne laisse passer qu'environ une requête sur
quatre, une centaine de pages garantit qu'au moins l'une d'elles sera refusée jusqu'au bout.

**Décidé.** Une page refusée est comptée et sautée, le tirage continue. À la fin, s'il en
manque une seule, l'étape s'arrête sans rien écrire et pose un marqueur : des effectifs
amputés produiraient un classement faux sans que rien ne le signale.

Le cache des réponses porte alors la reprise. Il est conservé entre exécutions sous une clé
stable, si bien qu'une nouvelle exécution ne retélécharge rien et ne demande à la source que
les pages manquantes. Le workflow se relance lui-même, jusqu'à six fois : un tirage complet
est une opération à reprendre, pas à réussir d'un coup.

**Ce qui reste fatal.** Une erreur d'API qui n'est pas une limitation — table renommée, champ
inexistant — s'arrête immédiatement, même en mode tolérant. La sauter produirait un jeu
silencieusement amputé, ce qui est précisément ce qu'on cherche à éviter.

**Vérifié.** Cinq tests couvrent le tri entre ces cas, en substituant la réponse réseau plutôt
qu'en dépendant de la disponibilité de la source. Le budget global reste la borne la plus
forte : sauter des pages ne permet pas de le dépasser.
