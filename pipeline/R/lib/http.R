# Accès réseau : cache sur disque et politesse.
#
# Deux sources gratuites soutiennent ce projet. Les marteler serait à la fois grossier et le
# meilleur moyen de se faire couper l'accès. Tout passe donc par un cache, et l'API Cargo
# respecte une pause entre deux requêtes.

WHISKER_USER_AGENT <- paste0(
  "WHISKER/0.1 (projet statistique open source ; contact via le dépôt) ",
  "httr2/", as.character(utils::packageVersion("httr2"))
)

#' Chemin de cache d'une requête, dérivé de son URL.
whisker_cache_path <- function(url, extension, paths = whisker_paths()) {
  file.path(paths$raw, paste0(substr(digest::digest(url, algo = "sha1"), 1, 16), ".", extension))
}

#' Télécharge une URL, ou rend le fichier déjà en cache.
#'
#' `max_age_days` fixe la fraîcheur acceptable : le pipeline hebdomadaire retélécharge, une
#' exécution locale répétée ne retélécharge pas.
whisker_download <- function(url, destination, max_age_days = 6, paths = whisker_paths()) {
  if (file.exists(destination)) {
    age <- as.numeric(difftime(Sys.time(), file.mtime(destination), units = "days"))
    if (age <= max_age_days) {
      whisker_log("cache", "%s (%.1f j)", basename(destination), age)
      return(destination)
    }
  }

  whisker_log("download", "%s", url)
  request <- httr2::request(url)
  request <- httr2::req_user_agent(request, WHISKER_USER_AGENT)
  request <- httr2::req_retry(request, max_tries = 3, backoff = function(attempt) 2^attempt)
  request <- httr2::req_timeout(request, 300)

  response <- httr2::req_perform(request, path = destination)
  if (httr2::resp_status(response) >= 400) {
    unlink(destination)
    stop(sprintf("Téléchargement échoué (%d) : %s", httr2::resp_status(response), url), call. = FALSE)
  }
  destination
}

#' Récupère une page Cargo, en réessayant si l'API limite le débit.
#'
#' Fandom signale la limitation dans le corps de la réponse, avec un code HTTP 200 :
#' `req_retry` ne la voit donc pas. Sur une adresse partagée, elle est intermittente —
#' la même requête passe quelques secondes plus tard. On patiente donc, en doublant
#' l'attente, plutôt que d'abandonner une exécution de pipeline pour une seconde de trop.
whisker_cargo_fetch <- function(url, cache, pause, paths, max_attempts = 6L) {
  wait <- pause
  for (attempt in seq_len(max_attempts)) {
    if (!file.exists(cache)) {
      Sys.sleep(wait)
      whisker_download(url, cache, max_age_days = 6, paths = paths)
    }

    payload <- jsonlite::fromJSON(cache, simplifyVector = FALSE)
    if (is.null(payload$error)) return(payload)

    if (!identical(payload$error$code, "ratelimited")) {
      stop(
        sprintf("API Cargo : %s — %s", payload$error$code, payload$error$info),
        call. = FALSE
      )
    }

    # La réponse en cache porte une erreur : elle ne doit pas être resservie.
    unlink(cache)
    wait <- min(wait * 2, 60)
    whisker_log("02_contracts", "limitation de débit, nouvelle tentative dans %.0f s (%d/%d)",
                wait, attempt, max_attempts)
  }

  stop(
    paste0(
      "API Cargo : limitation de débit persistante après ", max_attempts, " tentatives.\n",
      "  L'adresse IP utilisée est probablement mutualisée. Le pipeline hebdomadaire\n",
      "  tourne depuis une adresse dédiée en CI, où cette limite ne s'applique pas."
    ),
    call. = FALSE
  )
}

#' Interroge l'API Cargo de Leaguepedia, en suivant la pagination.
#'
#' `limit` est plafonné à 500 par l'API. La pause d'une seconde entre deux requêtes n'est pas
#' négociable : c'est la condition d'accès posée par Fandom.
#'
#' `order_by` ne relève pas du confort. Sans tri explicite, l'API ne garantit aucun ordre
#' entre deux requêtes, et la pagination par `offset` rend alors des lignes en double d'une
#' page à l'autre tout en en omettant d'autres. Constaté sur la table Players : 590 lignes
#' rendues pour 587 identifiants distincts. Le tri par défaut porte sur le premier champ
#' demandé ; la déduplication finale reste en filet de sécurité.
whisker_cargo_query <- function(tables, fields, where = NULL, join_on = NULL,
                                order_by = NULL, limit = 500L, pause = 1.0,
                                max_pages = 200L, paths = whisker_paths()) {
  base <- "https://lol.fandom.com/api.php"
  collected <- list()
  offset <- 0L

  for (page in seq_len(max_pages)) {
    query <- list(
      action = "cargoquery", format = "json",
      tables = tables, fields = fields,
      limit = as.character(limit), offset = as.character(offset)
    )
    if (!is.null(where)) query$where <- where
    if (!is.null(join_on)) query$join_on <- join_on
    query$order_by <- if (is.null(order_by)) whisker_first_field(fields) else order_by

    url <- httr2::url_modify_query(base, !!!query)
    cache <- whisker_cache_path(url, "json", paths)

    payload <- whisker_cargo_fetch(url, cache, pause, paths)

    rows <- payload$cargoquery
    if (length(rows) == 0) break

    collected[[length(collected) + 1]] <- do.call(
      rbind,
      lapply(rows, function(row) as.data.frame(row$title, stringsAsFactors = FALSE))
    )
    if (length(rows) < limit) break
    offset <- offset + limit
  }

  if (length(collected) == 0) {
    return(data.frame())
  }
  result <- do.call(rbind, collected)
  result <- result[!duplicated(result), , drop = FALSE]
  rownames(result) <- NULL
  result
}

#' Premier champ d'une liste Cargo, sous sa forme qualifiée « Table.Champ ».
#'
#' Cargo veut le nom de colonne source pour trier, pas l'alias : « Players.ID », pas « id ».
whisker_first_field <- function(fields) {
  first <- trimws(strsplit(fields, ",", fixed = TRUE)[[1]][1])
  trimws(strsplit(first, "=", fixed = TRUE)[[1]][1])
}
