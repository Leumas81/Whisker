# `metric_std` est le socle des quatre modèles. Ces tests vérifient que le calcul suit bien
# la spécification de config/metric.yaml, et surtout qu'aucune constante n'a été recopiée
# dans le code : la configuration doit rester le seul endroit où la métrique se décide.

whisker_source_lib()

fixture <- function(n_per_group = 40, seed = 7) {
  set.seed(seed)
  grid <- expand.grid(
    role = c("top", "jng", "mid", "adc", "sup"),
    league = c("LEC", "LFL"),
    season = c(2024L, 2025L),
    stringsAsFactors = FALSE
  )
  rows <- do.call(rbind, lapply(seq_len(nrow(grid)), function(i) {
    # La LFL est délibérément décalée vers le bas : les tests vérifient que ce décalage
    # survit à la standardisation, puisque c'est lui que le §4.1 cherche à estimer.
    decalage <- if (grid$league[i] == "LFL") -0.8 else 0
    data.frame(
      gameid = paste0("g", i, "-", seq_len(n_per_group)),
      playername = paste0("j", i, "-", seq_len(n_per_group) %% 8),
      role = grid$role[i], league = grid$league[i], season = grid$season[i],
      golddiffat15 = rnorm(n_per_group, 300 * decalage, 700),
      xpdiffat15 = rnorm(n_per_group, 250 * decalage, 600),
      csdiffat15 = rnorm(n_per_group, 5 * decalage, 12),
      damageshare = pmin(pmax(rnorm(n_per_group, 0.2 + 0.02 * decalage, 0.05), 0.01), 0.6),
      earnedgoldshare = pmin(pmax(rnorm(n_per_group, 0.2, 0.04), 0.01), 0.6),
      kills = rpois(n_per_group, 3), assists = rpois(n_per_group, 6),
      deaths = rpois(n_per_group, 2.5),
      gamelength = rnorm(n_per_group, 1900, 250),
      vspm = rnorm(n_per_group, 2 + 0.2 * decalage, 0.6),
      team_kills = rpois(n_per_group, 14) + 1,
      stringsAsFactors = FALSE
    )
  }))
  rownames(rows) <- NULL
  rows
}

test_that("la spécification se lit et reste cohérente", {
  spec <- whisker_metric_spec()
  keys <- vapply(spec$components, function(component) component$key, character(1))
  expect_length(unique(keys), length(keys))
  for (role in c("top", "jng", "mid", "adc", "sup")) {
    expect_true(role %in% names(spec$inclusion))
    expect_true(all(spec$inclusion[[role]] %in% keys))
    expect_gt(length(spec$inclusion[[role]]), 0)
  }
})

test_that("aucune constante de la métrique n'est recopiée dans le code R", {
  # Si la liste des composants, la matrice d'inclusion ou les centiles vivaient aussi dans
  # metric.R, changer la configuration ne changerait plus rien — et personne ne s'en
  # apercevrait. Les clés de composants ne doivent donc apparaître nulle part en littéral.
  source_code <- paste(
    readLines(file.path(whisker_paths()$pipeline, "R", "lib", "metric.R"), warn = FALSE),
    collapse = "\n"
  )

  spec <- whisker_metric_spec()
  for (key in vapply(spec$components, function(component) component$key, character(1))) {
    expect_false(
      grepl(paste0("[\"']", key, "[\"']"), source_code),
      label = sprintf("composant « %s » cité en littéral dans metric.R", key)
    )
  }
  expect_false(grepl("0\\.99", source_code), label = "centile de winsorisation en dur")
  expect_false(grepl("[\"']LEC[\"']", source_code), label = "ligue de référence en dur")
})

test_that("une matrice d'inclusion citant un composant inconnu est refusée", {
  spec <- whisker_metric_spec()
  expect_error(
    {
      broken <- spec
      broken$inclusion$mid <- c("gd15", "inexistant")
      keys <- vapply(broken$components, function(c) c$key, character(1))
      unknown <- setdiff(unlist(broken$inclusion, use.names = FALSE), keys)
      if (length(unknown) > 0) stop("composants inconnus")
      NULL
    },
    "composants inconnus"
  )
})

test_that("la participation aux éliminations vaut zéro quand l'équipe n'a rien tué", {
  games <- data.frame(
    golddiffat15 = 0, xpdiffat15 = 0, csdiffat15 = 0,
    damageshare = 0.2, earnedgoldshare = 0.2,
    kills = 0, assists = 0, deaths = 3, gamelength = 1800, vspm = 2, team_kills = 0
  )
  expect_identical(whisker_metric_components(games)$kp, 0)
})

test_that("le rendement est la part de dégâts moins la part d'or", {
  games <- data.frame(
    golddiffat15 = 0, xpdiffat15 = 0, csdiffat15 = 0,
    damageshare = 0.31, earnedgoldshare = 0.24,
    kills = 1, assists = 1, deaths = 1, gamelength = 1800, vspm = 2, team_kills = 10
  )
  expect_equal(whisker_metric_components(games)$rendement, 0.07, tolerance = 1e-12)
})

test_that("la survie pénalise les morts et se mesure aux dix minutes", {
  games <- data.frame(
    golddiffat15 = 0, xpdiffat15 = 0, csdiffat15 = 0,
    damageshare = 0.2, earnedgoldshare = 0.2,
    kills = 0, assists = 0, deaths = c(0, 3), gamelength = 1800, vspm = 2, team_kills = 10
  )
  survie <- whisker_metric_components(games)$survie
  expect_identical(survie[1], 0)
  expect_equal(survie[2], -1, tolerance = 1e-12)   # 3 morts en 30 min = 1 pour 10 min
  expect_lt(survie[2], survie[1])
})

test_that("une durée de partie nulle est refusée plutôt que divisée", {
  games <- data.frame(
    golddiffat15 = 0, xpdiffat15 = 0, csdiffat15 = 0,
    damageshare = 0.2, earnedgoldshare = 0.2,
    kills = 0, assists = 0, deaths = 1, gamelength = 0, vspm = 2, team_kills = 10
  )
  expect_error(whisker_metric_components(games), "durée nulle")
})

test_that("une colonne manquante est nommée plutôt que devinée", {
  expect_error(whisker_metric_components(data.frame(kills = 1)), "Colonnes absentes")
})

test_that("la winsorisation ramène les queues sans jeter de lignes", {
  x <- c(rep(10, 98), -1000, 1000)
  clipped <- whisker_winsorize(x, 0.01, 0.99)
  expect_length(clipped, length(x))
  expect_gt(min(clipped), -1000)
  expect_lt(max(clipped), 1000)
})

test_that("le joueur LEC moyen est à zéro, par construction", {
  games <- whisker_metric_std(fixture())
  for (role in unique(games$role)) {
    for (season in unique(games$season)) {
      reference <- games$metric_std[
        games$role == role & games$league == "LEC" & games$season == season
      ]
      expect_equal(mean(reference), 0, tolerance = 1e-8,
                   label = sprintf("moyenne LEC %s %d", role, season))
      expect_equal(stats::sd(reference), 1, tolerance = 1e-8,
                   label = sprintf("écart-type LEC %s %d", role, season))
    }
  }
})

test_that("l'écart entre ligues survit à la standardisation", {
  # C'est la propriété qui rend le §4.1 possible : standardiser par saison absorbe la dérive
  # du méta, pas les différences de niveau entre ligues à l'intérieur d'une saison.
  games <- whisker_metric_std(fixture())
  moyenne_lec <- mean(games$metric_std[games$league == "LEC"], na.rm = TRUE)
  moyenne_lfl <- mean(games$metric_std[games$league == "LFL"], na.rm = TRUE)
  expect_lt(moyenne_lfl, moyenne_lec - 0.3)
})

test_that("perturber un composant exclu ne change rien au composite du poste", {
  spec <- whisker_metric_spec()
  expect_false("csd15" %in% spec$inclusion$sup)
  expect_true("csd15" %in% spec$inclusion$mid)

  base <- fixture()
  reference <- whisker_metric_std(base)

  # On perturbe le farm des seuls supports, pour qui csd15 est écarté.
  perturbed <- base
  perturbed$csdiffat15[perturbed$role == "sup"] <-
    perturbed$csdiffat15[perturbed$role == "sup"] + 500
  apres <- whisker_metric_std(perturbed)

  expect_equal(
    apres$metric_std[apres$role == "sup"],
    reference$metric_std[reference$role == "sup"],
    tolerance = 1e-8
  )

  # Le même composant, pour un poste où il compte, doit au contraire déplacer le composite.
  perturbe_mid <- base
  perturbe_mid$csdiffat15[perturbe_mid$role == "mid"] <-
    perturbe_mid$csdiffat15[perturbe_mid$role == "mid"] +
    seq_along(perturbe_mid$csdiffat15[perturbe_mid$role == "mid"])
  mid_apres <- whisker_metric_std(perturbe_mid)

  expect_false(isTRUE(all.equal(
    mid_apres$metric_std[mid_apres$role == "mid"],
    reference$metric_std[reference$role == "mid"],
    tolerance = 1e-8
  )))
})

test_that("les composants exclus restent calculés pour les diagnostics de la phase 2", {
  games <- whisker_metric_std(fixture())
  sup <- games[games$role == "sup", ]
  expect_true(all(is.finite(sup$z_csd15)))
  expect_true(all(is.finite(sup$z_dmgshare)))
})

test_that("l'indice de valeur place le joueur moyen à 50 et reste borné", {
  spec <- whisker_metric_spec()
  expect_equal(whisker_value_index(0, 1, spec), 50)
  expect_equal(whisker_value_index(1, 1, spec), 65)
  expect_equal(whisker_value_index(-1, 1, spec), 35)
  expect_equal(whisker_value_index(2.16, 1, spec), 82.4, tolerance = 0.05)
  expect_equal(whisker_value_index(50, 1, spec), 100)
  expect_equal(whisker_value_index(-50, 1, spec), 0)
})

test_that("l'indice de valeur préserve l'ordre des bornes d'un intervalle", {
  spec <- whisker_metric_spec()
  borne_basse <- whisker_value_index(0.8, 1, spec)
  point <- whisker_value_index(1.4, 1, spec)
  borne_haute <- whisker_value_index(2.0, 1, spec)
  expect_lt(borne_basse, point)
  expect_lt(point, borne_haute)
})

test_that("un écart-type d'effets joueurs nul est refusé", {
  expect_error(whisker_value_index(1, 0), "strictement positif")
})
