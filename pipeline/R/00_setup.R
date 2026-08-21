# Fondations communes à toutes les étapes du pipeline.
#
# Ce fichier ne fait rien tout seul : il est sourcé par les autres. Il fixe les chemins,
# charge la configuration et fournit un journal lisible en CI, où l'on ne dispose que
# de la sortie texte pour comprendre ce qui s'est passé.

# Racine du dépôt. Le pipeline est lancé depuis la CI, depuis testthat et parfois à la main :
# plutôt que de deviner à partir du fichier courant — ce que `source()` et `Rscript` ne
# renseignent pas de la même façon — on remonte jusqu'au dossier qui contient schemas/.
whisker_root <- function(start = getwd()) {
  from_env <- Sys.getenv("WHISKER_ROOT", unset = "")
  if (nzchar(from_env)) return(normalizePath(from_env, mustWork = TRUE))

  current <- normalizePath(start, mustWork = FALSE)
  repeat {
    if (dir.exists(file.path(current, "schemas")) && dir.exists(file.path(current, "pipeline"))) {
      return(current)
    }
    parent <- dirname(current)
    if (identical(parent, current)) {
      stop(
        "Racine du dépôt introuvable : aucun dossier parent ne contient schemas/ et pipeline/.",
        call. = FALSE
      )
    }
    current <- parent
  }
}

whisker_paths <- function(root = whisker_root()) {
  pipeline <- file.path(root, "pipeline")
  list(
    root = root,
    pipeline = pipeline,
    config = file.path(pipeline, "config"),
    raw = file.path(pipeline, "raw"),
    interim = file.path(pipeline, "interim"),
    diagnostics = file.path(pipeline, "diagnostics"),
    schemas = file.path(root, "schemas"),
    data_out = file.path(root, "web", "src", "data")
  )
}

whisker_config <- function(name, paths = whisker_paths()) {
  file <- file.path(paths$config, paste0(name, ".yaml"))
  if (!file.exists(file)) {
    stop(sprintf("Configuration absente : %s", file), call. = FALSE)
  }
  yaml::read_yaml(file)
}

whisker_log <- function(step, message, ...) {
  cat(sprintf("[%s] %-14s %s\n", format(Sys.time(), "%H:%M:%S"), step, sprintf(message, ...)))
}

# Une étape non implémentée doit s'arrêter en nommant sa phase, jamais renvoyer un
# résultat vide qui se propagerait en silence jusqu'au site.
whisker_not_implemented <- function(step, phase) {
  stop(
    sprintf("%s n'est pas implémenté. Prévu en phase %s du brief.", step, phase),
    call. = FALSE
  )
}

whisker_ensure_dirs <- function(paths = whisker_paths()) {
  for (directory in c(paths$raw, paths$interim, paths$diagnostics, paths$data_out)) {
    dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  }
  invisible(paths)
}
