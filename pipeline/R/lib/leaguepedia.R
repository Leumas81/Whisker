# Source de performance alternative : les tableaux de score de Leaguepedia.
#
# Oracle's Elixir reste la source de référence du brief. Mais sa distribution est passée à
# Google Drive, dont le quota public s'épuise et rend le jeu inatteignable pendant des jours.
# Leaguepedia expose, par la même API Cargo que les contrats, une ligne par joueur et par
# partie — vrais pseudos, vraies équipes, vraies dates.
#
# Ce que cette source n'a pas : les différentiels de lane à quinze minutes. Trois des huit
# composants de `metric_std` disparaissent donc, et `meta.json` enregistre lesquels ont
# réellement servi. Une estimation qui repose sur moins d'information doit le dire.
#
# Les requêtes sont découpées par saison et sans jointure. Une requête large jointe sur deux
# tables est systématiquement refusée par le limiteur de débit, là où les mêmes données
# demandées saison par saison passent : le coût de la requête compte autant que leur nombre.

# Un tirage de fond n'a pas la même patience qu'une poignée de requêtes : la limitation
# de débit de Fandom s'applique par fenêtre, et attendre qu'elle rouvre est le comportement
# correct. Chaque page déjà obtenue reste en cache, donc une reprise ne recommence rien.
WHISKER_BULK_ATTEMPTS <- as.integer(Sys.getenv("WHISKER_BULK_ATTEMPTS", "8"))
WHISKER_BULK_WAIT <- as.numeric(Sys.getenv("WHISKER_BULK_WAIT", "60"))

# Budget global du tirage, en minutes. Au-delà, on s'arrête en le disant plutôt que de
# laisser la CI annuler au bout de plusieurs heures sans rien produire.
WHISKER_FETCH_BUDGET <- as.numeric(Sys.getenv("WHISKER_FETCH_BUDGET_MINUTES", "45"))

# Pause entre deux requêtes. Une seconde est le minimum de politesse ; deux déclenchent
# nettement moins souvent la limitation, et coûtent moins cher que les reprises évitées.
WHISKER_BULK_PAUSE <- as.numeric(Sys.getenv("WHISKER_BULK_PAUSE", "2"))

WHISKER_SCOREBOARD_FIELDS <- paste(
  "ScoreboardPlayers.Link=playername",
  "ScoreboardPlayers.Team=teamname",
  "ScoreboardPlayers.Role=role_raw",
  "ScoreboardPlayers.Kills=kills",
  "ScoreboardPlayers.Deaths=deaths",
  "ScoreboardPlayers.Assists=assists",
  "ScoreboardPlayers.Gold=gold",
  "ScoreboardPlayers.DamageToChampions=damage",
  "ScoreboardPlayers.VisionScore=vision_score",
  "ScoreboardPlayers.TeamKills=teamkills",
  "ScoreboardPlayers.TeamGold=teamgold",
  "ScoreboardPlayers.DateTime_UTC=date",
  "ScoreboardPlayers.GameId=gameid",
  "ScoreboardPlayers.Side=side",
  sep = ", "
)

WHISKER_GAME_FIELDS <- paste(
  "ScoreboardGames.GameId=gameid",
  "ScoreboardGames.Gamelength_Number=minutes",
  sep = ", "
)

#' Postes de Leaguepedia vers le vocabulaire du projet.
WHISKER_SCOREBOARD_ROLES <- c(
  Top = "top", Jungle = "jng", Mid = "mid", Bot = "adc", Support = "sup",
  top = "top", jungle = "jng", mid = "mid", bot = "adc", support = "sup",
  ADC = "adc", adc = "adc"
)

#' Récupère les lignes joueur-game d'une ligue, saison par saison.
whisker_fetch_scoreboards <- function(league_page, seasons, paths = whisker_paths()) {
  collected <- list()

  for (season in seasons) {
    whisker_log("01_download", "%s/%d — budget restant : %.0f min",
                league_page, season, whisker_deadline_left())
    page <- sprintf("%s/%d", league_page, season)

    players <- whisker_cargo_query(
      tables = "ScoreboardPlayers",
      fields = WHISKER_SCOREBOARD_FIELDS,
      where = sprintf("ScoreboardPlayers.OverviewPage LIKE '%s%%'", page),
      order_by = "ScoreboardPlayers.GameId",
      limit = 500L, max_pages = 40L,
      pause = WHISKER_BULK_PAUSE, max_attempts = WHISKER_BULK_ATTEMPTS,
      max_wait = WHISKER_BULK_WAIT, on_rate_limit = "skip", paths = paths
    )
    if (nrow(players) == 0) {
      whisker_log("01_download", "%s : aucune partie", page)
      next
    }

    games <- whisker_cargo_query(
      tables = "ScoreboardGames",
      fields = WHISKER_GAME_FIELDS,
      where = sprintf("ScoreboardGames.OverviewPage LIKE '%s%%'", page),
      order_by = "ScoreboardGames.GameId",
      limit = 500L, max_pages = 20L,
      pause = WHISKER_BULK_PAUSE, max_attempts = WHISKER_BULK_ATTEMPTS,
      max_wait = WHISKER_BULK_WAIT, on_rate_limit = "skip", paths = paths
    )
    players$minutes <- if (nrow(games) > 0) {
      as.numeric(games$minutes[match(players$gameid, games$gameid)])
    } else {
      NA_real_
    }

    players$season_page <- page
    collected[[length(collected) + 1]] <- players
    whisker_log("01_download", "%s : %d lignes, %d parties",
                page, nrow(players), length(unique(players$gameid)))
  }

  if (length(collected) == 0) {
    stop(sprintf("Aucune ligne de tableau de score pour %s.", league_page), call. = FALSE)
  }
  do.call(rbind, collected)
}

#' Normalise les tableaux de score dans la forme attendue par l'étape 03.
#'
#' Rend exactement les colonnes qu'attend le nettoyage, en laissant à NA celles que cette
#' source ne porte pas. Un NA franc vaut mieux qu'un zéro qui se ferait passer pour une mesure.
whisker_normalise_scoreboards <- function(rows) {
  numeric_columns <- c("kills", "deaths", "assists", "gold", "damage",
                       "vision_score", "teamkills", "teamgold", "minutes")
  for (column in numeric_columns) {
    rows[[column]] <- suppressWarnings(as.numeric(rows[[column]]))
  }

  rows$role <- unname(WHISKER_SCOREBOARD_ROLES[rows$role_raw])
  rows$date <- as.Date(substr(rows$date, 1, 10))
  rows$gamelength <- rows$minutes * 60
  rows$side <- ifelse(rows$side == "1", "Blue", "Red")

  # Parts d'équipe : la somme des dégâts des cinq joueurs du même camp donne le dénominateur
  # que Leaguepedia ne fournit pas, contrairement à l'or.
  key <- paste(rows$gameid, rows$side, sep = "|")
  team_damage <- stats::ave(rows$damage, key, FUN = function(x) sum(x, na.rm = TRUE))
  rows$damageshare <- ifelse(team_damage > 0, rows$damage / team_damage, NA_real_)
  rows$earnedgoldshare <- ifelse(rows$teamgold > 0, rows$gold / rows$teamgold, NA_real_)
  rows$vspm <- ifelse(rows$minutes > 0, rows$vision_score / rows$minutes, NA_real_)
  rows$dpm <- ifelse(rows$minutes > 0, rows$damage / rows$minutes, NA_real_)

  # Absents de cette source : les différentiels de lane à quinze minutes.
  rows$golddiffat15 <- NA_real_
  rows$xpdiffat15 <- NA_real_
  rows$csdiffat15 <- NA_real_
  rows$wpm <- NA_real_
  rows$result <- NA_integer_
  rows$split <- "Regular"
  rows$datacompleteness <- "complete"
  rows$position <- rows$role

  keep <- c(
    "gameid", "datacompleteness", "date", "league", "split", "side", "position",
    "playername", "teamname", "result", "gamelength", "kills", "deaths", "assists",
    "teamkills", "golddiffat15", "xpdiffat15", "csdiffat15", "damageshare",
    "earnedgoldshare", "dpm", "vspm", "wpm", "role"
  )

  rows <- rows[, keep, drop = FALSE]
  rows[is.finite(rows$gamelength) & rows$gamelength > 0 & !is.na(rows$role), , drop = FALSE]
}
