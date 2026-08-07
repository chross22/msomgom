# End-to-end tests against the mock-data workflow. These fit a real (tiny)
# JAGS model, so they're skipped in any environment without a working
# rjags/dclone/JAGS install rather than failing - see README.md for setup.
skip_if_not_installed("sf")
skip_if_not_installed("rjags")
skip_if_not_installed("dclone")
skip_if_not_installed("coda")

make_fast_config <- function(name = "pipeline_test", ...) {
  configs_dir <- withr::local_tempdir(.local_envir = parent.frame())
  project_dir <- withr::local_tempdir(.local_envir = parent.frame())
  path <- generate_config(
    name, configs_dir = configs_dir, project_dir = project_dir,
    data_file = "data/mock.csv", output_dir = "output",
    beg_year = 2018, end_year = 2019, beg_month = 8, end_month = 9,
    n_chains = 2, n_adapt = 20, n_burn = 20, n_iter = 40, thin = 1,
    ...
  )
  generate_mock_data(path, surveys_per_season = 3, points_per_survey = 8, seed = 11)
  path
}

test_that("run_occupancy_model runs end-to-end and returns a fitted mcmc.list", {
  result <- run_occupancy_model(make_fast_config())

  expect_type(result, "list")
  expect_named(result, c("fit", "evaluation"))
  expect_s3_class(result$fit, "mcmc.list")
})

test_that("with no covariates configured, exactly the 7 original hyperparameters are tracked", {
  result <- run_occupancy_model(make_fast_config())

  expect_setequal(
    result$evaluation$parameters$parameter,
    c("mu.a.0", "mu.a.bft", "mu.a.eff", "mu.a.jday", "mu.b.0", "mu.e.0", "mu.g.0")
  )
})

test_that("evaluate_occupancy_model's summary table has one row per tracked parameter with sane columns", {
  result <- run_occupancy_model(make_fast_config())
  params <- result$evaluation$parameters

  expect_true(all(c("parameter", "mean", "sd", "q2.5", "q50", "q97.5", "eff_size", "rhat", "converged") %in% names(params)))
  expect_equal(nrow(params), 7)
  expect_true(all(params$eff_size > 0))
})

test_that("covariates on one process add exactly that process's coefficient, not the others", {
  config_path <- make_fast_config("pipeline_test_cov", covariates_psi = c("sst"))
  config <- load_config(config_path)
  prep <- prep_survey_data(config)
  arrays <- build_detection_arrays(prep$tmpdat, prep$season_info, config)

  windows <- season_windows_from_config(config)
  set.seed(1)
  fake_sst <- matrix(rnorm(arrays$num_cells * nrow(windows), 15, 2),
                      nrow = arrays$num_cells, dimnames = list(NULL, windows$label))

  result <- run_occupancy_model(config_path, occ_covariates = list(sst = fake_sst))
  params <- result$evaluation$parameters$parameter

  expect_true("mu.b.cov" %in% params)  # psi got the covariate
  expect_false("mu.e.cov" %in% params) # phi didn't
  expect_false("mu.g.cov" %in% params) # gamma didn't
})

test_that("jags.params = 'Z' tracks occupancy states and evaluate_occupancy_model compares naive vs. modeled occupancy", {
  result <- run_occupancy_model(make_fast_config("pipeline_test_z", jags_params = "Z"))

  expect_true(any(grepl("^Z\\[", result$evaluation$parameters$parameter)))
  expect_false(is.null(result$evaluation$occupancy_comparison))
  expect_true(all(c("year", "n_sites", "naive_psi", "modeled_psi") %in% names(result$evaluation$occupancy_comparison)))
})

test_that("results save to output_dir when jags.save_results is true (the default)", {
  config_path <- make_fast_config("pipeline_test_save")
  config <- load_config(config_path)
  run_occupancy_model(config_path)

  expected_file <- file.path(config$paths$output_dir, paste0(config$species$active, ".colext.RData"))
  expect_true(file.exists(expected_file))
})

test_that("evaluate_occupancy_model works standalone against a saved .RData path, without re-fitting", {
  config_path <- make_fast_config("pipeline_test_standalone")
  config <- load_config(config_path)
  run_occupancy_model(config_path)

  saved_file <- file.path(config$paths$output_dir, paste0(config$species$active, ".colext.RData"))
  evaluation <- evaluate_occupancy_model(saved_file, config = config, save_plots = FALSE)

  expect_equal(nrow(evaluation$parameters), 7)
})

test_that("cleanup_outputs runs when cleanup.run_after_model is true", {
  config_path <- make_fast_config("pipeline_test_cleanup", cleanup_after_run = TRUE)
  config <- load_config(config_path)
  expect_true(file.exists(config$paths$data_file))

  run_occupancy_model(config_path)

  expect_false(file.exists(config$paths$data_file))
})
