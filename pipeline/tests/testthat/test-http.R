# Construction des requêtes Cargo. La partie réseau se vérifie dans tests/live/ ; ici on
# teste ce qui peut l'être hors ligne — et notamment le tri, dont l'absence produisait des
# doublons de pagination observés sur la source réelle.

whisker_source_lib()

test_that("le champ de tri par défaut est le premier champ, sous sa forme qualifiée", {
  # Cargo trie sur le nom de colonne source, pas sur l'alias.
  expect_identical(
    whisker_first_field("Players.ID=id, Players.Birthdate=birthdate"),
    "Players.ID"
  )
  expect_identical(whisker_first_field("Players.ID"), "Players.ID")
  expect_identical(
    whisker_first_field("  Contracts.Player = id , Contracts.Team=team"),
    "Contracts.Player"
  )
})

test_that("l'en-tête User-Agent identifie le projet", {
  # Fandom pose l'identification comme condition d'accès : une requête anonyme est un abus.
  expect_match(WHISKER_USER_AGENT, "WHISKER")
  expect_match(WHISKER_USER_AGENT, "httr2")
})

test_that("le chemin de cache est déterministe et propre à l'URL", {
  paths <- whisker_paths()
  a <- whisker_cache_path("https://exemple.test/a", "json", paths)
  b <- whisker_cache_path("https://exemple.test/b", "json", paths)
  expect_identical(a, whisker_cache_path("https://exemple.test/a", "json", paths))
  expect_false(identical(a, b))
  expect_match(basename(a), "^[0-9a-f]{16}[.]json$")
})
