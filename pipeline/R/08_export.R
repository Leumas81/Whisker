# Écriture des cinq JSON, validation contre les schémas, arrondis, meta.json avec le hash git.
#
# Entrées  : interim/*.rds
# Sorties  : web/src/data/*.json
# Phase    : 3 du brief.

whisker_step_08_export <- function(paths = whisker_paths(), synthetic = FALSE) {
  games <- as.data.frame(arrow::read_parquet(file.path(paths$interim, "player_games.parquet")))
  # `metric_std` est dérivé, jamais stocké : le parquet ne contient que les colonnes sources.
  # Le recalculer ici garantit qu'export et modèles parlent exactement de la même grandeur.
  games <- whisker_metric_std(games)
  games <- games[is.finite(games$metric_std), , drop = FALSE]
  effects <- readRDS(file.path(paths$interim, "player_effects.rds"))
  league_fit <- readRDS(file.path(paths$interim, "league_strength.rds"))
  aging <- readRDS(file.path(paths$interim, "aging.rds"))
  salary <- readRDS(file.path(paths$interim, "salary.rds"))
  thresholds <- whisker_config("leagues", paths)$reliability

  whisker_export_players(games, effects, salary, thresholds, paths)
  whisker_export_leagues(league_fit, paths)
  whisker_export_aging(aging, paths)
  whisker_export_salary(salary, paths)
  whisker_export_meta(games, effects, salary, synthetic, paths)

  invisible(paths$data_out)
}

#' Identifiant d'URL stable, dérivé du pseudo.
whisker_slugify <- function(names) {
  slug <- tolower(names)
  slug <- iconv(slug, to = "ASCII//TRANSLIT", sub = "")
  slug <- gsub("[^a-z0-9]+", "-", slug)
  slug <- gsub("^-+|-+$", "", slug)
  slug[!nzchar(slug)] <- paste0("joueur-", which(!nzchar(slug)))
  make.unique(slug, sep = "-")
}

whisker_export_players <- function(games, effects, salary, thresholds, paths) {
  latest <- max(as.Date(games$date), na.rm = TRUE)
  spec <- whisker_metric_spec(paths)
  blups <- salary$assignments

  # Le dernier état connu de chaque joueur : équipe, ligue, âge, contrat.
  games <- games[order(games$playername, as.Date(games$date)), ]
  last <- games[!duplicated(games$playername, fromLast = TRUE), ]
  rownames(last) <- NULL

  blups <- blups[match(last$playername, blups$level), ]
  keep <- !is.na(blups$level)
  last <- last[keep, ]
  blups <- blups[keep, ]

  counts <- as.integer(table(games$playername)[last$playername])
  reliability <- whisker_reliability(counts, thresholds)
  publishable <- !is.na(reliability)

  last <- last[publishable, ]
  blups <- blups[publishable, ]
  counts <- counts[publishable]
  reliability <- reliability[publishable]

  slugs <- whisker_slugify(last$playername)
  sigma <- effects$sigma_player

  players <- lapply(seq_len(nrow(last)), function(index) {
    name <- last$playername[index]
    history_rows <- games[games$playername == name, , drop = FALSE]

    history <- lapply(sort(unique(history_rows$season)), function(season) {
      season_rows <- history_rows[history_rows$season == season, , drop = FALSE]
      mean_std <- mean(season_rows$metric_std, na.rm = TRUE)
      se <- stats::sd(season_rows$metric_std, na.rm = TRUE) / sqrt(nrow(season_rows))
      if (!is.finite(se)) se <- 0
      z <- stats::qnorm(1 - (1 - WHISKER_CONFIDENCE) / 2)
      list(
        season = as.integer(season),
        league = season_rows$league_id[nrow(season_rows)],
        team = season_rows$teamname[nrow(season_rows)],
        games = nrow(season_rows),
        valueIndex = whisker_round_estimate(whisker_estimate(
          whisker_value_index(mean_std * sigma, sigma, spec),
          whisker_value_index((mean_std - z * se) * sigma, sigma, spec),
          whisker_value_index((mean_std + z * se) * sigma, sigma, spec)
        ), 1)
      )
    })
    history <- Filter(function(h) h$league %in% c("LEC", "LFL"), history)

    list(
      slug = slugs[index],
      name = name,
      role = last$role[index],
      team = last$teamname[index],
      league = last$league_id[index],
      age = round(last$age[index], 1),
      contractEnd = if (is.na(last$contract_end[index])) NULL else format(last$contract_end[index], "%Y-%m-%d"),
      games = counts[index],
      valueIndex = whisker_round_estimate(whisker_estimate(
        whisker_value_index(blups$effect[index], sigma, spec),
        whisker_value_index(blups$lower[index], sigma, spec),
        whisker_value_index(blups$upper[index], sigma, spec)
      ), 1),
      playerShare = whisker_round_estimate(
        effects$share_by_role[[last$role[index]]] %||% whisker_estimate(
          effects$share_global, effects$share_global, effects$share_global
        ), 3
      ),
      lecEquivalent = NULL,
      salaryQuintile = if (is.na(blups$salary_quintile[index])) NULL else as.integer(blups$salary_quintile[index]),
      salaryBand = if (is.na(blups$salary_lower[index])) NULL else
        whisker_round_band(list(lower = blups$salary_lower[index], upper = blups$salary_upper[index])),
      reliability = reliability[index],
      history = history
    )
  })

  whisker_write_validated(list(players = players), "player.schema.json",
                          file.path(paths$data_out, "players.json"), paths)
}

`%||%` <- function(x, y) if (is.null(x)) y else x

whisker_export_leagues <- function(league_fit, paths) {
  strengths <- lapply(league_fit$strengths, function(s) {
    s$strength <- whisker_round_estimate(s$strength, 4)
    s
  })
  whisker_write_validated(
    list(strengths = strengths, equivalences = league_fit$equivalences %||% list()),
    "leagues.schema.json", file.path(paths$data_out, "leagues.json"), paths
  )
}

whisker_export_aging <- function(aging, paths) {
  variants <- lapply(aging, function(variant) {
    variant$curves <- lapply(variant$curves, function(curve) {
      curve$peakAge <- whisker_round_estimate(curve$peakAge, 2)
      curve$points <- lapply(curve$points, function(point) {
        point$value <- whisker_round_estimate(point$value, 4)
        point
      })
      curve
    })
    variant
  })
  whisker_write_validated(list(variants = variants), "aging.schema.json",
                          file.path(paths$data_out, "aging.json"), paths)
}

whisker_export_salary <- function(salary, paths) {
  distributions <- lapply(salary$distributions, function(d) {
    d$mu <- round(d$mu, 6)
    d$sigma <- round(d$sigma, 6)
    d$pBelowFloor <- round(d$pBelowFloor, 4)
    d$quintiles <- lapply(d$quintiles, function(band) list(
      quintile = as.integer(band$quintile),
      band = whisker_round_band(list(
        lower = band$lower,
        upper = if (is.infinite(band$upper)) stats::qlnorm(0.999, d$mu, d$sigma) else band$upper
      ))
    ))
    d
  })

  anchors <- lapply(salary$anchors, function(a) list(
    id = a$id, league = a$league, season = as.integer(a$season),
    statistic = if (a$statistic == "roster_cap") "rosterCap" else a$statistic,
    value = if (is.null(a$value)) NULL else as.numeric(a$value),
    valueLower = if (is.null(a$value_lower)) NULL else as.numeric(a$value_lower),
    valueUpper = if (is.null(a$value_upper)) NULL else as.numeric(a$value_upper),
    uncertainty = if (is.null(a$uncertainty)) NULL else as.numeric(a$uncertainty),
    currency = a$currency, source = a$source, method = trimws(a$method),
    url = a$url, publishedAt = a$published_at, retrievedAt = a$retrieved_at
  ))

  whisker_write_validated(
    list(
      distributions = distributions,
      excluded = salary$exclusions,
      anchors = anchors,
      disclaimer = "Estimation statistique. Aucun salaire réel n'est connu de ce site."
    ),
    "salary.schema.json", file.path(paths$data_out, "salary.json"), paths
  )
}

whisker_export_meta <- function(games, effects, salary, synthetic, paths) {
  config <- whisker_config("leagues", paths)
  spec <- whisker_metric_spec(paths)
  components <- whisker_available_components(whisker_metric_components(games, spec), spec)

  sources <- list(
    list(name = "Oracle's Elixir", url = "https://oracleselixir.com/tools/downloads",
         licence = "Usage libre avec attribution", retrievedAt = format(Sys.Date(), "%Y-%m-%d")),
    list(name = "Leaguepedia / Fandom", url = "https://lol.fandom.com",
         licence = "CC BY-SA", retrievedAt = format(Sys.Date(), "%Y-%m-%d"))
  )

  meta <- list(
    generatedAt = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    pipelineCommit = whisker_git_commit(paths),
    lastDataDate = format(max(as.Date(games$date), na.rm = TRUE), "%Y-%m-%d"),
    confidenceLevel = WHISKER_CONFIDENCE,
    bootstrapReplicates = WHISKER_REPLICATES,
    synthetic = isTRUE(synthetic),
    performanceSource = config$performance_source %||% "oracle",
    metricComponents = as.list(components),
    counts = list(
      players = length(unique(games$playername)),
      playerGames = nrow(games),
      teams = length(unique(games$teamname)),
      leagues = length(unique(games$league_id[!is.na(games$league_id)])),
      transitions = whisker_count_transitions(games)
    ),
    unmatchedRate = 0,
    sources = sources
  )

  whisker_write_validated(meta, "meta.schema.json",
                          file.path(paths$data_out, "meta.json"), paths)
}

#' Nombre de joueurs observés dans plus d'une ligue : les transitions qui identifient le §4.2.
whisker_count_transitions <- function(games) {
  per_player <- tapply(games$league_id, games$playername, function(x) length(unique(x[!is.na(x)])))
  as.integer(sum(per_player > 1, na.rm = TRUE))
}
