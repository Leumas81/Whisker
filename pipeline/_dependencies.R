# Déclaration des dépendances pour renv.
#
# Ce fichier n'est jamais exécuté. renv détecte les dépendances en lisant les appels
# `library()` du projet ; tant que les étapes des phases 1 à 3 sont des squelettes, aucune
# n'apparaît, et renv signale le projet comme désynchronisé à chaque lancement.
#
# Chaque ligne dit à quoi sert le paquet et à quelle phase il entre en jeu.

library(httr2)        # phase 1 — API Cargo de Leaguepedia
library(readr)        # phase 1 — CSV d'Oracle's Elixir
library(dplyr)        # phases 1 à 3 — manipulation
library(tidyr)        # phases 1 à 3
library(stringr)      # phase 1 — réconciliation des pseudos
library(arrow)        # phase 1 — Parquet intermédiaire
library(digest)       # phase 1 — empreintes de cache
library(yaml)         # toutes phases — configuration

library(lme4)         # phase 2 — effets aléatoires croisés
library(mgcv)         # phase 2 — splines pénalisées, courbes de vieillissement
library(boot)         # phase 2 — bootstrap des intervalles

library(jsonlite)     # phase 3 — écriture des JSON
library(jsonvalidate) # phase 3 — validation ajv contre schemas/

library(testthat)     # tests de chaque étape
