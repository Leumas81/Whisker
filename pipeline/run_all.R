#!/usr/bin/env Rscript
# Point d'entrée unique du pipeline.
#
# Tourne en CI, pas sur la machine du propriétaire. Chaque étape est indépendante et
# nommée : `Rscript run_all.R 04_model_league` rejoue une seule étape sans refaire le reste.

script_dir <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0) {
    return(dirname(normalizePath(sub("^--file=", "", file_arg[1]), mustWork = FALSE)))
  }
  getwd()
}

PIPELINE_DIR <- script_dir()

suppressPackageStartupMessages(library(yaml))
source(file.path(PIPELINE_DIR, "R", "00_setup.R"))

STEPS <- c(
  "01_download",
  "02_contracts",
  "03_clean",
  "04_model_league",
  "05_model_player",
  "06_model_aging",
  "07_salary",
  "08_export"
)

run_pipeline <- function(requested = character()) {
  paths <- whisker_ensure_dirs()
  for (step in STEPS) {
    source(file.path(PIPELINE_DIR, "R", paste0(step, ".R")))
  }

  selected <- if (length(requested) == 0) STEPS else requested
  unknown <- setdiff(selected, STEPS)
  if (length(unknown) > 0) {
    stop(
      sprintf(
        "Étapes inconnues : %s\nÉtapes disponibles : %s",
        paste(unknown, collapse = ", "),
        paste(STEPS, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  for (step in selected) {
    whisker_log(step, "début")
    do.call(paste0("whisker_step_", step), list(paths = paths))
    whisker_log(step, "terminé")
  }

  whisker_log("run_all", "pipeline terminé (%d étapes)", length(selected))
  invisible(selected)
}

if (!interactive()) {
  run_pipeline(commandArgs(trailingOnly = TRUE))
}
