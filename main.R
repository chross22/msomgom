# Entry point for the occupancy-model pipeline.
#
# From an R session:
#   source("main.R")
#   result <- run_occupancy_model("configs/bof_riwh.yaml")
#   result$fit          # the fitted mcmc.list
#   result$evaluation    # convergence diagnostics / parameter summary, see evaluate_model.R
#
# From the command line:
#   Rscript main.R configs/bof_riwh.yaml
#
# See config.yaml fields documented in configs/bof_riwh.yaml, and
# generate_config.R to create new config files.

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

run_occupancy_model <- function(config_path) {
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
  fit <- fit_occupancy_model(arrays, config)

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
