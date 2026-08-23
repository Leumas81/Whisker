# Force de ligue par saison. BLUP de league:season, identifié séparément par les transferts
# et par les rencontres internationales.
#
# Entrées  : interim/player_games.parquet
# Sorties  : interim/league_strength.rds, diagnostics/*.png
# Phase    : 2 du brief.
#
# Le §4.1 pose le problème d'identifiabilité : sans ancrage, effets ligue et joueur sont
# confondus. Deux sources d'identification existent, et elles sont estimées séparément puis
# rapportées côte à côte. Les moyenner masquerait précisément ce qu'on veut voir.

whisker_step_04_model_league <- function(paths = whisker_paths()) {
  games <- as.data.frame(arrow::read_parquet(file.path(paths$interim, "player_games.parquet")))
  games <- whisker_metric_std(games)
  games <- games[is.finite(games$metric_std), , drop = FALSE]

  games$player <- factor(games$playername)
  games$team_season <- factor(paste(games$teamname, games$season, sep = ":"))
  games$league_season <- factor(paste(games$league_id, games$season, sep = ":"))
  games$role <- factor(games$role)

  fit_on <- function(subset, label) {
    if (nrow(subset) < 200 || nlevels(droplevels(subset$league_season)) < 2) {
      whisker_log("04_model_league", "%s : échantillon insuffisant, ignoré", label)
      return(NULL)
    }
    subset <- droplevels(subset)
    model <- lme4::lmer(
      metric_std ~ role + (1 | player) + (1 | team_season) + (1 | league_season),
      data = subset, REML = TRUE,
      control = lme4::lmerControl(optimizer = "bobyqa", calc.derivs = FALSE)
    )
    whisker_log("04_model_league", "%s : %d lignes, %d ligue-saisons",
                label, nrow(subset), nlevels(subset$league_season))
    list(model = model, data = subset, label = label)
  }

  # Identification 1 — les joueurs vus dans plus d'une ligue portent l'information.
  leagues_per_player <- tapply(games$league_id, games$playername, function(x) length(unique(x)))
  movers <- names(leagues_per_player)[leagues_per_player > 1]
  transfers <- fit_on(games[games$playername %in% movers, , drop = FALSE], "transferts")

  # Identification 2 — les rencontres internationales opposent directement les ligues.
  international_players <- unique(games$playername[games$is_international])
  international <- fit_on(
    games[games$playername %in% international_players, , drop = FALSE],
    "international"
  )

  fits <- Filter(Negate(is.null), list(transfers = transfers, international = international))
  if (length(fits) == 0) {
    stop(
      paste0(
        "Aucune source n'identifie l'effet de ligue.\n",
        "  Ni joueur passé d'une ligue à l'autre, ni rencontre internationale dans les données.\n",
        "  Sans ancrage, force de ligue et qualité des joueurs sont confondues (§4.1)."
      ),
      call. = FALSE
    )
  }

  strengths <- list()
  for (source_name in names(fits)) {
    fit <- fits[[source_name]]
    blups <- whisker_blups(fit$model, "league_season")
    counts <- table(fit$data$league_season)

    draws <- whisker_bootstrap_interval(
      fit$model,
      function(m) lme4::ranef(m)$league_season[[1]],
      replicates = WHISKER_REPLICATES
    )

    for (index in seq_len(nrow(blups))) {
      parts <- strsplit(blups$level[index], ":", fixed = TRUE)[[1]]
      strengths[[length(strengths) + 1]] <- list(
        league = parts[1],
        season = as.integer(parts[2]),
        source = if (source_name == "transfers") "transfers" else "international",
        strength = draws[[index]],
        nPlayers = length(unique(fit$data$playername[fit$data$league_season == blups$level[index]])),
        nGames = as.integer(counts[[blups$level[index]]])
      )
    }

    whisker_diagnostic_png(paste0("04_league_", source_name), function() {
      graphics::par(mfrow = c(1, 2), mar = c(4, 4, 3, 1))
      stats::qqnorm(stats::resid(fit$model), main = paste("Résidus —", fit$label))
      stats::qqline(stats::resid(fit$model))
      graphics::plot(stats::fitted(fit$model), stats::resid(fit$model),
                     xlab = "Valeurs ajustées", ylab = "Résidus",
                     main = "Homoscédasticité", pch = 16, cex = 0.3,
                     col = grDevices::rgb(0, 0, 0, 0.2))
      graphics::abline(h = 0, lty = 2)
    }, paths = paths)
  }

  # Divergence entre les deux identifications : signal d'alerte à documenter, pas à masquer.
  divergence <- whisker_league_divergence(strengths)
  if (nrow(divergence) > 0) {
    whisker_log("04_model_league", "écart max entre sources : %.3f", max(abs(divergence$gap)))
  }

  equivalences <- whisker_estimate_equivalences(games)

  saveRDS(list(strengths = strengths, divergence = divergence, equivalences = equivalences),
          file.path(paths$interim, "league_strength.rds"))
  invisible(strengths)
}

#' Coefficients d'équivalence entre ligues, sur le sous-échantillon des transitions.
#'
#' Le §4.2 pose le biais de sélection : on n'observe après transition que les joueurs jugés
#' assez bons pour monter, jamais les autres. L'équivalence estimée est donc probablement
#' optimiste. `selectionCorrection` vaut "none" : le biais est documenté et affiché, pas
#' corrigé. Le corriger demanderait un probit de promotion sur une population de candidats
#' que les données ne décrivent pas — le §4.2 laisse les deux options ouvertes, et documenter
#' une limite vaut mieux que corriger avec un modèle qu'on ne peut pas valider.
whisker_estimate_equivalences <- function(games) {
  regular <- games[!games$is_international & !is.na(games$league_id), , drop = FALSE]
  if (nrow(regular) == 0) return(list())

  per_player_league <- stats::aggregate(
    metric_std ~ playername + league_id + season,
    data = regular, FUN = mean
  )

  results <- list()
  pairs <- expand.grid(from = unique(regular$league_id), to = unique(regular$league_id),
                       stringsAsFactors = FALSE)
  pairs <- pairs[pairs$from != pairs$to, , drop = FALSE]

  for (index in seq_len(nrow(pairs))) {
    from <- pairs$from[index]
    to <- pairs$to[index]

    before <- per_player_league[per_player_league$league_id == from, ]
    after <- per_player_league[per_player_league$league_id == to, ]
    movers <- intersect(before$playername, after$playername)
    if (length(movers) < 5) next

    paired <- do.call(rbind, lapply(movers, function(name) {
      b <- before[before$playername == name, ]
      a <- after[after$playername == name, ]
      b <- b[which.max(b$season), ]
      a <- a[which.min(a$season), ]
      if (a$season <= b$season) return(NULL)
      data.frame(player = name, before = b$metric_std, after = a$metric_std,
                 stringsAsFactors = FALSE)
    }))
    if (is.null(paired) || nrow(paired) < 5) next

    fit <- stats::lm(after ~ before, data = paired)
    slope <- unname(stats::coef(fit)[["before"]])

    # Bootstrap non paramétrique sur les joueurs : l'unité de rééchantillonnage est le
    # joueur, pas la ligne, puisque c'est lui qui a effectué le trajet.
    draws <- replicate(WHISKER_REPLICATES, {
      sampled <- paired[sample(nrow(paired), replace = TRUE), ]
      if (length(unique(sampled$before)) < 2) return(NA_real_)
      unname(stats::coef(stats::lm(after ~ before, data = sampled))[["before"]])
    })

    coefficient <- whisker_quantile_interval(slope, draws[is.finite(draws)])
    coefficient <- lapply(coefficient, function(v) min(max(v, 1e-4), 1 - 1e-4))

    # Taux de base : combien sont encore présents dans la ligue cible la saison suivante.
    retained <- vapply(movers, function(name) {
      arrivals <- after$season[after$playername == name]
      any(after$season[after$playername == name] >= min(arrivals) + 1)
    }, logical(1))

    results[[length(results) + 1]] <- list(
      from = from, to = to,
      coefficient = coefficient,
      nTransitions = nrow(paired),
      selectionCorrection = "none",
      retentionOneYear = whisker_wilson_interval(sum(retained), length(retained))
    )
  }

  results
}

#' Écart entre les deux identifications, ligue-saison par ligue-saison.
whisker_league_divergence <- function(strengths) {
  if (length(strengths) == 0) return(data.frame())
  flat <- do.call(rbind, lapply(strengths, function(s) data.frame(
    league = s$league, season = s$season, source = s$source,
    point = s$strength$point, stringsAsFactors = FALSE
  )))
  wide <- stats::reshape(flat, idvar = c("league", "season"), timevar = "source",
                         direction = "wide")
  if (!all(c("point.transfers", "point.international") %in% names(wide))) return(data.frame())
  wide$gap <- wide$point.transfers - wide$point.international
  wide[!is.na(wide$gap), , drop = FALSE]
}
