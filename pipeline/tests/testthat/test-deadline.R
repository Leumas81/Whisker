# Le budget de temps des requêtes. Ce test existe parce qu'une exécution de CI a brûlé cinq
# heures et demie sans rien produire : la patience par requête se multipliait par le nombre
# de pages, et rien ne bornait l'ensemble. Une limite atteinte doit se solder par un message.

whisker_source_lib()

test_that("aucun budget ouvert laisse passer sans contrainte", {
  whisker_set_deadline(NULL)
  expect_true(is.na(whisker_deadline_left()))
  expect_silent(whisker_check_deadline())
})

test_that("un budget ouvert décompte le temps restant", {
  whisker_set_deadline(10)
  reste <- whisker_deadline_left()
  expect_gt(reste, 9)
  expect_lte(reste, 10)
  expect_silent(whisker_check_deadline())
})

test_that("un budget épuisé s'arrête en disant quoi faire", {
  whisker_set_deadline(-1)
  expect_error(whisker_check_deadline("tirage"), "Budget de temps épuisé")
  expect_error(whisker_check_deadline("tirage"), "tirage")
  # Le message doit dire que rien n'est perdu : le cache permet de reprendre.
  expect_error(whisker_check_deadline(), "cache")
})

test_that("la patience par requête reste compatible avec le budget global", {
  # Huit tentatives plafonnées à soixante secondes font au pire une dizaine de minutes par
  # page. Au-delà, une seule page pourrait consommer tout le budget et masquer le problème.
  pire_cas <- sum(pmin(2^(1:WHISKER_BULK_ATTEMPTS), WHISKER_BULK_WAIT)) / 60
  expect_lt(pire_cas, WHISKER_FETCH_BUDGET / 3)
})

test_that("le budget se referme entre deux tirages", {
  whisker_set_deadline(5)
  expect_false(is.na(whisker_deadline_left()))
  whisker_set_deadline(NULL)
  expect_true(is.na(whisker_deadline_left()))
})
