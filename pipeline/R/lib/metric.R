# Calcul de `metric_std`, conformément à config/metric.yaml.
#
# Le fichier de configuration est la spécification ; ce fichier n'en est que l'exécution.
# Aucune constante de la métrique n'est écrite ici : ni la liste des composants, ni la
# matrice d'inclusion, ni les centiles de winsorisation. Un test le vérifie.

whisker_metric_spec <- function(paths = whisker_paths()) {
  spec <- whisker_config("metric", paths)

  keys <- vapply(spec$components, function(component) component$key, character(1))
  if (anyDuplicated(keys) > 0) {
    stop("config/metric.yaml : clés de composants dupliquées.", call. = FALSE)
  }
  unknown <- setdiff(unlist(spec$inclusion, use.names = FALSE), keys)
  if (length(unknown) > 0) {
    stop(
      sprintf("config/metric.yaml : la matrice d'inclusion cite des composants inconnus : %s",
              paste(unique(unknown), collapse = ", ")),
      call. = FALSE
    )
  }
  spec
}

# ── Composants bruts ───────────────────────────────────────────────────────────────────

#' Calcule les composants à partir d'une table joueur-game.
#'
#' Les formules ne sont pas écrites ici : elles sont évaluées depuis le champ `expression`
#' de config/metric.yaml. C'est ce qui fait de la configuration la spécification véritable
#' plutôt qu'un commentaire que le code pourrait démentir en silence.
#'
#' `games` doit porter les colonnes d'Oracle's Elixir plus `team_kills`, repris de la ligne
#' agrégée d'équipe du même gameid et du même côté.
whisker_metric_components <- function(games, spec = whisker_metric_spec()) {
  if (!"gamelength" %in% names(games)) {
    stop("Colonnes absentes : gamelength", call. = FALSE)
  }
  if (any(games$gamelength <= 0, na.rm = TRUE)) {
    stop("Une partie de durée nulle ou négative est présente.", call. = FALSE)
  }

  for (component in spec$components) {
    value <- tryCatch(
      eval(parse(text = component$expression), envir = games, enclos = baseenv()),
      error = function(condition) {
        stop(
          sprintf(
            "Colonnes absentes pour le composant « %s » (%s) : %s",
            component$key, component$expression, conditionMessage(condition)
          ),
          call. = FALSE
        )
      }
    )
    games[[component$key]] <- as.numeric(value)
  }

  games
}

# ── Winsorisation ──────────────────────────────────────────────────────────────────────

whisker_winsorize <- function(x, lower, upper) {
  finite <- x[is.finite(x)]
  if (length(finite) < 3) return(x)
  bounds <- stats::quantile(finite, probs = c(lower, upper), names = FALSE, na.rm = TRUE)
  pmin(pmax(x, bounds[1]), bounds[2])
}

# ── Standardisation sur la référence LEC ───────────────────────────────────────────────

#' Indices des lignes servant de référence pour un couple (poste, saison).
#'
#' La référence est la sous-population de la ligue étalon au même poste et à la même saison.
#' Si elle est trop maigre pour estimer un écart-type stable, on l'élargit aux saisons
#' adjacentes plutôt que de produire une échelle fantaisiste.
whisker_reference_rows <- function(games, role, season, reference_league, min_rows) {
  base <- which(games$role == role & games$league == reference_league & games$season == season)
  if (length(base) >= min_rows) return(base)

  widened <- which(
    games$role == role &
      games$league == reference_league &
      abs(games$season - season) <= 1
  )
  if (length(widened) >= min_rows) return(widened)
  widened
}

#' Centre-réduit `values` en utilisant les lignes de référence pour la position et l'échelle.
whisker_standardise_against <- function(values, reference) {
  centre <- mean(reference, na.rm = TRUE)
  echelle <- stats::sd(reference, na.rm = TRUE)
  if (!is.finite(echelle) || echelle == 0) return(rep(NA_real_, length(values)))
  (values - centre) / echelle
}

# ── Composite ──────────────────────────────────────────────────────────────────────────

#' Ajoute `metric_std` à une table joueur-game.
#'
#' Attend les colonnes `role`, `league`, `season` en plus de celles d'Oracle's Elixir.
#' Rend la table augmentée des composants centrés-réduits (préfixe `z_`) et de `metric_std`.
whisker_metric_std <- function(games, spec = whisker_metric_spec()) {
  games <- whisker_metric_components(games, spec)

  keys <- vapply(spec$components, function(component) component$key, character(1))
  lower <- spec$winsorize$lower_quantile
  upper <- spec$winsorize$upper_quantile
  reference_league <- spec$standardisation$reference_league
  min_rows <- spec$standardisation$min_reference_rows

  groups <- unique(games[, c("role", "season")])
  for (key in keys) games[[paste0("z_", key)]] <- NA_real_

  for (index in seq_len(nrow(groups))) {
    role <- groups$role[index]
    season <- groups$season[index]
    rows <- which(games$role == role & games$season == season)
    reference <- whisker_reference_rows(games, role, season, reference_league, min_rows)
    if (length(reference) < 2) next

    for (key in keys) {
      # La winsorisation s'applique au groupe (poste, saison) tout entier, la référence
      # n'en étant qu'un sous-ensemble : les deux doivent partager la même échelle.
      scope <- union(rows, reference)
      clipped <- whisker_winsorize(games[[key]][scope], lower, upper)
      names(clipped) <- as.character(scope)

      games[[paste0("z_", key)]][rows] <- whisker_standardise_against(
        clipped[as.character(rows)],
        clipped[as.character(reference)]
      )
    }
  }

  # Poids unitaires sur les seuls composants retenus pour le poste.
  games$metric_std <- NA_real_
  for (role in names(spec$inclusion)) {
    included <- paste0("z_", spec$inclusion[[role]])
    rows <- which(games$role == role)
    if (length(rows) == 0) next
    block <- as.matrix(games[rows, included, drop = FALSE])
    games$metric_std[rows] <- rowMeans(block, na.rm = FALSE)
  }

  if (isTRUE(spec$aggregation$restandardise)) {
    for (index in seq_len(nrow(groups))) {
      role <- groups$role[index]
      season <- groups$season[index]
      rows <- which(games$role == role & games$season == season)
      reference <- whisker_reference_rows(games, role, season, reference_league, min_rows)
      if (length(reference) < 2) next
      games$metric_std[rows] <- whisker_standardise_against(
        games$metric_std[rows],
        games$metric_std[reference]
      )
    }
  }

  games
}

# ── Passage à l'indice affiché ─────────────────────────────────────────────────────────

#' Transforme un effet joueur en indice de valeur affichable.
#'
#' Monotone croissante, donc applicable telle quelle aux bornes d'un intervalle : l'ordre
#' et la couverture sont préservés.
whisker_value_index <- function(blup, sigma_player, spec = whisker_metric_spec()) {
  if (!is.finite(sigma_player) || sigma_player <= 0) {
    stop("L'écart-type des effets joueurs doit être strictement positif.", call. = FALSE)
  }
  clip <- unlist(spec$value_index$clip)
  raw <- 50 + 15 * (blup / sigma_player)
  round(pmin(pmax(raw, clip[1]), clip[2]), spec$value_index$decimals)
}
