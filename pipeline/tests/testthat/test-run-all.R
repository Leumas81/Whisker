# Le point d'entrée du pipeline. Ce test existe parce qu'un défaut y est passé : `run_all.R`
# sourçait les huit étapes mais aucune bibliothèque interne, si bien que la première étape
# échouait sur une fonction introuvable. Rien ne l'avait vu — le générateur de développement
# sourçait les bibliothèques lui-même, et les tests appelaient les fonctions directement.

whisker_source_lib()

test_that("le point d'entrée source les bibliothèques avant les étapes", {
  # C'est exactement le défaut qui est passé : les étapes étaient sourcées, les bibliothèques
  # non. On vérifie donc l'ordre dans le fichier, pas seulement que les fonctions existent
  # quelque part — un test qui sourcerait lui-même les bibliothèques ne verrait rien.
  source_code <- readLines(file.path(whisker_paths()$pipeline, "run_all.R"), warn = FALSE)

  appel_lib <- grep("whisker_source_lib\\(", source_code)
  boucle_etapes <- grep("for \\(step in STEPS\\)", source_code)

  expect_length(appel_lib, 1)
  expect_length(boucle_etapes, 1)
  expect_lt(
    appel_lib[1], boucle_etapes[1],
    label = "whisker_source_lib doit être appelé avant la boucle sur les étapes"
  )
})

test_that("chaque étape déclarée est appelable une fois le pipeline mis en place", {
  paths <- whisker_paths()
  bac <- new.env(parent = globalenv())

  steps <- c(
    "01_download", "02_contracts", "03_clean", "04_model_league",
    "05_model_player", "06_model_aging", "07_salary", "08_export"
  )
  for (step in steps) {
    source(file.path(paths$pipeline, "R", paste0(step, ".R")), local = bac)
    expect_true(
      is.function(get0(paste0("whisker_step_", step), envir = bac, inherits = FALSE)),
      info = sprintf("étape absente : %s", step)
    )
  }
})

test_that("toutes les fonctions de bibliothèque appelées par les étapes existent", {
  paths <- whisker_paths()

  # On rejoue la mise en place complète du point d'entrée — bibliothèques puis étapes — dans
  # un environnement neuf, puis on relève tous les appels `whisker_*` du code des étapes et
  # on vérifie que chacun est défini. Un oubli de fichier dans R/lib/ se verrait ici plutôt
  # qu'à la première exécution du pipeline.
  bac <- new.env(parent = globalenv())
  source(file.path(paths$pipeline, "R", "00_setup.R"), local = bac)

  lib_dir <- file.path(paths$pipeline, "R", "lib")
  for (file in sort(list.files(lib_dir, pattern = "\\.R$", full.names = TRUE))) {
    source(file, local = bac)
  }

  fichiers <- list.files(file.path(paths$pipeline, "R"), pattern = "^[0-9][0-9]_.*[.]R$",
                         full.names = TRUE)
  for (file in fichiers) source(file, local = bac)

  code <- paste(unlist(lapply(fichiers, readLines, warn = FALSE)), collapse = "\n")
  appels <- unique(gsub("[(]$", "", regmatches(code, gregexpr("whisker_[a-z_0-9]+[(]", code))[[1]]))
  expect_gt(length(appels), 20)

  manquantes <- Filter(function(nom) !is.function(get0(nom, envir = bac)), appels)
  expect_identical(
    manquantes, character(0),
    label = sprintf("fonctions appelées mais introuvables : %s", paste(manquantes, collapse = ", "))
  )
})

test_that("la liste des étapes du point d'entrée correspond aux fichiers présents", {
  paths <- whisker_paths()
  fichiers <- sort(sub("\\.R$", "", list.files(file.path(paths$pipeline, "R"), pattern = "^\\d\\d_")))
  source_code <- readLines(file.path(paths$pipeline, "run_all.R"), warn = FALSE)
  cites <- sort(unique(regmatches(
    paste(source_code, collapse = "\n"),
    gregexpr("\\d\\d_[a-z_]+", paste(source_code, collapse = "\n"))
  )[[1]]))

  expect_identical(cites, fichiers)
})
