#' Diagnose common reasons a run might fail, hang, or produce meaningless output
#'
#' Runs `prep_survey_data()` and `build_detection_arrays()` - never JAGS
#' itself - and reports on the most common ways a run goes wrong before it
#' ever reaches the model: a filter that leaves nothing, a study-area
#' polygon that misses the survey tracks, a species with zero detections, a
#' season nothing got assigned to, or a covariate matrix with the wrong
#' shape. Meant to run *before* `run_occupancy_model()`/`fit_occupancy_model()`,
#' so a misconfiguration is caught in seconds rather than after a slow JAGS
#' run that either errors cryptically or "succeeds" with meaningless output.
#'
#' Every check here reports a problem rather than fixing it - this function
#' never modifies the config, the data, or the returned objects.
#'
#' @param config_path path to a config YAML, or an already-loaded config
#'   list (as returned by `load_config()`)
#' @param occ_covariates optional named list, as passed to
#'   `fit_occupancy_model()`/`run_occupancy_model()` - checked for missing
#'   names and shape mismatches against `config$covariates$psi/phi/gamma`
#' @return invisibly, `list(config, prep, arrays)` - whichever of these were
#'   reached before a fatal problem stopped the checks - so you can pick up
#'   investigating from there, e.g. `plot_survey_coverage(result$arrays)`
#' @seealso [prep_survey_data()]'s `verbose` argument, which this uses;
#'   [plot_survey_coverage()] and [plot_sightings()] for visualizing what
#'   this function reports as plain numbers; [run_occupancy_model()], which
#'   this is meant to run ahead of
#' @family pipeline stages
#' @examples
#' \dontrun{
#' diagnose_pipeline("configs/my_run.yaml")
#' diagnose_pipeline("configs/my_run.yaml", occ_covariates = list(sst = sst_avg$sst))
#' }
#' @export
diagnose_pipeline <- function(config_path, occ_covariates = NULL) {
  ok <- TRUE
  header <- function(x) cat("\n== ", x, " ==\n", sep = "")
  pass <- function(...) cat("  ok    ", ..., "\n", sep = "")
  warn <- function(...) {
    cat("  WARN  ", ..., "\n", sep = "")
    ok <<- FALSE
  }
  fail <- function(...) {
    cat("  FAIL  ", ..., "\n", sep = "")
    ok <<- FALSE
  }

  cat("msomgom pipeline diagnosis\n")

  header("Config")
  config <- tryCatch(
    if (is.character(config_path)) load_config(config_path) else config_path,
    error = function(e) {
      fail("could not load config: ", conditionMessage(e))
      NULL
    }
  )
  if (is.null(config)) {
    cat("\nStopped: fix the config error above before continuing.\n")
    return(invisible(list(config = NULL)))
  }
  pass("loaded (active species: ", config$species$active, ")")

  header("JAGS toolchain")
  if (requireNamespace("rjags", quietly = TRUE) && requireNamespace("dclone", quietly = TRUE)) {
    pass("rjags and dclone are installed")
  } else {
    warn("rjags and/or dclone not installed - fitting will fail even if everything else here ",
         "passes. install.packages(c(\"rjags\", \"dclone\")); see README.md for JAGS setup.")
  }
  if (requireNamespace("coda", quietly = TRUE)) {
    pass("coda is installed (needed for evaluate_occupancy_model())")
  } else {
    warn("coda not installed - evaluate_occupancy_model() will fail after a fit completes")
  }

  header("Survey data")
  prep <- tryCatch(prep_survey_data(config, verbose = TRUE), error = function(e) {
    fail("prep_survey_data() failed: ", conditionMessage(e))
    NULL
  })
  if (is.null(prep)) {
    cat("\nStopped: fix the data error above before continuing.\n")
    return(invisible(list(config = config)))
  }
  n_on_effort <- sum(prep$dat$on.off.eff == 1)
  if (nrow(prep$dat) == 0) {
    fail("0 records survived filtering - see the warning above for which filter did it")
    # stop here rather than handing an empty dataset to build_detection_arrays(),
    # which fails with an internal type error that says nothing about the real cause
    cat("\nStopped: no records to grid. Fix the filters above before continuing.\n")
    return(invisible(list(config = config, prep = prep)))
  } else if (n_on_effort == 0) {
    fail("0 on-effort records - see the warning above")
  } else {
    pass(nrow(prep$dat), " records survived filtering, ", n_on_effort, " on-effort")
  }

  header("Spatial grid")
  arrays <- tryCatch(build_detection_arrays(prep$tmpdat, prep$season_info, config), error = function(e) {
    fail("build_detection_arrays() failed: ", conditionMessage(e))
    NULL
  })
  if (is.null(arrays)) {
    cat("\nStopped: fix the grid error above before continuing.\n")
    return(invisible(list(config = config, prep = prep)))
  }
  if (arrays$num_cells == 0) {
    fail("study_area.polygon produced a 0-cell grid - it likely doesn't overlap the survey ",
         "data's extent")
  } else {
    pass(arrays$num_cells, " grid cells, ", arrays$num_ssn, " season x year combination(s), ",
         "max ", arrays$max_survs, " survey(s) in any one season")
  }
  empty_seasons <- which(rowSums(arrays$reps) == 0)
  if (length(empty_seasons) > 0) {
    warn(length(empty_seasons), " season(s) have zero surveyed cells (season index: ",
         paste(empty_seasons, collapse = ", "), ") - those seasons contribute nothing to the fit")
  } else {
    pass("every season has at least one surveyed cell")
  }

  header("Species detections")
  for (spp in names(arrays$species_arrays)) {
    total <- sum(arrays$species_arrays[[spp]][, -1, , drop = FALSE], na.rm = TRUE)
    if (total == 0) {
      warn(spp, ": zero detections across the whole study - psi will be estimated near 0 ",
           "and colonization/persistence won't be identifiable for this species")
    } else {
      pass(spp, ": ", total, " total sightings")
    }
  }

  if (!is.null(occ_covariates)) {
    header("Covariates")
    configured <- unique(unlist(config$covariates[c("psi", "phi", "gamma")]))
    if (length(configured) == 0) {
      pass("no covariates configured in config$covariates$psi/phi/gamma; occ_covariates is ignored")
    }
    for (nm in configured) {
      if (!(nm %in% names(occ_covariates))) {
        fail("'", nm, "' is referenced in config$covariates but missing from occ_covariates")
        next
      }
      mat <- occ_covariates[[nm]]
      if (!is.matrix(mat) || nrow(mat) != arrays$num_cells || ncol(mat) != arrays$num_ssn) {
        fail("'", nm, "' has shape [",
             if (is.matrix(mat)) paste(nrow(mat), "x", ncol(mat)) else class(mat)[1],
             "] but must be [", arrays$num_cells, " x ", arrays$num_ssn,
             "] (num_cells x num_ssn) to match this run's grid")
      } else {
        pass("'", nm, "' shape matches this run's grid")
      }
    }
  }

  cat("\n", if (ok) {
    "All checks passed - looks ready to fit."
  } else {
    "Some checks need attention - see WARN/FAIL above."
  }, "\n", sep = "")

  invisible(list(config = config, prep = prep, arrays = arrays))
}
