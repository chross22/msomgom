# Removes the downloaded survey data file and any figures/ produced by
# jagsPrep.R::build_detection_arrays(), e.g. to tidy up a temporary/cloud
# environment after a run. Only runs if cleanup.run_after_model is true in
# the config.

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
