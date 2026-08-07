#' Remove downloaded data and figures
#'
#' Removes the downloaded survey data file and any `figs/` produced by
#' `jagsPrep.R::build_detection_arrays()`, e.g. to tidy up a temporary/cloud
#' environment after a run. Only called from `main.R` if
#' `cleanup.run_after_model` is `true` in the config.
#'
#' @param config a config list, as returned by `load_config()`
#' @return `NULL`, invisibly
#' @seealso [run_occupancy_model()], which calls this if `cleanup.run_after_model` is `true`
#' @family pipeline stages
#' @examples
#' \dontrun{
#' config <- load_config("configs/bof_riwh.yaml")
#' cleanup_outputs(config)
#' }
#' @export
cleanup_outputs <- function(config) {
  if (file.exists(config$paths$data_file)) {
    file.remove(config$paths$data_file)
  }

  figs_dir <- file.path(config$paths$output_dir, "figs")
  if (dir.exists(figs_dir)) {
    unlink(figs_dir, recursive = TRUE)
  }

  invisible(NULL)
}
