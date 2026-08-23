# Téléchargement des CSV annuels d'Oracle's Elixir, avec cache local.
#
# Entrées  : config/leagues.yaml (identifiants Google Drive, première saison)
# Sorties  : raw/oracle_<annee>.csv
# Phase    : 1 du brief.

whisker_step_01_download <- function(paths = whisker_paths()) {
  config <- whisker_config("leagues", paths)
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
            "  Vérifiez oracle_downloads dans pipeline/config/leagues.yaml."
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
