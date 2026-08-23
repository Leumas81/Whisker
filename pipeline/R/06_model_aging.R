# Courbes de vieillissement par rôle, en deux variantes pour rendre le biais de survie visible.
#
# Entrées  : interim/player_games.parquet
# Sorties  : interim/aging.rds, diagnostics/*.png
# Phase    : 2 du brief.
#
# Le §4.4 est explicite : les joueurs faibles quittent le circuit, donc la courbe remonte
# artificiellement en fin de carrière. Les deux variantes sont exportées et affichables
# ensemble ; aucune n'est présentée comme la bonne.

WHISKER_AGING_MIN_SEASONS <- 3L

whisker_step_06_model_aging <- function(paths = whisker_paths()) {
  games <- as.data.frame(arrow::read_parquet(file.path(paths$interim, "player_games.parquet")))
  games <- whisker_metric_std(games)
  games <- games[is.finite(games$metric_std) & is.finite(games$age), , drop = FALSE]

  seasons_per_player <- tapply(games$season, games$playername, function(x) length(unique(x)))
  tenured <- names(seasons_per_player)[seasons_per_player >= WHISKER_AGING_MIN_SEASONS]

  variants <- list(
    list(
      id = "all", min_seasons = 1L,
      label = "Tous les joueurs",
      note = paste(
        "Sujette au biais de survie : les joueurs qui déclinent quittent le circuit, si bien",
        "que la courbe remonte en fin de carrière sans qu'aucun joueur ne se soit amélioré."
      ),
      rows = games
    ),
    list(
      id = "tenured", min_seasons = WHISKER_AGING_MIN_SEASONS,
      label = sprintf("Joueurs à %d saisons au moins", WHISKER_AGING_MIN_SEASONS),
      note = paste(
        "Le biais est atténué en n'observant que des carrières longues, au prix d'un",
        "échantillon plus petit et d'une sélection sur les joueurs qui ont duré."
      ),
      rows = games[games$playername %in% tenured, , drop = FALSE]
    )
  )

  built <- lapply(variants, function(variant) {
    rows <- droplevels(variant$rows)
    rows$role <- factor(rows$role)
    rows$player <- factor(rows$playername)

    model <- mgcv::gam(
      metric_std ~ role + s(age, by = role, k = 6) + s(player, bs = "re"),
      data = rows, method = "REML"
    )

    curves <- lapply(levels(rows$role), function(role) {
      role_rows <- rows[rows$role == role, , drop = FALSE]
      grid_ages <- seq(
        max(16, floor(stats::quantile(role_rows$age, 0.02))),
        min(35, ceiling(stats::quantile(role_rows$age, 0.98))),
        by = 0.5
      )
      newdata <- data.frame(
        age = grid_ages,
        role = factor(role, levels = levels(rows$role)),
        player = rows$player[1]
      )
      prediction <- stats::predict(model, newdata, se.fit = TRUE, exclude = "s(player)")
      z <- stats::qnorm(1 - (1 - WHISKER_CONFIDENCE) / 2)

      points <- lapply(seq_along(grid_ages), function(index) list(
        age = grid_ages[index],
        value = whisker_estimate(
          prediction$fit[index],
          prediction$fit[index] - z * prediction$se.fit[index],
          prediction$fit[index] + z * prediction$se.fit[index]
        )
      ))

      list(
        role = role,
        peakAge = whisker_peak_age(grid_ages, prediction$fit, prediction$se.fit),
        nPlayers = length(unique(role_rows$playername)),
        nGames = nrow(role_rows),
        points = points
      )
    })

    whisker_diagnostic_png(paste0("06_aging_", variant$id), function() {
      # plot.gam ne trace qu'un lissage à la fois : on boucle plutôt que de lui passer un vecteur.
      smooths <- seq_len(min(5, length(model$smooth)))
      graphics::par(mfrow = c(2, 3), mar = c(4, 4, 3, 1))
      for (index in smooths) plot(model, select = index, shade = TRUE)
    }, paths = paths)

    list(id = variant$id, label = variant$label,
         survivorshipNote = variant$note,
         minSeasons = variant$min_seasons, curves = curves)
  })

  saveRDS(built, file.path(paths$interim, "aging.rds"))
  invisible(built)
}

#' Âge de pic et son intervalle.
#'
#' L'intervalle est l'ensemble des âges dont la prédiction n'est pas distinguable du maximum
#' au niveau retenu. C'est plus honnête qu'un intervalle autour de l'argmax : sur une courbe
#' plate au sommet, le pic n'est de toute façon pas localisable finement.
whisker_peak_age <- function(ages, fitted, standard_errors) {
  best <- which.max(fitted)
  z <- stats::qnorm(1 - (1 - WHISKER_CONFIDENCE) / 2)
  threshold <- fitted[best] - z * standard_errors[best]
  plausible <- ages[fitted >= threshold]
  whisker_estimate(ages[best], min(plausible), max(plausible))
}
