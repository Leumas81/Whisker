# Nettoyage et réconciliation des identités. Ces fonctions décident quelles lignes entrent
# dans les modèles ; une erreur ici se propage partout sans jamais lever d'exception.

whisker_source_lib()

test_that("un pseudo inconnu de la table d'alias traverse inchangé", {
  aliases <- list(list(canonical = "Vladi", aliases = c("Vladii", "Vlad1")))
  expect_identical(whisker_canonical(c("Caps", "Vladii"), aliases), c("Caps", "Vladi"))
})

test_that("la résolution d'alias ignore la casse", {
  aliases <- list(list(canonical = "Karmine Corp", aliases = c("KC", "kc blue")))
  expect_identical(
    whisker_canonical(c("kc", "KC BLUE", "Karmine Corp"), aliases),
    rep("Karmine Corp", 3)
  )
})

test_that("une table d'alias vide ne casse rien", {
  expect_identical(whisker_canonical(c("Caps", "Vladi"), list()), c("Caps", "Vladi"))
})

test_that("le poste « bot » d'Oracle's Elixir devient « adc »", {
  mapping <- whisker_config("oracle_columns")$positions
  expect_identical(whisker_map_positions(c("bot", "sup", "jng"), mapping), c("adc", "sup", "jng"))
})

test_that("un poste inconnu devient NA plutôt que d'être deviné", {
  mapping <- whisker_config("oracle_columns")$positions
  expect_true(is.na(whisker_map_positions("coach", mapping)))
})

test_that("les éliminations d'équipe se reportent sur le bon côté", {
  players <- data.frame(
    gameid = c("g1", "g1", "g2"),
    side = c("Blue", "Red", "Blue"),
    stringsAsFactors = FALSE
  )
  teams <- data.frame(
    gameid = c("g1", "g1", "g2", "g2"),
    side = c("Blue", "Red", "Blue", "Red"),
    teamkills = c(14, 7, 21, 3),
    stringsAsFactors = FALSE
  )
  expect_identical(whisker_attach_team_kills(players, teams)$team_kills, c(14, 7, 21))
})

test_that("une partie sans ligne d'équipe laisse un NA, qui sera compté comme non résolu", {
  players <- data.frame(gameid = "g9", side = "Blue", stringsAsFactors = FALSE)
  teams <- data.frame(gameid = "g1", side = "Blue", teamkills = 10, stringsAsFactors = FALSE)
  expect_true(is.na(whisker_attach_team_kills(players, teams)$team_kills))
})

test_that("les seuils de fiabilité suivent le tableau du §3.4", {
  thresholds <- whisker_config("leagues")$reliability
  expect_identical(
    whisker_reliability(c(9, 10, 24, 25, 59, 60, 120), thresholds),
    c(NA, "low", "low", "medium", "medium", "high", "high")
  )
})

test_that("un joueur sous dix games n'obtient aucun niveau de fiabilité", {
  thresholds <- whisker_config("leagues")$reliability
  expect_true(all(is.na(whisker_reliability(0:9, thresholds))))
})

test_that("le taux de non-résolution compte les lignes, pas les colonnes", {
  data <- data.frame(age = c(1, NA, 3, NA), team_kills = c(5, 5, NA, NA))
  result <- whisker_unmatched(data, c("age", "team_kills"))
  expect_equal(result$rate, 0.75)
  expect_equal(nrow(result$rows), 3)
})

test_that("un jeu complet donne un taux nul", {
  data <- data.frame(age = c(20, 22), team_kills = c(10, 12))
  expect_equal(whisker_unmatched(data, c("age", "team_kills"))$rate, 0)
})

test_that("une colonne attendue mais absente est nommée", {
  expect_error(
    whisker_require_columns(data.frame(a = 1), c("a", "gameid"), "oracle_2025.csv"),
    "gameid"
  )
  expect_error(
    whisker_require_columns(data.frame(a = 1), c("a", "gameid"), "oracle_2025.csv"),
    "format de la source"
  )
})

test_that("les doublons gameid x playername sont écartés une seule fois", {
  data <- data.frame(
    gameid = c("g1", "g1", "g1", "g2"),
    playername = c("Caps", "Caps", "Vladi", "Caps"),
    stringsAsFactors = FALSE
  )
  expect_equal(nrow(whisker_drop_duplicate_rows(data)), 3)
})

test_that("la saison se déduit de la date de partie", {
  expect_identical(whisker_season_of(c("2025-01-18", "2024-11-02")), c(2025L, 2024L))
})

test_that("l'âge se calcule en années décimales à la date de la partie", {
  expect_equal(whisker_age_at("2004-08-22", "2026-08-22"), 22, tolerance = 0.01)
  expect_true(is.na(whisker_age_at(NA, "2026-08-22")))
})

test_that("les codes de ligue de la configuration couvrent les ligues du schéma", {
  config <- whisker_config("leagues")
  codes <- unlist(lapply(config$leagues, function(l) l$oracle_codes))
  expect_true(all(nzchar(codes)))
  expect_equal(length(codes), length(unique(codes)))
})

test_that("les codes d'événements internationaux ne recoupent pas ceux des ligues", {
  config <- whisker_config("leagues")
  ligues <- unlist(lapply(config$leagues, function(l) l$oracle_codes))
  evenements <- unlist(lapply(config$international_events, function(e) e$oracle_codes))
  expect_length(intersect(ligues, evenements), 0)
})

test_that("chaque saison depuis la première a une source de téléchargement", {
  config <- whisker_config("leagues")
  attendues <- seq(config$period$first_season, 2025)
  disponibles <- as.integer(names(config$oracle_downloads$files))
  expect_true(all(attendues %in% disponibles))
})
