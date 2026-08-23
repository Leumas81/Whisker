#!/usr/bin/env Rscript
# Jeu de développement synthétique.
#
# Les deux sources du projet ne sont pas joignables depuis toutes les machines : Oracle's
# Elixir passe par Google Drive, dont le quota public s'épuise, et l'API Cargo limite les IP
# partagées. Sans données, ni le forest plot ni les pages ne peuvent être construits ni relus.
#
# Ce script fabrique donc un jeu de la même forme que le vrai, puis lui fait traverser les
# étapes 04 à 08 réelles — mêmes modèles, mêmes validations, mêmes schémas. Il ne remplace pas
# les vraies données : il permet de construire le site en attendant, et il vérifie au passage
# que la chaîne de modélisation fonctionne de bout en bout.
#
# `meta.json` porte alors `synthetic: true`. Le site affiche un bandeau permanent et
# `pnpm verify:release` échoue : ces chiffres ne peuvent pas être publiés.

suppressPackageStartupMessages({
  library(yaml); library(jsonlite); library(arrow)
  library(lme4); library(mgcv); library(dplyr)
})

args <- commandArgs(trailingOnly = FALSE)
fixtures_dir <- dirname(normalizePath(sub("^--file=", "", grep("^--file=", args, value = TRUE)[1])))
Sys.setenv(WHISKER_ROOT = normalizePath(file.path(fixtures_dir, "..", ".."), mustWork = TRUE))

source(file.path(fixtures_dir, "..", "R", "00_setup.R"))
paths <- whisker_ensure_dirs()
whisker_source_lib(paths)
for (step in c("04_model_league", "05_model_player", "06_model_aging", "07_salary", "08_export")) {
  source(file.path(paths$pipeline, "R", paste0(step, ".R")))
}

# Le bootstrap complet du §4.6 n'a pas sa place ici : on vérifie la mécanique, pas la précision.
WHISKER_REPLICATES <- as.integer(Sys.getenv("WHISKER_FIXTURE_REPLICATES", "120"))

set.seed(20260822)

SEASONS <- 2019:2026
ROLES <- c("top", "jng", "mid", "adc", "sup")

# ── Univers : équipes, joueurs, carrières ────────────────────────────────────────────────
teams <- list(
  LEC = c("G2 Esports", "Fnatic", "Karmine Corp", "Movistar KOI", "Team Heretics",
          "Team Vitality", "SK Gaming", "Team BDS", "GiantX", "Rogue"),
  LFL = c("Karmine Corp Blue", "Solary", "Vitality.Bee", "GameWard", "BK ROG",
          "Team Du Sud", "Aegis", "Izi Dream", "Gentle Mates", "Ici Japon Corp")
)

prenoms <- c("Vlad", "Kais", "Noor", "Elio", "Rami", "Tobi", "Sasha", "Nils", "Juno", "Emre",
             "Lior", "Milo", "Anka", "Bran", "Cedr", "Doru", "Enzo", "Faro", "Gwen", "Hako",
             "Ilan", "Jaro", "Kiro", "Lume", "Mako", "Nael", "Orin", "Pavo", "Quin", "Rune",
             "Silo", "Taro", "Ulis", "Vero", "Wilo", "Xano", "Yuri", "Zeno", "Arno", "Bilo")
suffixes <- c("", "z", "x", "ko", "ne", "us", "el", "ka", "ro", "an")

make_players <- function(n, league, role_cycle) {
  data.frame(
    playername = paste0(
      sample(prenoms, n, replace = TRUE),
      sample(suffixes, n, replace = TRUE),
      sample(c("", as.character(1:99)), n, replace = TRUE, prob = c(0.75, rep(0.25 / 99, 99)))
    ),
    role = role_cycle,
    home = league,
    skill = stats::rnorm(n, if (league == "LEC") 0.35 else -0.35, 0.55),
    stringsAsFactors = FALSE
  )
}

roster <- rbind(
  make_players(90, "LEC", rep(ROLES, length.out = 90)),
  make_players(160, "LFL", rep(ROLES, length.out = 160))
)
roster$playername <- make.unique(roster$playername, sep = "")

# Carrières : chaque joueur couvre une plage de saisons, quelques-uns changent de ligue.
roster$first_season <- sample(SEASONS[1:6], nrow(roster), replace = TRUE)
roster$last_season <- pmin(2026L, roster$first_season + sample(1:7, nrow(roster), replace = TRUE))

# L'âge à la première saison tourne autour de vingt ans : un joueur ne débute pas à quinze.
roster$birthdate <- as.Date(sprintf("%d-06-01", roster$first_season)) -
  round(pmax(17, stats::rnorm(nrow(roster), 20.2, 1.8)) * 365.25)
# Promotion déterministe : les meilleurs LFL montent. Une sélection tirée au sort variait
# d'une exécution à l'autre et laissait parfois trop peu de transferts pour que la force de
# ligue soit identifiable — ce qui est justement ce que le §4.1 met en garde.
lfl_rows <- which(roster$home == "LFL")
promoted_rows <- lfl_rows[order(roster$skill[lfl_rows], decreasing = TRUE)][1:40]
roster$promoted <- FALSE
roster$promoted[promoted_rows] <- TRUE
roster$promotion_season <- ifelse(
  roster$promoted,
  pmin(roster$last_season, roster$first_season + sample(1:3, nrow(roster), replace = TRUE)),
  NA_integer_
)

# ── Parties ─────────────────────────────────────────────────────────────────────────────
LEAGUE_EFFECT <- c(LEC = 0.0, LFL = -0.55)
peak_age <- c(top = 23.5, jng = 22.5, mid = 23.0, adc = 24.0, sup = 25.0)

rows <- list()
game_counter <- 0L

for (season in SEASONS) {
  active <- roster[roster$first_season <= season & roster$last_season >= season, , drop = FALSE]
  if (nrow(active) == 0) next

  active$league <- ifelse(
    !is.na(active$promotion_season) & season >= active$promotion_season, "LEC", active$home
  )

  for (league in c("LEC", "LFL")) {
    pool <- active[active$league == league, , drop = FALSE]
    if (nrow(pool) < 10) next

    # Les titulaires sont les meilleurs de leur poste. Trier par ordre d'apparition
    # reléguait systématiquement les promus au banc, et il ne restait aucun transfert
    # observable des deux côtés.
    pool <- pool[order(pool$role, -pool$skill), ]
    squads <- split(pool, pool$role)
    n_teams <- min(vapply(squads, nrow, integer(1)))
    if (n_teams < 2) next
    n_teams <- min(n_teams, length(teams[[league]]))

    assignment <- do.call(rbind, lapply(ROLES, function(role) {
      members <- squads[[role]][seq_len(n_teams), , drop = FALSE]
      members$team <- teams[[league]][seq_len(n_teams)]
      members
    }))

    n_games <- if (league == "LEC") 95 else 85
    for (game in seq_len(n_games)) {
      pair <- sample(teams[[league]][seq_len(n_teams)], 2)
      game_counter <- game_counter + 1L
      gameid <- sprintf("SYN-%d-%05d", season, game_counter)
      date <- min(
        as.Date(sprintf("%d-01-15", season)) + round(stats::runif(1, 0, 300)),
        Sys.Date()
      )
      length_seconds <- max(1200, stats::rnorm(1, 1920, 260))

      for (side_index in 1:2) {
        side <- c("Blue", "Red")[side_index]
        squad <- assignment[assignment$team == pair[side_index], , drop = FALSE]
        team_kills <- max(1, stats::rpois(1, 13))
        result <- as.integer(side_index == 1) # arbitraire, non utilisé par les modèles

        for (member_index in seq_len(nrow(squad))) {
          member <- squad[member_index, ]
          age <- as.numeric(difftime(date, member$birthdate, units = "days")) / 365.25
          aging <- -0.045 * (age - peak_age[[member$role]])^2
          quality <- member$skill + LEAGUE_EFFECT[[league]] + aging + stats::rnorm(1, 0, 0.75)

          rows[[length(rows) + 1]] <- data.frame(
            gameid = gameid, date = date, league = league, split = "Regular",
            side = side, position = member$role, playername = member$playername,
            teamname = member$team, result = result,
            gamelength = length_seconds,
            kills = stats::rpois(1, max(0.4, 2.6 + quality)),
            deaths = stats::rpois(1, max(0.4, 2.8 - 0.7 * quality)),
            assists = stats::rpois(1, max(0.5, 5.5 + 0.8 * quality)),
            teamkills = team_kills,
            golddiffat15 = stats::rnorm(1, 420 * quality, 620),
            xpdiffat15 = stats::rnorm(1, 330 * quality, 540),
            csdiffat15 = stats::rnorm(1, 7 * quality, 11),
            damageshare = min(0.55, max(0.02, stats::rnorm(1, 0.2 + 0.025 * quality, 0.045))),
            earnedgoldshare = min(0.55, max(0.02, stats::rnorm(1, 0.2, 0.035))),
            vspm = max(0.2, stats::rnorm(1, 2.1 + 0.15 * quality, 0.55)),
            birthdate = member$birthdate,
            stringsAsFactors = FALSE
          )
        }
      }
    }
  }
}

games <- do.call(rbind, rows)
games$role <- games$position
games$season <- whisker_season_of(games$date)
games$league_id <- games$league
games$is_international <- FALSE
games$team_kills <- games$teamkills
games$age <- whisker_age_at(games$birthdate, games$date)
games$contract_end <- as.Date(ifelse(
  stats::runif(nrow(games)) < 0.45,
  as.Date("2026-11-16") + sample(c(0, 365), nrow(games), replace = TRUE),
  NA
), origin = "1970-01-01")

games$vspm <- games$vspm
# Le jeu de développement doit imiter la source active, pas une source plus riche : sinon
# il répéterait une chaîne que le vrai pipeline ne parcourt pas. Si la configuration désigne
# Leaguepedia, les différentiels de lane disparaissent ici aussi.
if (identical(whisker_config("leagues", paths)$performance_source, "leaguepedia")) {
  games$golddiffat15 <- NA_real_
  games$xpdiffat15 <- NA_real_
  games$csdiffat15 <- NA_real_
  whisker_log("fixtures", "différentiels de lane retirés : la source active ne les porte pas")
}

arrow::write_parquet(games, file.path(paths$interim, "player_games.parquet"))
whisker_log("fixtures", "%d lignes joueur-game, %d joueurs, %d saisons",
            nrow(games), length(unique(games$playername)), length(unique(games$season)))

# ── Les vraies étapes, sur des données synthétiques ─────────────────────────────────────
whisker_step_04_model_league(paths)
whisker_step_05_model_player(paths)
whisker_step_06_model_aging(paths)
whisker_step_07_salary(paths)
whisker_step_08_export(paths, synthetic = TRUE)

whisker_log("fixtures", "jeu de développement écrit — meta.synthetic = true")
