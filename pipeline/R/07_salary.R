# Calibration log-normale à partir des ancres sourcées, puis attribution par rangs.
#
# Entrées  : config/salary_anchors.yaml, interim/player_effects.rds
# Sorties  : interim/salary.rds
# Phase    : 2 du brief.
#
# L'hypothèse forte du §4.5 — monotonie parfaite performance vers salaire — est fausse en
# pratique : ancienneté, valeur marketing et qualité de négociation ne se lisent nulle part
# dans les statistiques de jeu. C'est pourquoi le résultat n'est jamais un montant, seulement
# un quintile et une fourchette.

whisker_step_07_salary <- function(paths = whisker_paths()) {
  config <- whisker_config("salary_anchors", paths)
  leagues <- vapply(whisker_config("leagues", paths)$leagues, function(l) l$id, character(1))
  effects <- readRDS(file.path(paths$interim, "player_effects.rds"))

  distributions <- list()
  exclusions <- list()

  for (league in leagues) {
    rule <- Filter(function(d) d$league == league, config$distributions)
    if (length(rule) == 0) {
      stop(sprintf("Aucune règle de publication salariale pour %s.", league), call. = FALSE)
    }
    rule <- rule[[1]]

    params <- whisker_calibrate_league(league, rule$season, config)
    if (is.null(params)) {
      exclusions[[length(exclusions) + 1]] <- list(
        league = league, season = rule$season, reason = trimws(rule$note)
      )
      whisker_log("07_salary", "%s : non calibrée — %s", league, rule$basis)
      next
    }

    bands <- whisker_quintile_bands(params)
    distributions[[length(distributions) + 1]] <- list(
      league = league, season = rule$season, currency = "EUR",
      basis = params$basis, mu = params$mu, sigma = params$sigma,
      floor = params$floor, pBelowFloor = params$untruncated_mass_below_floor,
      truncated = params$truncated, note = trimws(rule$note),
      quintiles = bands
    )
    whisker_log("07_salary", "%s : mu=%.4f sigma=%.4f tronquée=%s",
                league, params$mu, params$sigma, params$truncated)
  }

  # La ligue d'un joueur est celle de sa dernière partie connue : c'est dans cette
  # distribution-là qu'il faut le situer.
  games <- as.data.frame(arrow::read_parquet(file.path(paths$interim, "player_games.parquet")))
  games <- games[order(games$playername, as.Date(games$date)), ]
  last <- games[!duplicated(games$playername, fromLast = TRUE), ]

  blups <- effects$blups
  blups$league <- last$league_id[match(blups$level, last$playername)]
  assignments <- whisker_assign_quintiles(blups, distributions)

  saveRDS(
    list(distributions = distributions, exclusions = exclusions,
         anchors = config$anchors, assignments = assignments),
    file.path(paths$interim, "salary.rds")
  )
  invisible(distributions)
}

#' Attribue un quintile et une fourchette à chaque joueur, par correspondance de rangs.
#'
#' Les joueurs d'une ligue sans distribution calibrée reçoivent NA, qui deviendra `null` à
#' l'export. Une absence assumée vaut mieux qu'une extrapolation muette.
whisker_assign_quintiles <- function(blups, distributions, league_column = "league") {
  if (!league_column %in% names(blups)) {
    blups[[league_column]] <- NA_character_
  }
  blups$salary_quintile <- NA_integer_
  blups$salary_lower <- NA_real_
  blups$salary_upper <- NA_real_

  for (distribution in distributions) {
    rows <- which(blups[[league_column]] == distribution$league)
    if (length(rows) == 0) next

    # Rang relatif dans la ligue, puis quintile. `ties.method = "average"` évite qu'un
    # ex aequo bascule arbitrairement d'un quintile à l'autre.
    ranks <- rank(blups$effect[rows], ties.method = "average")
    fraction <- (ranks - 0.5) / length(rows)
    quintiles <- pmin(5L, pmax(1L, as.integer(floor(fraction * 5)) + 1L))

    blups$salary_quintile[rows] <- quintiles
    for (index in seq_along(rows)) {
      band <- distribution$quintiles[[quintiles[index]]]
      blups$salary_lower[rows[index]] <- band$lower
      blups$salary_upper[rows[index]] <- band$upper
    }
  }

  blups
}
