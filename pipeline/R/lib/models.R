# Briques de modélisation communes aux étapes 04 à 07.
#
# Tout ce qui est ici est testable sur de petits jeux synthétiques : extraction des effets
# aléatoires, décomposition de variance, intervalles par bootstrap. Les étapes se contentent
# d'assembler.

WHISKER_CONFIDENCE <- 0.8

# Deux mille réplications, comme le veut le §4.6. Le nombre reste réglable par variable
# d'environnement : la CI l'abaisse pour une exécution de contrôle, et le générateur
# synthétique n'a pas besoin de cette précision pour vérifier la mécanique.
WHISKER_REPLICATES <- as.integer(Sys.getenv("WHISKER_REPLICATES", "2000"))

#' Bornes de quantile pour un niveau de confiance donné.
whisker_ci_probs <- function(level = WHISKER_CONFIDENCE) {
  alpha <- (1 - level) / 2
  c(lower = alpha, upper = 1 - alpha)
}

#' Assemble une estimation au format du contrat de données.
#'
#' Le tri final n'est pas cosmétique : un bootstrap peut rendre des quantiles dans le désordre
#' sur de très petits échantillons, et le schéma refuserait l'objet. Mieux vaut le corriger
#' ici, où l'on sait que c'est un artefact d'échantillonnage.
whisker_estimate <- function(point, lower, upper) {
  bounds <- sort(c(lower, upper))
  list(
    point = unname(min(max(point, bounds[1]), bounds[2])),
    lower = unname(bounds[1]),
    upper = unname(bounds[2])
  )
}

#' Effets aléatoires d'un facteur, sous forme de table nommée.
whisker_blups <- function(model, group) {
  effects <- lme4::ranef(model, condVar = TRUE)[[group]]
  data.frame(
    level = rownames(effects),
    effect = effects[[1]],
    stringsAsFactors = FALSE
  )
}

#' Écarts-types des composantes de variance d'un modèle mixte.
whisker_variance_components <- function(model) {
  components <- as.data.frame(lme4::VarCorr(model))
  stats::setNames(components$vcov, components$grp)
}

#' Part de la variance revenant au joueur plutôt qu'au contexte d'équipe.
#'
#' `playerShare = s2_joueur / (s2_joueur + s2_equipe:saison)`, §4.3 du brief. Le résidu est
#' délibérément exclu du dénominateur : la question posée est « du joueur ou de son équipe ? »,
#' pas « quelle part du bruit de partie en partie ? ».
whisker_player_share <- function(variances, player_key = "player", team_key = "team:season") {
  missing <- setdiff(c(player_key, team_key), names(variances))
  if (length(missing) > 0) {
    stop(sprintf("Composantes de variance absentes : %s", paste(missing, collapse = ", ")),
         call. = FALSE)
  }
  total <- variances[[player_key]] + variances[[team_key]]
  if (!is.finite(total) || total <= 0) {
    stop("Variances joueur et équipe toutes deux nulles : rien à décomposer.", call. = FALSE)
  }
  variances[[player_key]] / total
}

#' Intervalle d'une statistique par bootstrap paramétrique sur les effets aléatoires.
#'
#' `replicates` est ramené à une poignée dans les tests : deux mille réplications sur quinze
#' mille lignes n'ont leur place qu'en CI.
whisker_bootstrap_interval <- function(model, statistic, replicates = WHISKER_REPLICATES,
                                       level = WHISKER_CONFIDENCE, seed = 1L) {
  set.seed(seed)
  draws <- lme4::bootMer(model, statistic, nsim = replicates, type = "parametric",
                         use.u = FALSE, .progress = "none")
  probs <- whisker_ci_probs(level)
  observed <- statistic(model)

  bounds <- apply(as.matrix(draws$t), 2, stats::quantile,
                  probs = c(probs[["lower"]], probs[["upper"]]), na.rm = TRUE)
  lapply(seq_along(observed), function(index) {
    whisker_estimate(observed[index], bounds[1, index], bounds[2, index])
  })
}

#' Intervalle empirique d'un vecteur de réplications.
whisker_quantile_interval <- function(point, draws, level = WHISKER_CONFIDENCE) {
  probs <- whisker_ci_probs(level)
  bounds <- stats::quantile(draws, probs = c(probs[["lower"]], probs[["upper"]]), na.rm = TRUE)
  whisker_estimate(point, bounds[[1]], bounds[[2]])
}

#' Intervalle de Wilson pour une proportion.
#'
#' Un taux de base sans intervalle contredirait la règle fondatrice du §1.2 ; Wilson tient
#' correctement sur les petits effectifs, là où l'intervalle normal déborde de [0,1].
whisker_wilson_interval <- function(successes, total, level = WHISKER_CONFIDENCE) {
  if (total <= 0) return(whisker_estimate(0, 0, 1))
  z <- stats::qnorm(1 - (1 - level) / 2)
  proportion <- successes / total
  denominator <- 1 + z^2 / total
  centre <- (proportion + z^2 / (2 * total)) / denominator
  half <- z * sqrt(proportion * (1 - proportion) / total + z^2 / (4 * total^2)) / denominator
  whisker_estimate(proportion, max(0, centre - half), min(1, centre + half))
}

#' Enregistre un diagnostic graphique.
#'
#' Le §7 du brief exige des diagnostics exportés en PNG : le propriétaire juge sur des images,
#' pas sur du code.
whisker_diagnostic_png <- function(name, draw, paths = whisker_paths(),
                                   width = 900, height = 650) {
  dir.create(paths$diagnostics, recursive = TRUE, showWarnings = FALSE)
  file <- file.path(paths$diagnostics, paste0(name, ".png"))
  grDevices::png(file, width = width, height = height, res = 110)
  on.exit(grDevices::dev.off(), add = TRUE)
  draw()
  invisible(file)
}
