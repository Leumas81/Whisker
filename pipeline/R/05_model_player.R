# Indice de valeur joueur et décomposition joueur/contexte.
#
# Entrées  : interim/player_games.parquet
# Sorties  : interim/player_effects.rds, diagnostics/*.png
# Phase    : 2 du brief.

whisker_step_05_model_player <- function(paths = whisker_paths()) {
  games <- as.data.frame(arrow::read_parquet(file.path(paths$interim, "player_games.parquet")))
  games <- whisker_metric_std(games)
  games <- games[is.finite(games$metric_std) & !games$is_international, , drop = FALSE]

  games$player <- factor(games$playername)
  games$team_season <- factor(paste(games$teamname, games$season, sep = ":"))
  games$role <- factor(games$role)

  model <- lme4::lmer(
    metric_std ~ role + (1 | player) + (1 | team_season),
    data = games, REML = TRUE,
    control = lme4::lmerControl(optimizer = "bobyqa", calc.derivs = FALSE)
  )

  variances <- whisker_variance_components(model)
  names(variances)[names(variances) == "team_season"] <- "team:season"
  share_global <- whisker_player_share(variances)
  whisker_log("05_model_player", "part joueur globale : %.3f", share_global)

  # Par rôle. Le §4.3 impose de ne jamais présenter ces valeurs sans avertissement : la part
  # joueur d'un support est mécaniquement plus faible parce que ses métriques sont plus
  # contextuelles, pas parce qu'il compterait moins.
  share_by_role <- list()
  for (role in levels(games$role)) {
    subset <- droplevels(games[games$role == role, , drop = FALSE])
    if (nrow(subset) < 300) next
    role_model <- lme4::lmer(
      metric_std ~ (1 | player) + (1 | team_season),
      data = subset, REML = TRUE,
      control = lme4::lmerControl(optimizer = "bobyqa", calc.derivs = FALSE)
    )

    draws <- whisker_bootstrap_interval(
      role_model,
      function(m) {
        v <- whisker_variance_components(m)
        names(v)[names(v) == "team_season"] <- "team:season"
        whisker_player_share(v)
      },
      replicates = WHISKER_REPLICATES
    )
    share_by_role[[role]] <- draws[[1]]
  }

  blups <- whisker_blups(model, "player")
  sigma_player <- sqrt(unname(variances[["player"]]))

  # Incertitude d'un effet joueur : erreur-type conditionnelle du BLUP. Un bootstrap complet
  # sur quatre cents joueurs coûterait des heures pour un résultat équivalent.
  conditional <- lme4::ranef(model, condVar = TRUE)$player
  standard_errors <- sqrt(as.numeric(attr(conditional, "postVar")))
  z <- stats::qnorm(1 - (1 - WHISKER_CONFIDENCE) / 2)

  blups$se <- standard_errors
  blups$lower <- blups$effect - z * blups$se
  blups$upper <- blups$effect + z * blups$se
  blups$games <- as.integer(table(games$player)[blups$level])

  whisker_diagnostic_png("05_player_effects", function() {
    graphics::par(mfrow = c(1, 2), mar = c(4, 4, 3, 1))
    stats::qqnorm(blups$effect, main = "Effets joueurs")
    stats::qqline(blups$effect)
    graphics::plot(blups$games, blups$se, log = "x", pch = 16, cex = 0.5,
                   xlab = "Games", ylab = "Erreur-type de l'effet",
                   main = "L'incertitude décroît avec l'échantillon")
  }, paths = paths)

  result <- list(
    blups = blups,
    sigma_player = sigma_player,
    share_global = share_global,
    share_by_role = share_by_role,
    variances = variances
  )
  saveRDS(result, file.path(paths$interim, "player_effects.rds"))
  invisible(result)
}
