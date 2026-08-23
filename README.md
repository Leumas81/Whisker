# WHISKER

*Les stats existent partout. Ici, on te dit ce qu'elles valent.*

L'écosystème League of Legends esport ne manque pas de données brutes. Il manque d'inférence.
WHISKER traduit les statistiques en jugement, avec l'incertitude affichée — et n'affiche
jamais un chiffre sans son intervalle et sa taille d'échantillon.

Trois questions, trois outils : ce que vaudrait un joueur de LFL en LEC, ce qui revient au
joueur plutôt qu'à son équipe, et où il se situe dans la distribution salariale de sa ligue.

## Comment ça tient debout

```
GitHub Actions ─▶ pipeline R ─▶ JSON validés ─▶ site Astro statique
   (cron hebdo)   (renv, testthat)  (JSON Schema)      (Cloudflare Pages)
                                          │
                                          ▼
                              types TypeScript générés
```

Aucun serveur applicatif, aucune base de données, aucune route API. Les données changent au
plus une fois par semaine et pèsent quelques mégaoctets ; un backend n'apporterait que des
coûts et une surface d'attaque.

Le dossier `schemas/` est la **source unique de vérité**. Les types TypeScript du site en sont
générés, et les sorties du pipeline R y sont validées. Un champ renommé d'un côté sans mise à
jour du schéma fait échouer la CI — la dérive silencieuse entre les deux moitiés du projet
est structurellement impossible.

## Démarrer

```bash
pnpm install
pnpm dev
```

Le pipeline R n'est pas nécessaire pour travailler sur le site : les JSON qu'il produit sont
commités dans `web/src/data/`. Pour le faire tourner localement :

```bash
Rscript pipeline/bootstrap.R
```

> **Les données actuellement commitées sont synthétiques.** Oracle&rsquo;s Elixir distribue ses
> CSV par Google Drive, dont le quota public était épuisé au moment du développement, et l&rsquo;API
> Cargo de Leaguepedia limite les IP partagées : le pipeline n&rsquo;a pas encore tourné sur les
> données réelles. `meta.synthetic` vaut `true`, chaque page l&rsquo;affiche en bandeau, et
> `pnpm verify:release` refuse toute publication tant que c&rsquo;est le cas.

## Vérifier

Une seule commande, à passer au vert avant de considérer quoi que ce soit terminé :

```bash
pnpm verify
```

Elle enchaîne : cohérence des schémas, types à jour, JSON conformes, lint, typage strict,
tests unitaires, build, tests bout-en-bout, et — si `Rscript` est accessible — les tests du
pipeline R. Pour rejouer une seule étape : `node tools/verify.mjs types`.

| Commande | Effet |
|---|---|
| `pnpm gen:types` | Régénère `web/src/generated/types.ts` depuis `schemas/` |
| `pnpm validate:data` | Valide les JSON produits contre leurs schémas |
| `pnpm build` | Construit le site statique |
| `Rscript pipeline/run_all.R` | Exécute le pipeline complet |
| `Rscript pipeline/run_all.R 04_model_league` | Rejoue une seule étape |
| `Rscript pipeline/fixtures/generate.R` | Produit un jeu de développement synthétique |
| `pnpm verify:release` | Vérifie, puis refuse de publier des données synthétiques |
| `pnpm lighthouse` | Audite le site construit, échoue sous 95 en performance ou accessibilité |
| `pnpm test:cargo` | Vérifie l’ingestion Leaguepedia contre la source réelle |

## Mettre en route la CI

Le pipeline est fait pour tourner en intégration continue, pas sur une machine personnelle :
l'API Cargo de Leaguepedia limite fortement le débit des adresses mutualisées, ce qui rend un
tirage de quarante mille lignes impraticable depuis un accès domestique.

Une fois un dépôt distant créé, sans rien y pousser :

```bash
git remote add origin <URL-du-depot>
git push -u origin main
```

Ce que la première poussée déclenche, sans autre intervention :

| Workflow | Ce qu'il fait |
|---|---|
| `verify` | Rejoue `pnpm verify` : contrats, types, lint, typage, tests, build, bout-en-bout, tests R |
| `pipeline` | Ne se lance sur poussée **que si** `meta.synthetic` est vrai — il remplace alors les données de développement par les vraies. La condition s'éteint d'elle-même au premier passage réussi |
| `deploy` | S'arrête proprement tant que les données ne sont pas publiables, et ne peint pas la CI en rouge pour autant |

Le déploiement lui-même attend deux secrets de dépôt, `CLOUDFLARE_API_TOKEN` et
`CLOUDFLARE_ACCOUNT_ID`. Sans eux, tout le reste fonctionne : seule la mise en ligne est
suspendue.

## Où lire quoi

| | |
|---|---|
| [docs/METHODE.md](docs/METHODE.md) | Ce que chaque modèle répond, sur quelles données, avec quelles limites |
| [docs/DECISIONS.md](docs/DECISIONS.md) | Journal des décisions techniques et de leurs raisons |
| [docs/SOURCES.md](docs/SOURCES.md) | Provenance des données, licences, attributions |

## Sources et mentions

Données de performance : [Oracle's Elixir](https://oracleselixir.com/tools/downloads).
Contrats, âges et rosters : [Leaguepedia / Fandom](https://lol.fandom.com).

Les estimations salariales sont statistiques. Aucun salaire réel n'est connu de ce site.

WHISKER n'est pas affilié à Riot Games.
