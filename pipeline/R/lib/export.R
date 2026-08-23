# Écriture et validation des JSON — la moitié R du contrat de données.
#
# Le §3.3 veut que les schémas soient la source unique de vérité des deux côtés du projet.
# Côté web, ajv valide et les types TypeScript sont générés. Côté R, ajv valide la structure,
# et l'ordre `lower <= point <= upper` est vérifié par un parcours générique piloté par
# l'annotation `orderedProperties` du schéma — la même que celle qu'ajv lit côté web.

#' Arrondit une estimation, en préservant l'ordre de ses bornes.
#'
#' Arrondir indépendamment peut inverser deux valeurs très proches et faire échouer la
#' validation. On arrondit puis on réordonne.
whisker_round_estimate <- function(estimate, digits = 3, label = "") {
  raw <- c(estimate$lower, estimate$point, estimate$upper)
  if (length(raw) != 3 || !all(is.finite(raw))) {
    stop(
      sprintf(
        "Estimation non finie%s : lower=%s point=%s upper=%s.
  Une valeur manquante ne doit jamais atteindre l'export.",
        if (nzchar(label)) paste0(" (", label, ")") else "",
        format(estimate$lower), format(estimate$point), format(estimate$upper)
      ),
      call. = FALSE
    )
  }
  values <- sort(c(
    round(estimate$lower, digits),
    round(estimate$point, digits),
    round(estimate$upper, digits)
  ))
  list(point = values[2], lower = values[1], upper = values[3])
}

whisker_round_band <- function(band, digits = 0) {
  values <- sort(c(round(band$lower, digits), round(band$upper, digits)))
  list(lower = values[1], upper = values[2])
}

#' Hash git complet du dépôt.
whisker_git_commit <- function(paths = whisker_paths()) {
  result <- tryCatch(
    system2("git", c("-C", shQuote(paths$root), "rev-parse", "HEAD"),
            stdout = TRUE, stderr = FALSE),
    error = function(condition) character()
  )
  commit <- if (length(result) > 0) trimws(result[1]) else ""
  if (!grepl("^[0-9a-f]{40}$", commit)) {
    stop(
      paste0(
        "Hash git introuvable. meta.json doit porter le commit qui a produit les données :\n",
        "  sans lui, aucune estimation affichée n'est traçable (§0.2)."
      ),
      call. = FALSE
    )
  }
  commit
}

#' Ensembles de clés portant une contrainte d'ordre, découverts dans les schémas.
whisker_ordered_shapes <- function(paths = whisker_paths()) {
  shapes <- list()
  collect <- function(node) {
    if (is.list(node)) {
      if (!is.null(node$orderedProperties) && !is.null(node$properties)) {
        shapes[[length(shapes) + 1]] <<- list(
          keys = sort(names(node$properties)),
          order = unlist(node$orderedProperties)
        )
      }
      for (child in node) collect(child)
    }
    invisible(NULL)
  }
  for (file in list.files(paths$schemas, pattern = "\\.schema\\.json$", full.names = TRUE)) {
    collect(jsonlite::fromJSON(file, simplifyVector = FALSE))
  }
  unique(shapes)
}

#' Vérifie l'ordre de toutes les estimations d'un objet, quelle que soit sa profondeur.
#'
#' Ne connaît aucune règle en propre : elle applique celles que le schéma déclare.
whisker_assert_ordered <- function(data, shapes, trail = "") {
  violations <- character()

  walk <- function(node, path) {
    if (!is.list(node)) return(invisible(NULL))

    if (!is.null(names(node))) {
      keys <- sort(names(node))
      for (shape in shapes) {
        if (identical(keys, shape$keys)) {
          values <- unlist(node[shape$order])
          if (is.numeric(values) && (anyNA(values) || is.unsorted(values))) {
            violations <<- c(violations, sprintf(
              "%s : %s doit être croissant, obtenu %s",
              path, paste(shape$order, collapse = " <= "),
              paste(signif(values, 6), collapse = ", ")
            ))
          }
        }
      }
    }

    for (index in seq_along(node)) {
      label <- if (!is.null(names(node)) && nzchar(names(node)[index])) {
        paste0(path, "/", names(node)[index])
      } else {
        sprintf("%s[%d]", path, index)
      }
      walk(node[[index]], label)
    }
    invisible(NULL)
  }

  walk(data, trail)
  violations
}

#' Écrit un JSON et le valide contre son schéma.
#'
#' Échoue avant d'écrire si la validation ne passe pas : un fichier invalide ne doit jamais
#' exister sur le disque, il finirait par être commité.
whisker_write_validated <- function(data, schema_file, destination, paths = whisker_paths()) {
  json <- jsonlite::toJSON(data, auto_unbox = TRUE, null = "null", na = "null", digits = NA)

  violations <- whisker_assert_ordered(data, whisker_ordered_shapes(paths), basename(destination))
  if (length(violations) > 0) {
    stop(
      sprintf("%s : %d estimation(s) aux bornes désordonnées.\n  %s",
              basename(destination), length(violations),
              paste(utils::head(violations, 5), collapse = "\n  ")),
      call. = FALSE
    )
  }

  schema <- file.path(paths$schemas, schema_file)
  validator <- jsonvalidate::json_validator(schema, engine = "ajv")
  result <- validator(json, verbose = TRUE)
  if (!result) {
    errors <- attr(result, "errors")
    stop(
      sprintf(
        "%s ne respecte pas %s :\n%s",
        basename(destination), schema_file,
        paste(utils::capture.output(print(utils::head(errors, 10))), collapse = "\n")
      ),
      call. = FALSE
    )
  }

  dir.create(dirname(destination), recursive = TRUE, showWarnings = FALSE)
  writeLines(jsonlite::prettify(json, indent = 2), destination, useBytes = TRUE)
  whisker_log("08_export", "%s : %.0f Ko", basename(destination), file.size(destination) / 1024)
  invisible(destination)
}
