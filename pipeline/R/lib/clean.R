# Nettoyage et réconciliation des identités — le cœur testable de l'étape 03.
#
# Les fonctions d'ici sont pures : elles prennent des tables, en rendent d'autres, ne lisent
# ni n'écrivent rien. C'est ce qui les rend vérifiables sans réseau ni fichier.

#' Applique la table d'alias : rend le nom canonique de chaque valeur.
#'
#' Une valeur inconnue de la table est rendue telle quelle. C'est voulu : la grande majorité
#' des pseudos n'a jamais changé et n'a rien à faire dans le fichier d'alias.
whisker_canonical <- function(values, aliases) {
  if (length(aliases) == 0) return(values)
  lookup <- new.env(parent = emptyenv(), hash = TRUE)
  for (entry in aliases) {
    for (alias in c(entry$aliases, entry$canonical)) {
      assign(tolower(alias), entry$canonical, envir = lookup)
    }
  }
  vapply(
    values,
    function(value) {
      key <- tolower(value)
      if (exists(key, envir = lookup, inherits = FALSE)) get(key, envir = lookup) else value
    },
    character(1),
    USE.NAMES = FALSE
  )
}

#' Traduit les postes d'Oracle's Elixir vers le vocabulaire du projet.
#'
#' Un poste inconnu devient NA plutôt que d'être deviné : la ligne sera écartée et comptée.
whisker_map_positions <- function(positions, mapping) {
  translated <- unlist(mapping)[tolower(positions)]
  unname(translated)
}

#' Reporte les éliminations de l'équipe sur chaque ligne joueur.
#'
#' `teams` est le sous-ensemble des lignes agrégées (position == "team"). L'appariement se
#' fait sur (gameid, side) : deux équipes par partie, cinq joueurs chacune.
whisker_attach_team_kills <- function(players, teams) {
  key_players <- paste(players$gameid, players$side, sep = "|")
  key_teams <- paste(teams$gameid, teams$side, sep = "|")
  players$team_kills <- teams$teamkills[match(key_players, key_teams)]
  players
}

#' Dérive la saison d'une date de partie.
whisker_season_of <- function(dates) {
  as.integer(format(as.Date(dates), "%Y"))
}

#' Âge en années à une date de référence.
whisker_age_at <- function(birthdate, reference) {
  birthdate <- as.Date(birthdate)
  reference <- as.Date(reference)
  as.numeric(difftime(reference, birthdate, units = "days")) / 365.25
}

#' Niveau de fiabilité, dérivé du nombre de games.
#'
#' Les seuils viennent de config/leagues.yaml, jamais du code : le §3.4 du brief les fixe et
#' un test vérifie qu'ils y correspondent.
whisker_reliability <- function(games, thresholds) {
  out <- rep(NA_character_, length(games))
  out[games >= thresholds$low_min_games] <- "low"
  out[games >= thresholds$medium_min_games] <- "medium"
  out[games >= thresholds$high_min_games] <- "high"
  out
}

#' Entités non résolues, et taux correspondant.
#'
#' Une entité est non résolue quand une colonne indispensable manque après jointure. Le
#' pipeline échoue au-delà du seuil : le §3.2 interdit la dégradation silencieuse.
whisker_unmatched <- function(data, columns) {
  incomplete <- Reduce(`|`, lapply(columns, function(column) is.na(data[[column]])))
  list(
    rows = data[incomplete, , drop = FALSE],
    rate = if (nrow(data) == 0) 0 else sum(incomplete) / nrow(data)
  )
}

#' Vérifie qu'une table porte bien les colonnes attendues.
whisker_require_columns <- function(data, columns, source_label) {
  missing <- setdiff(columns, names(data))
  if (length(missing) > 0) {
    stop(
      sprintf(
        "%s : colonnes attendues absentes — %s.\nLe format de la source a probablement changé.",
        source_label, paste(missing, collapse = ", ")
      ),
      call. = FALSE
    )
  }
  invisible(TRUE)
}

#' Écarte les doublons stricts (gameid, playername) en signalant leur nombre.
whisker_drop_duplicate_rows <- function(data) {
  key <- paste(data$gameid, data$playername, sep = "|")
  duplicated_rows <- duplicated(key)
  if (any(duplicated_rows)) {
    whisker_log("03_clean", "%d doublon(s) gameid x playername écarté(s)", sum(duplicated_rows))
  }
  data[!duplicated_rows, , drop = FALSE]
}
