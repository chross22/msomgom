# Entry point for the occupancy-model pipeline.
#
# See config.yaml fields documented in configs/bof_riwh.yaml, and
# generate_config.R to create new config files.

#' Find this script's own directory
#'
#' Used so `run_occupancy_model()` can `source()` its sibling scripts
#' regardless of the caller's working directory.
#'
#' @return the directory containing `main.R`, when run via
#'   `Rscript main.R ...` (parsed from `--file=`); otherwise (sourced
#'   interactively) the current working directory, on the assumption it's
#'   already the project root
get_script_dir <- function() {
  cmd_args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", cmd_args, value = TRUE)
  if (length(file_arg) > 0) {
    return(dirname(normalizePath(sub("^--file=", "", file_arg[1]))))
  }
  # sourced interactively rather than run via Rscript: assume the working
  # directory is already the project root
  getwd()
}

#' Run the full occupancy-model pipeline
#'
#' Sources every pipeline stage and runs them in order: `prep_survey_data()`
#' (load + clean the survey CSV) -> `build_detection_arrays()` (spatial grid
#' + detection-history arrays) -> `fit_occupancy_model()` (fit the model) ->
#' `evaluate_occupancy_model()` (diagnostics, unless disabled in the config)
#' -> `cleanup_outputs()` (only if `cleanup.run_after_model: true`).
#'
#' @examples
#' \dontrun{
#' source("main.R")
#' result <- run_occupancy_model("configs/bof_riwh.yaml")
#' result$fit          # the fitted mcmc.list
#' result$evaluation    # convergence diagnostics / parameter summary, see evaluate_model.R
#'
#' # To put environmental covariates on occupancy/persistence/colonization,
#' # list their names under a config's covariates.psi/phi/gamma (see
#' # configs/bof_riwh.yaml), build them yourself (e.g. with
#' # average_covariates.R) into a named list of [num_cells x num_ssn]
#' # matrices, and pass that in:
#' result <- run_occupancy_model("configs/my_run.yaml", occ_covariates = my_covariates)
#' }
#'
#' From the command line (no `occ_covariates` support - `covariates.psi/phi/gamma`
#' must be empty in the config): `Rscript main.R configs/bof_riwh.yaml`
#'
#' @param config_path path to a config YAML file (see `load_config()`)
#' @param occ_covariates optional named list of covariate matrices for
#'   `fit_occupancy_model()`; see its documentation
#' @return `list(fit = <mcmc.list>, evaluation = <evaluate_occupancy_model() result, or NULL if skipped>)`
run_occupancy_model <- function(config_path, occ_covariates = NULL) {
  pipeline_dir <- get_script_dir()
  source(file.path(pipeline_dir, "padstr0.R"))
  source(file.path(pipeline_dir, "makeSeasons.R"))
  source(file.path(pipeline_dir, "load_config.R"))
  source(file.path(pipeline_dir, "data_prep.R"))
  source(file.path(pipeline_dir, "jagsPrep.R"))
  source(file.path(pipeline_dir, "jags.R"))
  source(file.path(pipeline_dir, "evaluate_model.R"))
  source(file.path(pipeline_dir, "cleanup.R"))

  config <- load_config(config_path)

  prep <- prep_survey_data(config)
  arrays <- build_detection_arrays(prep$tmpdat, prep$season_info, config)
  fit <- fit_occupancy_model(arrays, config, occ_covariates = occ_covariates)

  evaluation <- NULL
  if (is.null(config$evaluation) || isTRUE(config$evaluation$run_after_fit)) {
    evaluation <- evaluate_occupancy_model(
      fit, arrays, config,
      save_plots = is.null(config$evaluation) || isTRUE(config$evaluation$save_plots)
    )
  }

  if (isTRUE(config$cleanup$run_after_model)) {
    cleanup_outputs(config)
  }

  list(fit = fit, evaluation = evaluation)
}

# only auto-run when invoked directly via `Rscript main.R <config_path>`,
# not when sourced (source() adds a stack frame, direct Rscript execution doesn't)
if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) < 1) {
    stop("Usage: Rscript main.R <path/to/config.yaml>")
  }
  run_occupancy_model(args[1])
}
