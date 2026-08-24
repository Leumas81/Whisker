# Reprise d'un tirage partiel. Ces tests existent parce qu'une seule page refusée faisait
# tomber tout le travail : la source ne laisse passer qu'environ une requête sur quatre, et
# elle finit toujours par en refuser une jusqu'au bout.

whisker_source_lib()

#' Substitue temporairement `whisker_download` par une réponse fixée.
#'
#' Le projet n'est pas un paquet, donc `local_mocked_bindings` ne s'applique pas. On remplace
#' la fonction dans l'environnement global et on la restaure à la sortie du bloc appelant :
#' aucune requête réseau, et la fonction testée reste bien celle qui décide quoi faire.
avec_reponse <- function(json, code) {
  original <- get("whisker_download", envir = globalenv())
  assign(
    "whisker_download",
    function(url, destination, ...) {
      writeLines(json, destination)
      destination
    },
    envir = globalenv()
  )
  on.exit(assign("whisker_download", original, envir = globalenv()), add = TRUE)
  force(code)
}

LIMITE <- '{"error":{"code":"ratelimited","info":"limite"}}'
REQUETE_INVALIDE <- '{"error":{"code":"invalidquery","info":"champ inconnu"}}'

test_that("le compteur de pages abandonnées démarre et se remet à zéro", {
  whisker_reset_skipped()
  expect_identical(whisker_skipped_count(), 0L)
})

test_that("une page refusée est comptée plutôt que fatale, quand on le demande", {
  whisker_reset_skipped()
  whisker_set_deadline(NULL)
  cache <- tempfile(fileext = ".json")

  resultat <- avec_reponse(LIMITE, {
    whisker_cargo_fetch("https://exemple.test/a", cache, pause = 0,
                        paths = whisker_paths(), max_attempts = 2L,
                        max_wait = 0, on_rate_limit = "skip")
  })

  expect_null(resultat)
  expect_identical(whisker_skipped_count(), 1L)
})

test_that("sans autorisation de sauter, la même situation s'arrête", {
  whisker_reset_skipped()
  whisker_set_deadline(NULL)
  cache <- tempfile(fileext = ".json")

  expect_error(
    avec_reponse(LIMITE, {
      whisker_cargo_fetch("https://exemple.test/b", cache, pause = 0,
                          paths = whisker_paths(), max_attempts = 2L, max_wait = 0)
    }),
    "limitation de débit persistante"
  )
  expect_identical(whisker_skipped_count(), 0L)
})

test_that("une erreur d'API qui n'est pas une limitation reste fatale, même en mode « skip »", {
  # Un champ inexistant ou une table renommée doivent se voir tout de suite : les sauter
  # produirait un jeu silencieusement amputé.
  whisker_reset_skipped()
  whisker_set_deadline(NULL)
  cache <- tempfile(fileext = ".json")

  expect_error(
    avec_reponse(REQUETE_INVALIDE, {
      whisker_cargo_fetch("https://exemple.test/c", cache, pause = 0,
                          paths = whisker_paths(), max_attempts = 3L,
                          max_wait = 0, on_rate_limit = "skip")
    }),
    "invalidquery"
  )
  expect_identical(whisker_skipped_count(), 0L)
})

test_that("le budget de temps prime sur la tolérance aux pages refusées", {
  # Sauter des pages ne doit pas permettre de dépasser le budget : c'est la borne qui a
  # manqué la première fois, et elle doit rester la plus forte.
  whisker_reset_skipped()
  whisker_set_deadline(-1)
  cache <- tempfile(fileext = ".json")

  expect_error(
    avec_reponse(LIMITE, {
      whisker_cargo_fetch("https://exemple.test/d", cache, pause = 0,
                          paths = whisker_paths(), max_attempts = 5L,
                          max_wait = 0, on_rate_limit = "skip")
    }),
    "Budget de temps épuisé"
  )
  whisker_set_deadline(NULL)
})
