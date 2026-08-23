# La calibration salariale porte sur des personnes identifiables. Ces tests vérifient
# qu'elle restitue bien ses ancres, qu'elle tronque quand il le faut, et surtout qu'elle
# refuse de produire une distribution quand les sources n'en portent pas.

whisker_source_lib()

test_that("la log-normale simple restitue ses deux moments", {
  params <- whisker_lognormal_from_moments(median_value = 165000, mean_value = 240000)
  expect_equal(exp(params$mu), 165000, tolerance = 1e-6)
  expect_equal(exp(params$mu + params$sigma^2 / 2), 240000, tolerance = 1e-6)
  expect_equal(params$sigma, 0.8657, tolerance = 1e-3)
})

test_that("une moyenne inférieure à la médiane est refusée", {
  expect_error(
    whisker_lognormal_from_moments(median_value = 240000, mean_value = 165000),
    "strictement supérieure"
  )
})

test_that("les ancres LEC réelles violent le seuil du brief, ce qui impose la troncature", {
  params <- whisker_lognormal_from_moments(165000, 240000)
  masse <- whisker_mass_below(params, 60000)
  expect_gt(masse, 0.05)
  expect_equal(masse, 0.121, tolerance = 5e-3)
})

test_that("la ré-identification tronquée restitue exactement moyenne et médiane", {
  params <- whisker_lognormal_truncated(165000, 240000, 60000)
  moments <- whisker_truncated_moments(params$mu, params$sigma, 60000)
  expect_equal(moments$mean, 240000, tolerance = 1)
  expect_equal(moments$median, 165000, tolerance = 1)
  expect_true(params$truncated)
  expect_equal(params$floor, 60000)
})

test_that("aucun quantile de la loi tronquée ne descend sous le plancher", {
  params <- whisker_lognormal_truncated(165000, 240000, 60000)
  for (p in seq(0, 0.99, by = 0.01)) {
    expect_gte(whisker_quantile(params, p), 60000 - 1e-6)
  }
})

test_that("les quintiles couvrent la distribution sans se chevaucher", {
  params <- whisker_lognormal_truncated(165000, 240000, 60000)
  bands <- whisker_quintile_bands(params)
  expect_length(bands, 5)
  for (band in bands) expect_lt(band$lower, band$upper)
  for (index in 1:4) {
    expect_equal(bands[[index]]$upper, bands[[index + 1]]$lower, tolerance = 1e-6)
  }
  expect_gte(bands[[1]]$lower, 60000 - 1e-6)
  expect_true(is.finite(bands[[5]]$upper))
  expect_gt(bands[[5]]$upper, bands[[5]]$lower)
})

test_that("la LEC est calibrée à partir de ses ancres sourcées", {
  config <- whisker_config("salary_anchors")
  params <- whisker_calibrate_league("LEC", 2025L, config)
  expect_false(is.null(params))
  expect_true(params$truncated)
  expect_equal(params$basis, "observed")
  moments <- whisker_truncated_moments(params$mu, params$sigma, params$floor)
  expect_equal(moments$mean, 240000, tolerance = 1)
  expect_equal(moments$median, 165000, tolerance = 1)
})

test_that("la LFL ne produit aucune distribution, faute de sources suffisantes", {
  config <- whisker_config("salary_anchors")
  expect_null(whisker_calibrate_league("LFL", 2025L, config))
})

test_that("une ligue déclarée publiable sans deux moments est refusée", {
  config <- whisker_config("salary_anchors")
  config$distributions[[2]]$publish <- TRUE
  expect_error(whisker_calibrate_league("LFL", 2025L, config), "moyenne et une médiane")
})

test_that("une ligue sans règle de publication est signalée, pas ignorée", {
  config <- whisker_config("salary_anchors")
  expect_error(whisker_calibrate_league("LCK", 2025L, config), "Aucune règle de publication")
})

test_that("chaque ancre porte sa source, son URL et ses deux dates", {
  for (anchor in whisker_config("salary_anchors")$anchors) {
    expect_true(nzchar(anchor$source), info = anchor$id)
    expect_true(nzchar(anchor$url), info = anchor$id)
    expect_true(nzchar(anchor$method), info = anchor$id)
    expect_match(anchor$retrieved_at, "^\\d{4}-\\d{2}-\\d{2}$", info = anchor$id)
    expect_match(anchor$published_at, "^\\d{4}-\\d{2}-\\d{2}$", info = anchor$id)
  }
})

test_that("aucune ancre ne pointe vers une URL factice", {
  # Le garde-fou qui empêche de remettre en ligne les valeurs de départ du brief.
  for (anchor in whisker_config("salary_anchors")$anchors) {
    expect_false(grepl("example\\.(invalid|com)", anchor$url), info = anchor$id)
    expect_match(anchor$url, "^https://", info = anchor$id)
  }
})

test_that("la calibration reste plausible au regard des moyennes par poste publiées", {
  # Contrôle indépendant : les moyennes par poste ne servent pas à calibrer, elles servent
  # à vérifier que la loi obtenue les contient dans un ordre de grandeur crédible.
  config <- whisker_config("salary_anchors")
  params <- whisker_calibrate_league("LEC", 2025L, config)
  valeurs <- unlist(config$role_means_check$values)

  expect_gte(min(valeurs), whisker_quantile(params, 0.05))
  expect_lte(max(valeurs), whisker_quantile(params, 0.95))
  expect_gt(config$role_means_check$rookie_mean, 60000)
})
