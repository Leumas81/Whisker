#!/usr/bin/env Rscript
# Amorçage de l'environnement R du pipeline.
#
# À lancer une fois par machine et par clone : `Rscript pipeline/bootstrap.R`.
# En CI, c'est renv::restore() qui prend le relais à partir de renv.lock — ce script ne
# sert qu'à produire ce fichier, ou à le mettre à jour quand une dépendance change.

PACKAGES <- c(
  # Ingestion et export
  "httr2",      # API Cargo de Leaguepedia, avec politesse et cache
  "jsonlite",   # lecture/écriture JSON
  "arrow",      # Parquet pour le stockage intermédiaire
  "yaml",       # configuration
  "readr",      # lecture des CSV d'Oracle's Elixir
  "dplyr",      # manipulation
  "tidyr",
  "stringr",
  "digest",     # empreintes de cache

  # Modélisation
  "lme4",       # effets aléatoires croisés
  # mgcv et boot sont livrés avec R : pas besoin de les installer, mais renv les verrouille.

  # Contrats et tests
  "jsonvalidate", # validation ajv des sorties contre schemas/
  "testthat"
)

user_lib <- Sys.getenv("R_LIBS_USER", unset = file.path(Sys.getenv("LOCALAPPDATA"), "R", "win-library", "4.4"))
dir.create(user_lib, recursive = TRUE, showWarnings = FALSE)
.libPaths(c(user_lib, .libPaths()))

options(repos = c(CRAN = "https://cloud.r-project.org"))

if (!requireNamespace("renv", quietly = TRUE)) {
  cat("Installation de renv...\n")
  install.packages("renv", lib = user_lib)
}

project <- normalizePath(dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])), mustWork = TRUE)
cat(sprintf("Projet renv : %s\n", project))

renv::init(project = project, bare = TRUE, restart = FALSE)
# Binaires exclusivement. Les dépôts source et binaire ne sont pas au même niveau : mélanger
# un httr2 compilé depuis les sources avec un rlang binaire plus ancien produit un conflit
# d'espace de noms au moment du build. Sous Linux, Posit sert également des binaires.
renv::install(PACKAGES, project = project, prompt = FALSE, type = "binary")
renv::snapshot(project = project, packages = c(PACKAGES, "mgcv", "boot"), prompt = FALSE)

cat("\nEnvironnement R prêt. renv.lock est à jour.\n")
