#' Run the full occupancy-model pipeline
#'
#' Runs every pipeline stage in order: `prep_survey_data()` (load + clean the
#' survey CSV) -> `build_detection_arrays()` (spatial grid + detection-history
#' arrays) -> `fit_occupancy_model()` (fit the model) ->
#' `evaluate_occupancy_model()` (diagnostics, unless disabled in the config)
#' -> `cleanup_outputs()` (only if `cleanup.run_after_model: true`).
#'
#' @examples
#' \dontrun{
#' library(msomgom)
#' result <- run_occupancy_model("configs/bof_riwh.yaml")
#' result$fit          # the fitted mcmc.list
#' result$evaluation    # convergence diagnostics / parameter summary, see evaluate_occupancy_model()
#'
#' # To put environmental covariates on occupancy/persistence/colonization,
#' # list their names under a config's covariates.psi/phi/gamma (see
#' # configs/bof_riwh.yaml), build them yourself (e.g. with
#' # average_covariates()) into a named list of [num_cells x num_ssn]
#' # matrices, and pass that in:
#' result <- run_occupancy_model("configs/my_run.yaml", occ_covariates = my_covariates)
#' }
#'
#' @param config_path path to a config YAML file (see `load_config()`)
#' @param occ_covariates optional named list of covariate matrices for
#'   `fit_occupancy_model()`; see its documentation
#' @return `list(fit = <mcmc.list>, evaluation = <evaluate_occupancy_model() result, or NULL if skipped>)`
#' @seealso [load_config()], [prep_survey_data()], [build_detection_arrays()],
#'   [fit_occupancy_model()], [evaluate_occupancy_model()], and
#'   [cleanup_outputs()] - the individual stages this function orchestrates
#' @family pipeline stages
#' @export
run_occupancy_model <- function(config_path, occ_covariates = NULL) {
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
