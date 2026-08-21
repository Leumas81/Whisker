# Ce que la phase 0 livre côté R, c'est une structure. C'est donc la structure qu'on teste :
# les chemins se résolvent, la configuration se lit, et elle reste cohérente avec les schémas
# JSON — qui sont la source unique de vérité des deux côtés du projet.

test_that("la racine du dépôt se retrouve depuis n'importe quel sous-dossier", {
  paths <- whisker_paths()
  expect_true(dir.exists(paths$schemas))
  expect_true(dir.exists(paths$config))
  expect_true(dir.exists(file.path(paths$pipeline, "R")))
})

test_that("les huit étapes du pipeline existent", {
  paths <- whisker_paths()
  steps <- c(
    "01_download", "02_contracts", "03_clean", "04_model_league",
    "05_model_player", "06_model_aging", "07_salary", "08_export"
  )
  for (step in steps) {
    expect_true(
      file.exists(file.path(paths$pipeline, "R", paste0(step, ".R"))),
      info = sprintf("étape manquante : %s", step)
    )
  }
})

test_that("une étape non implémentée s'arrête en nommant sa phase", {
  expect_error(whisker_not_implemented("04_model_league", "2"), "phase 2")
})

test_that("les trois fichiers de configuration se lisent", {
  for (name in c("leagues", "salary_anchors", "name_aliases")) {
    expect_type(whisker_config(name), "list")
  }
})

test_that("une configuration absente s'arrête clairement", {
  expect_error(whisker_config("inexistante"), "Configuration absente")
})

test_that("les ligues de la configuration correspondent à l'énumération du schéma", {
  paths <- whisker_paths()
  common <- jsonlite::fromJSON(
    file.path(paths$schemas, "common.schema.json"),
    simplifyVector = TRUE
  )
  from_schema <- sort(common$`$defs`$LeagueId$enum)
  from_config <- sort(vapply(whisker_config("leagues")$leagues, function(x) x$id, character(1)))

  expect_identical(
    from_config, from_schema,
    info = "config/leagues.yaml et common.schema.json doivent lister exactement les mêmes ligues."
  )
})

test_that("les seuils de fiabilité correspondent au tableau du brief", {
  thresholds <- whisker_config("leagues")$reliability
  expect_identical(thresholds$high_min_games, 60L)
  expect_identical(thresholds$medium_min_games, 25L)
  expect_identical(thresholds$low_min_games, 10L)
})

test_that("chaque ancre salariale porte sa source et sa date", {
  anchors <- whisker_config("salary_anchors")$anchors
  expect_gt(length(anchors), 0)
  for (anchor in anchors) {
    expect_true(nzchar(anchor$source), info = anchor$id)
    expect_true(nzchar(anchor$url), info = anchor$id)
    expect_match(anchor$retrieved_at, "^\\d{4}-\\d{2}-\\d{2}$", info = anchor$id)
    expect_true(anchor$statistic %in% c("mean", "median", "floor"), info = anchor$id)
  }
})

test_that("les ancres LEC restent ordonnées : plancher < médiane < moyenne", {
  anchors <- whisker_config("salary_anchors")$anchors
  value_of <- function(statistic) {
    match <- Filter(function(a) a$league == "LEC" && a$statistic == statistic, anchors)
    if (length(match) == 0) return(NA_real_)
    as.numeric(match[[1]]$value)
  }
  expect_lt(value_of("floor"), value_of("median"))
  expect_lt(value_of("median"), value_of("mean"))
})

test_that("le taux de non-résolution toléré est celui du brief", {
  expect_identical(whisker_config("leagues")$max_unmatched_rate, 0.02)
})
