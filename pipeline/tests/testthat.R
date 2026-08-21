#!/usr/bin/env Rscript
# Tests du pipeline : Rscript tests/testthat.R
#
# Les chemins sont résolus depuis l'emplacement de ce fichier, pas depuis le répertoire
# courant : la CI et une session locale ne partent pas du même endroit.

suppressPackageStartupMessages({
  library(testthat)
  library(yaml)
  library(jsonlite)
})

this_file <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) == 0) {
    stop("tests/testthat.R doit être lancé avec Rscript.", call. = FALSE)
  }
  normalizePath(sub("^--file=", "", file_arg[1]), mustWork = TRUE)
}

tests_dir <- dirname(this_file())
Sys.setenv(WHISKER_ROOT = normalizePath(file.path(tests_dir, "..", ".."), mustWork = TRUE))

source(file.path(tests_dir, "..", "R", "00_setup.R"))

test_dir(
  file.path(tests_dir, "testthat"),
  env = environment(),
  stop_on_failure = TRUE
)
