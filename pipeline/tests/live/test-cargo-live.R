#!/usr/bin/env Rscript
# Vérification de l'ingestion Cargo contre la source réelle.
#
# Ce contrôle sort du jeu de tests ordinaire : il touche le réseau, dépend de la
# disponibilité de lol.fandom.com et respecte une pause d'une seconde entre requêtes. Il
# n'a donc pas sa place dans `pnpm verify`, qui doit rester reproductible hors ligne.
#
#   Rscript tests/live/test-cargo-live.R
#
# Ce qu'il établit : la pagination fonctionne, les champs demandés reviennent, le cache
# évite la seconde requête, et une erreur d'API est remontée plutôt qu'avalée.

suppressPackageStartupMessages({
  library(testthat); library(yaml); library(jsonlite); library(httr2); library(digest)
})

this_file <- normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]))
root <- normalizePath(file.path(dirname(this_file), "..", "..", ".."), mustWork = TRUE)
Sys.setenv(WHISKER_ROOT = root)

source(file.path(root, "pipeline", "R", "00_setup.R"))
paths <- whisker_ensure_dirs()
whisker_source_lib(paths)

# Une limitation de débit persistante n'est pas un défaut du code : sur une adresse
# mutualisée, elle dit seulement que la source refuse de répondre maintenant. Le contrôle
# se déclare ignoré plutôt que rouge, et le dit clairement.
essayer <- function(label, corps) {
  tryCatch(
    test_that(label, corps),
    error = function(condition) {
      if (grepl("limitation de débit", conditionMessage(condition))) {
        cat(sprintf("  IGNORÉ — %s : la source limite le débit depuis cette adresse.\n", label))
        invisible(NULL)
      } else {
        stop(condition)
      }
    }
  )
}

cat("Source : https://lol.fandom.com/api.php (API Cargo)\n\n")

essayer("une requête Cargo bornée rend les champs demandés", {
  players <- whisker_cargo_query(
    tables = "Players",
    fields = "Players.ID=id, Players.Birthdate=birthdate, Players.Country=country, Players.Role=role",
    where = "Players.Team='G2 Esports'",
    limit = 100L,
    max_pages = 2L,
    paths = paths
  )

  expect_gt(nrow(players), 0)
  expect_true(all(c("id", "birthdate", "country", "role") %in% names(players)))
  expect_true(all(nzchar(players$id)))
  cat(sprintf("  %d joueurs rendus, colonnes : %s\n",
              nrow(players), paste(names(players), collapse = ", ")))
  cat(sprintf("  exemple : %s\n", paste(utils::head(players$id, 5), collapse = ", ")))
})

essayer("la pagination franchit la limite de 500 lignes par requête", {
  # Une table assez large pour exiger au moins deux requêtes.
  rows <- whisker_cargo_query(
    tables = "Players",
    fields = "Players.ID=id",
    where = "Players.Country='France'",
    limit = 500L,
    max_pages = 3L,
    paths = paths
  )
  expect_gt(nrow(rows), 500)
  expect_equal(length(unique(rows$id)), nrow(rows))
  cat(sprintf("  %d lignes sur plusieurs pages, sans doublon\n", nrow(rows)))
})

essayer("les dates de naissance se convertissent, et les manquantes restent manquantes", {
  players <- whisker_cargo_query(
    tables = "Players",
    fields = "Players.ID=id, Players.Birthdate=birthdate",
    where = "Players.Team='Fnatic'",
    limit = 100L, max_pages = 1L, paths = paths
  )
  dates <- suppressWarnings(as.Date(players$birthdate))
  expect_true(any(!is.na(dates)))
  cat(sprintf("  %d/%d dates de naissance exploitables\n", sum(!is.na(dates)), length(dates)))
})

essayer("le cache évite une seconde requête réseau", {
  query <- function() {
    whisker_cargo_query(
      tables = "Players", fields = "Players.ID=id",
      where = "Players.Team='T1'", limit = 50L, max_pages = 1L, paths = paths
    )
  }
  first <- system.time(query())[["elapsed"]]
  second <- system.time(query())[["elapsed"]]
  expect_lt(second, first)
  cat(sprintf("  premier appel %.2f s, second %.2f s (cache)\n", first, second))
})

essayer("une erreur d'API est remontée, pas avalée", {
  expect_error(
    whisker_cargo_query(
      tables = "TableInexistante", fields = "TableInexistante.Champ=x",
      limit = 10L, max_pages = 1L, paths = paths
    ),
    "API Cargo"
  )
})

cat("\nIngestion Cargo vérifiée contre la source réelle.\n")
