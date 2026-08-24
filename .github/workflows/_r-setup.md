# Mise en place de R en CI — pourquoi ces étapes plutôt que `setup-renv`

`r-lib/actions/setup-renv@v2` échouait en une minute sur les deux workflows, sans message
exploitable depuis l'extérieur du dépôt. Les étapes ci-dessous font le même travail, mais
chacune peut échouer distinctement et dire pourquoi.

Trois raisons de fond, indépendantes les unes des autres :

**Les dépôts du lockfile écrasent ceux du runner.** `renv.lock` déclare
`https://cloud.r-project.org`, qui ne sert que des sources. Sur Linux, restaurer soixante-douze
paquets depuis les sources signifie compiler `arrow`, `lme4` et `mgcv` — des dizaines de
minutes, et autant d'occasions d'échouer sur une dépendance système manquante.
`RENV_CONFIG_REPOS_OVERRIDE` pointe vers le dépôt binaire de Posit correspondant à la
distribution du runner, déduite de `/etc/os-release`. Lire la configuration de `setup-r`
depuis R paraissait plus élégant, mais dépendait du nom qu'il donne à son dépôt : une clé
absente faisait échouer l'étape en une seconde.

**`V8` a besoin d'une bibliothèque système.** Le paquet `jsonvalidate`, qui valide les JSON
produits contre les schémas, s'appuie sur `V8`. Sans `libnode-dev`, son installation échoue —
et avec elle toute la validation du contrat de données.

**Bioconductor était activé sans raison.** `renv/settings.json` portait
`bioconductor.enabled: true` alors que le projet n'utilise aucun paquet Bioconductor. renv
tente alors d'installer `BiocManager` au début de la restauration, ce qui échoue tôt sur un
runner neuf — et correspond au temps observé.

Le cache porte sur `~/.cache/R/renv`, la clé étant l'empreinte du lockfile : une exécution
suivante ne réinstalle rien tant que les dépendances ne changent pas.
