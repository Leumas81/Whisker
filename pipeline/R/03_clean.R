# Nettoyage, réconciliation des identités, jointure performances/contrats.
#
# Entrées  : raw/oracle_<annee>.csv, interim/players_meta.parquet, interim/contracts.parquet
# Sorties  : interim/player_games.parquet, interim/unmatched.csv
# Phase    : 1 du brief.
#
# Le pipeline échoue si le taux de non-résolution dépasse le seuil de config/leagues.yaml.
# Pas de dégradation silencieuse : mieux vaut un arrêt qu'un classement bâti sur des trous.

whisker_step_03_clean <- function(paths = whisker_paths()) {
  leagues_config <- whisker_config("leagues", paths)
  columns_config <- whisker_config("oracle_columns", paths)
  aliases_config <- whisker_config("name_aliases", paths)

  wanted_columns <- unique(unlist(columns_config[c("identity", "outcome", "performance")]))
  league_codes <- unlist(lapply(leagues_config$leagues, function(l) l$oracle_codes))
  league_ids <- vapply(leagues_config$leagues, function(l) l$id, character(1))
  code_to_id <- stats::setNames(
    rep(league_ids, vapply(leagues_config$leagues, function(l) length(l$oracle_codes), integer(1))),
    league_codes
  )
  event_codes <- unlist(lapply(leagues_config$international_events, function(e) e$oracle_codes))

  # ── Lecture des CSV annuels ───────────────────────────────────────────────────────────
  files <- list.files(paths$raw, pattern = "^oracle_\\d{4}\\.csv$", full.names = TRUE)
  if (length(files) == 0) {
    stop("Aucun CSV Oracle's Elixir dans raw/. Lancez d'abord l'étape 01_download.", call. = FALSE)
  }

  seasons <- lapply(files, function(file) {
    rows <- readr::read_csv(file, show_col_types = FALSE, progress = FALSE,
                            guess_max = 50000, na = c("", "NA"))
    whisker_require_columns(rows, wanted_columns, basename(file))
    rows <- rows[rows$league %in% c(league_codes, event_codes), wanted_columns, drop = FALSE]
    rows
  })
  raw_rows <- do.call(rbind, seasons)
  whisker_log("03_clean", "%d lignes retenues sur %d fichiers", nrow(raw_rows), length(files))

  if (isTRUE(columns_config$require_complete)) {
    before <- nrow(raw_rows)
    raw_rows <- raw_rows[raw_rows$datacompleteness == "complete", , drop = FALSE]
    whisker_log("03_clean", "%d ligne(s) incomplète(s) écartée(s)", before - nrow(raw_rows))
  }

  # ── Séparation des lignes d'équipe et des lignes joueur ───────────────────────────────
  marker <- columns_config$team_row_marker
  teams <- raw_rows[raw_rows$position == marker, , drop = FALSE]
  players <- raw_rows[raw_rows$position != marker, , drop = FALSE]

  players <- whisker_attach_team_kills(players, teams)
  players <- whisker_drop_duplicate_rows(players)

  # ── Vocabulaire interne ───────────────────────────────────────────────────────────────
  players$role <- whisker_map_positions(players$position, columns_config$positions)
  players$season <- whisker_season_of(players$date)
  players$is_international <- players$league %in% event_codes
  players$league_id <- unname(code_to_id[players$league])

  # Une partie internationale n'appartient à aucune ligue régulière : elle est jouée PAR un
  # joueur DE une ligue. On lui rattache donc la ligue où ce joueur a joué le reste de sa
  # saison. Sans cela, ces lignes — la seconde source d'identification du §4.1 — arriveraient
  # au modèle sans ligue et n'identifieraient plus rien.
  regular <- players[!players$is_international & !is.na(players$league_id), , drop = FALSE]
  if (nrow(regular) > 0) {
    home <- tapply(
      regular$league_id,
      paste(regular$playername, regular$season, sep = "|"),
      function(x) names(sort(table(x), decreasing = TRUE))[1]
    )
    missing <- which(players$is_international)
    players$league_id[missing] <- unname(
      home[paste(players$playername[missing], players$season[missing], sep = "|")]
    )
  }

  players$playername <- whisker_canonical(players$playername, aliases_config$players)
  players$teamname <- whisker_canonical(players$teamname, aliases_config$teams)

  before <- nrow(players)
  players <- players[!is.na(players$role), , drop = FALSE]
  if (before > nrow(players)) {
    whisker_log("03_clean", "%d ligne(s) au poste inconnu écartée(s)", before - nrow(players))
  }

  # ── Jointure avec Leaguepedia ─────────────────────────────────────────────────────────
  meta_file <- file.path(paths$interim, "players_meta.parquet")
  if (!file.exists(meta_file)) {
    stop("interim/players_meta.parquet absent. Lancez d'abord l'étape 02_contracts.", call. = FALSE)
  }
  players_meta <- as.data.frame(arrow::read_parquet(meta_file))
  contracts <- as.data.frame(arrow::read_parquet(file.path(paths$interim, "contracts.parquet")))

  players_meta$key <- tolower(whisker_canonical(players_meta$id, aliases_config$players))
  players$key <- tolower(players$playername)

  players$birthdate <- players_meta$birthdate[match(players$key, players_meta$key)]
  players$country <- players_meta$country[match(players$key, players_meta$key)]
  players$age <- whisker_age_at(players$birthdate, players$date)

  if (nrow(contracts) > 0) {
    contracts$key <- tolower(whisker_canonical(contracts$id, aliases_config$players))
    players$contract_end <- contracts$contract_end[match(players$key, contracts$key)]
  } else {
    players$contract_end <- as.Date(NA)
  }

  # ── Contrôle de non-résolution ────────────────────────────────────────────────────────
  # L'âge est le champ critique : sans date de naissance, le modèle de vieillissement du §4.4
  # n'a rien à mordre. Le contrat, lui, est légitimement inconnu pour beaucoup de joueurs.
  unmatched <- whisker_unmatched(players, c("age", "team_kills"))
  utils::write.csv(
    unmatched$rows[, c("gameid", "playername", "teamname", "league", "date"), drop = FALSE],
    file.path(paths$interim, "unmatched.csv"),
    row.names = FALSE
  )

  threshold <- leagues_config$max_unmatched_rate
  whisker_log("03_clean", "non-résolution : %.2f %% (seuil %.2f %%)",
              100 * unmatched$rate, 100 * threshold)

  if (unmatched$rate > threshold) {
    stop(
      sprintf(
        paste0(
          "Taux de non-résolution de %.2f %%, au-delà du seuil de %.2f %%.\n",
          "  %d lignes concernées, listées dans interim/unmatched.csv.\n",
          "  Ajoutez les correspondances manquantes à config/name_aliases.yaml."
        ),
        100 * unmatched$rate, 100 * threshold, nrow(unmatched$rows)
      ),
      call. = FALSE
    )
  }

  players <- players[!is.na(players$age) & !is.na(players$team_kills), , drop = FALSE]
  players$key <- NULL

  destination <- file.path(paths$interim, "player_games.parquet")
  arrow::write_parquet(players, destination)
  whisker_log("03_clean", "%d lignes joueur-game écrites", nrow(players))

  invisible(destination)
}
