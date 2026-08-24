# Récupération des performances joueur-game.
#
# Entrées  : config/leagues.yaml
# Sorties  : raw/oracle_<annee>.csv, ou interim/scoreboards.parquet
# Phase    : 1 du brief.
#
# Deux sources possibles, choisies par `performance_source` dans la configuration :
#
#   oracle       — les CSV annuels d'Oracle's Elixir, source de référence du brief. Sa
#                  distribution est passée à Google Drive, dont le quota public s'épuise :
#                  le jeu devient alors inatteignable pendant des jours.
#   leaguepedia  — les tableaux de score, par la même API Cargo que les contrats. Vrais
#                  pseudos, vraies équipes, mais pas de différentiels de lane à 15 minutes.
#
# Le choix se documente, il ne se devine pas : `meta.json` enregistre la source retenue et les
# composants de `metric_std` qui ont réellement pu être calculés.

whisker_step_01_download <- function(paths = whisker_paths()) {
  config <- whisker_config("leagues", paths)
  source_name <- config$performance_source %||% "oracle"

  switch(
    source_name,
    oracle = whisker_download_oracle(config, paths),
    leaguepedia = whisker_download_leaguepedia(config, paths),
    stop(
      sprintf(
        "performance_source vaut « %s ». Valeurs acceptées : oracle, leaguepedia.",
        source_name
      ),
      call. = FALSE
    )
  )
}

`%||%` <- function(x, y) if (is.null(x)) y else x

# ── Oracle's Elixir ──────────────────────────────────────────────────────────────────────

whisker_download_oracle <- function(config, paths) {
  downloads <- config$oracle_downloads
  first_season <- config$period$first_season
  seasons <- sort(as.integer(names(downloads$files)))
  seasons <- seasons[seasons >= first_season]

  if (length(seasons) == 0) {
    stop("Aucune saison à télécharger : vérifiez oracle_downloads dans leagues.yaml.", call. = FALSE)
  }

  written <- character()
  for (season in seasons) {
    id <- downloads$files[[as.character(season)]]
    destination <- file.path(paths$raw, sprintf("oracle_%d.csv", season))
    whisker_download(paste0(downloads$base_url, id), destination, paths = paths)

    # Google Drive rend une page HTML — quota dépassé, confirmation antivirus — avec un
    # code 200. Sans ce contrôle, un fichier HTML se ferait passer pour un CSV et l'erreur
    # n'apparaîtrait que bien plus loin, sous une forme incompréhensible.
    first_line <- readLines(destination, n = 1L, warn = FALSE)
    if (length(first_line) == 0 || grepl("^\\s*<", first_line)) {
      unlink(destination)
      stop(
        sprintf(
          paste0(
            "Oracle's Elixir %d : Google Drive a renvoyé une page HTML au lieu du CSV.\n",
            "  Cause probable : quota de téléchargement public dépassé, ou identifiant périmé.\n",
            "  Bascule possible : performance_source: leaguepedia dans config/leagues.yaml."
          ),
          season
        ),
        call. = FALSE
      )
    }
    if (!grepl("gameid", first_line, fixed = TRUE)) {
      unlink(destination)
      stop(sprintf("Oracle's Elixir %d : en-tête inattendu, colonne « gameid » absente.", season),
           call. = FALSE)
    }

    whisker_log("01_download", "saison %d : %.1f Mo", season, file.size(destination) / 1e6)
    written <- c(written, destination)
  }

  invisible(written)
}

# ── Leaguepedia ──────────────────────────────────────────────────────────────────────────

#' Vérifie que la source répond avant d'engager un tirage de plusieurs dizaines de minutes.
#'
#' Une requête minuscule, quelques tentatives. Si elle échoue, le tirage complet échouera
#' aussi : autant le dire en deux minutes plutôt qu'en cinq heures.
whisker_probe_cargo <- function(paths) {
  whisker_log("01_download", "sonde préalable de l'API Cargo")
  rows <- whisker_cargo_query(
    tables = "ScoreboardPlayers",
    fields = "ScoreboardPlayers.Link=playername",
    where = "ScoreboardPlayers.OverviewPage LIKE 'LEC/2025%'",
    order_by = "ScoreboardPlayers.GameId",
    limit = 5L, max_pages = 1L,
    max_attempts = 5L, max_wait = 30, paths = paths
  )
  if (nrow(rows) == 0) {
    stop(
      paste0(
        "La sonde n'a rendu aucune ligne alors que la table en contient.\n",
        "  La requête ou les noms de champs ont probablement changé côté Leaguepedia."
      ),
      call. = FALSE
    )
  }
  whisker_log("01_download", "sonde : %d lignes, exemple « %s »", nrow(rows), rows$playername[1])
  invisible(TRUE)
}

whisker_download_leaguepedia <- function(config, paths) {
  whisker_set_deadline(WHISKER_FETCH_BUDGET)
  whisker_reset_skipped()
  whisker_probe_cargo(paths)

  first_season <- config$period$first_season
  seasons <- seq(first_season, as.integer(format(Sys.Date(), "%Y")))
  pages <- vapply(config$leagues, function(league) league$leaguepedia_page, character(1))
  ids <- vapply(config$leagues, function(league) league$id, character(1))

  collected <- list()
  for (index in seq_along(pages)) {
    whisker_log("01_download", "%s : saisons %d à %d", ids[index], min(seasons), max(seasons))
    rows <- whisker_fetch_scoreboards(pages[index], seasons, paths)
    rows$league <- ids[index]
    collected[[length(collected) + 1]] <- rows
    whisker_log("01_download", "%s : %d lignes au total", ids[index], nrow(rows))
  }

  # Un tirage incomplet ne doit pas se présenter comme complet. Une source qui ne laisse
  # passer qu'une requête sur quatre finit toujours par en refuser quelques-unes jusqu'au
  # bout ; ce qui a été obtenu reste en cache, et une reprise le complète. Mais tant qu'il
  # manque une page, les effectifs seraient faux et le classement bancal.
  manquantes <- whisker_skipped_count()
  marqueur <- file.path(paths$interim, "tirage_incomplet")

  if (manquantes > 0) {
    writeLines(as.character(manquantes), marqueur)
    stop(
      sprintf(
        paste0(
          "Tirage incomplet : %d page(s) refusée(s) par la source.\n",
          "  %d lignes ont tout de même été obtenues et sont en cache.\n",
          "  Relancer le tirage reprend là où il s'est arrêté : rien n'est retéléchargé.\n",
          "  Aucun jeu de données n'est écrit tant qu'il manque une page — des effectifs\n",
          "  amputés produiraient un classement faux sans que rien ne le signale."
        ),
        manquantes, nrow(do.call(rbind, collected))
      ),
      call. = FALSE
    )
  }

  unlink(marqueur)
  games <- whisker_normalise_scoreboards(do.call(rbind, collected))
  destination <- file.path(paths$interim, "scoreboards.parquet")
  arrow::write_parquet(games, destination)

  whisker_log("01_download", "%d lignes joueur-game écrites (%d joueurs distincts)",
              nrow(games), length(unique(games$playername)))
  invisible(destination)
}
