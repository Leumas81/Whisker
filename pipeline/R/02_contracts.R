# Interrogation de l'API Cargo de Leaguepedia : joueurs, dates de naissance, contrats.
#
# Entrées  : config/leagues.yaml
# Sorties  : interim/players_meta.parquet, interim/contracts.parquet
# Phase    : 1 du brief.
#
# Politesse : en-tête User-Agent identifiant le projet, une seconde entre deux requêtes,
# réponses mises en cache. Voir R/lib/http.R.

whisker_step_02_contracts <- function(paths = whisker_paths()) {
  config <- whisker_config("leagues", paths)
  first_season <- config$period$first_season

  # ── Joueurs : identité, pays, date de naissance ──────────────────────────────────────
  players <- whisker_cargo_query(
    tables = "Players",
    fields = "Players.ID=id, Players.Player=player, Players.Birthdate=birthdate, Players.Country=country, Players.Role=role, Players.Team=team, Players.IsRetired=retired",
    where = "Players.IsPersonality=0",
    paths = paths
  )

  if (nrow(players) == 0) {
    stop("L'API Cargo n'a rendu aucun joueur. Vérifiez la disponibilité de lol.fandom.com.",
         call. = FALSE)
  }

  players$birthdate <- suppressWarnings(as.Date(players$birthdate))
  players <- players[!is.na(players$id) & nzchar(players$id), ]
  players <- players[!duplicated(players$id), ]

  # ── Contrats : fin de contrat connue ─────────────────────────────────────────────────
  contracts <- whisker_cargo_query(
    tables = "Contracts",
    fields = "Contracts.Player=id, Contracts.Team=team, Contracts.ContractEnd=contract_end",
    paths = paths
  )
  if (nrow(contracts) > 0) {
    contracts$contract_end <- suppressWarnings(as.Date(contracts$contract_end))
    contracts <- contracts[!is.na(contracts$id) & nzchar(contracts$id), ]
    # Un joueur peut avoir plusieurs contrats successifs : on garde la fin la plus tardive.
    contracts <- contracts[order(contracts$id, contracts$contract_end, decreasing = TRUE), ]
    contracts <- contracts[!duplicated(contracts$id), ]
  }

  # ── Tenures : appartenance à une équipe dans le temps ────────────────────────────────
  tenures <- whisker_cargo_query(
    tables = "Tenures",
    fields = "Tenures.Player=id, Tenures.Team=team, Tenures.Start=start_date, Tenures.End=end_date",
    paths = paths
  )
  if (nrow(tenures) > 0) {
    tenures$start_date <- suppressWarnings(as.Date(tenures$start_date))
    tenures$end_date <- suppressWarnings(as.Date(tenures$end_date))
    tenures <- tenures[is.na(tenures$start_date) |
                         as.integer(format(tenures$start_date, "%Y")) >= first_season - 1, ]
  }

  arrow::write_parquet(players, file.path(paths$interim, "players_meta.parquet"))
  arrow::write_parquet(contracts, file.path(paths$interim, "contracts.parquet"))
  arrow::write_parquet(tenures, file.path(paths$interim, "tenures.parquet"))

  whisker_log("02_contracts", "%d joueurs, %d contrats, %d tenures",
              nrow(players), nrow(contracts), nrow(tenures))
  invisible(list(players = players, contracts = contracts, tenures = tenures))
}
