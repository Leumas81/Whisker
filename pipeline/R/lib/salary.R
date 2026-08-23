# Calibration salariale — §4.5 du brief.
#
# Deux choses seulement : identifier une log-normale à partir d'ancres sourcées, et refuser
# de le faire quand les ancres ne suffisent pas. Le second point compte autant que le premier.

#' Log-normale simple identifiée par sa médiane et sa moyenne.
whisker_lognormal_from_moments <- function(median_value, mean_value) {
  if (mean_value <= median_value) {
    stop(
      "Une log-normale a toujours une moyenne strictement supérieure à sa médiane. ",
      "Des ancres qui disent le contraire sont incohérentes.",
      call. = FALSE
    )
  }
  mu <- log(median_value)
  list(mu = mu, sigma = sqrt(2 * (log(mean_value) - mu)), truncated = FALSE, floor = NA_real_)
}

#' Masse de probabilité située sous un plancher.
whisker_mass_below <- function(params, floor_value) {
  if (params$truncated) return(0)
  stats::plnorm(floor_value, meanlog = params$mu, sdlog = params$sigma)
}

#' Moyenne et médiane d'une log-normale tronquée à gauche.
whisker_truncated_moments <- function(mu, sigma, floor_value) {
  wa <- (log(floor_value) - mu) / sigma
  mass <- stats::pnorm(wa, lower.tail = FALSE)
  if (mass <= 0) return(list(mean = Inf, median = Inf))
  list(
    mean = exp(mu + sigma^2 / 2) * stats::pnorm(wa - sigma, lower.tail = FALSE) / mass,
    # Médiane tronquée : F(m) = 0,5 sur le support restant.
    median = exp(mu + sigma * stats::qnorm(0.5 * (1 + stats::pnorm(wa))))
  )
}

#' Ré-identifie numériquement une log-normale tronquée à gauche restituant les deux moments.
#'
#' Le §4.5 prévoit cette étape en cas de dépassement du seuil ; avec les ancres LEC réelles,
#' elle n'est pas facultative : la loi non tronquée place 12 % des joueurs sous le plancher
#' réglementaire, ce qui ne peut pas exister.
whisker_lognormal_truncated <- function(median_value, mean_value, floor_value) {
  start <- whisker_lognormal_from_moments(median_value, mean_value)

  cost <- function(par) {
    if (par[2] <= 0.01) return(1e9)
    moments <- whisker_truncated_moments(par[1], par[2], floor_value)
    if (!is.finite(moments$mean) || !is.finite(moments$median)) return(1e9)
    ((moments$mean - mean_value) / mean_value)^2 + ((moments$median - median_value) / median_value)^2
  }

  fit <- stats::optim(c(start$mu, start$sigma), cost, method = "Nelder-Mead",
                      control = list(reltol = 1e-12, maxit = 5000))
  if (fit$value > 1e-6) {
    stop("La ré-identification tronquée n'a pas convergé sur les deux moments visés.", call. = FALSE)
  }

  list(mu = fit$par[1], sigma = fit$par[2], truncated = TRUE, floor = floor_value)
}

#' Calibre la distribution d'une ligue, ou refuse de le faire.
#'
#' Rend `NULL` quand la configuration déclare la ligue non publiable. Un `NULL` n'est pas un
#' échec : c'est le résultat correct quand les sources ne portent pas de distribution.
whisker_calibrate_league <- function(league, season, config, max_below_floor = 0.05) {
  spec <- Filter(
    function(d) d$league == league && d$season == season,
    config$distributions
  )
  if (length(spec) == 0) {
    stop(sprintf("Aucune règle de publication pour %s %d dans salary_anchors.yaml", league, season),
         call. = FALSE)
  }
  spec <- spec[[1]]
  if (!isTRUE(spec$publish)) return(NULL)

  anchor_by_id <- function(id) {
    match <- Filter(function(a) a$id == id, config$anchors)
    if (length(match) == 0) stop(sprintf("Ancre introuvable : %s", id), call. = FALSE)
    match[[1]]
  }

  moments <- lapply(spec$moments, anchor_by_id)
  statistics <- vapply(moments, function(a) a$statistic, character(1))
  if (!all(c("mean", "median") %in% statistics)) {
    stop(
      sprintf("%s %d est déclarée publiable sans porter à la fois une moyenne et une médiane.",
              league, season),
      call. = FALSE
    )
  }

  mean_value <- as.numeric(moments[[which(statistics == "mean")]]$value)
  median_value <- as.numeric(moments[[which(statistics == "median")]]$value)
  floor_value <- as.numeric(anchor_by_id(spec$floor)$value)

  params <- whisker_lognormal_from_moments(median_value, mean_value)
  below <- whisker_mass_below(params, floor_value)
  if (below >= max_below_floor) {
    params <- whisker_lognormal_truncated(median_value, mean_value, floor_value)
  }

  c(params, list(
    league = league,
    season = season,
    basis = spec$basis,
    untruncated_mass_below_floor = below
  ))
}

#' Bornes de quintile d'une distribution calibrée.
whisker_quintile_bands <- function(params, upper_quantile = 0.999) {
  probabilities <- c(seq(0, 0.8, by = 0.2), upper_quantile)
  cuts <- vapply(probabilities, function(p) whisker_quantile(params, p), numeric(1))
  lapply(1:5, function(q) list(quintile = q, lower = cuts[q], upper = cuts[q + 1]))
}

#' Quantile d'une log-normale, tronquée ou non.
whisker_quantile <- function(params, p) {
  if (!params$truncated) {
    if (p <= 0) return(0)
    if (p >= 1) return(Inf)
    return(stats::qlnorm(p, meanlog = params$mu, sdlog = params$sigma))
  }
  wa <- (log(params$floor) - params$mu) / params$sigma
  base <- stats::pnorm(wa)
  if (p <= 0) return(params$floor)
  if (p >= 1) return(Inf)
  exp(params$mu + params$sigma * stats::qnorm(base + p * (1 - base)))
}
