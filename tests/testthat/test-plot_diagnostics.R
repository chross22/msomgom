skip_if_not_installed("sf")
skip_if_not_installed("sfheaders")

# A null graphics device, so these tests don't pop up windows or leave
# stray Rplots.pdf files behind.
local_null_device <- function(env = parent.frame()) {
  grDevices::pdf(NULL)
  withr::defer(grDevices::dev.off(), envir = env)
}

make_arrays <- function() {
  configs_dir <- withr::local_tempdir(.local_envir = parent.frame())
  project_dir <- withr::local_tempdir(.local_envir = parent.frame())
  path <- generate_config(
    "plot_test", configs_dir = configs_dir, project_dir = project_dir,
    data_file = "data/mock.csv",
    beg_year = 2018, end_year = 2019, beg_month = 8, end_month = 9
  )
  generate_mock_data(path, surveys_per_season = 3, points_per_survey = 8, seed = 9)
  config <- load_config(path)
  prep <- prep_survey_data(config)
  list(arrays = build_detection_arrays(prep$tmpdat, prep$season_info, config), config = config)
}

test_that("plot_survey_coverage summed across seasons matches colSums(reps)", {
  local_null_device()
  res <- make_arrays()
  arrays <- res$arrays

  grid <- plot_survey_coverage(arrays)
  expect_s3_class(grid, "sf")
  expect_equal(grid$n_surveys, unname(colSums(arrays$reps)))
})

test_that("plot_survey_coverage for one season matches that row of reps", {
  local_null_device()
  res <- make_arrays()
  arrays <- res$arrays

  grid <- plot_survey_coverage(arrays, season = 1)
  expect_equal(grid$n_surveys, unname(arrays$reps[1, ]))
})

test_that("plot_survey_coverage errors on an out-of-range season", {
  local_null_device()
  res <- make_arrays()
  expect_error(plot_survey_coverage(res$arrays, season = 999), "between 1 and")
})

test_that("plot_sightings summed across seasons matches the species array's totals", {
  local_null_device()
  res <- make_arrays()
  arrays <- res$arrays
  species_code <- res$config$species$active

  grid <- plot_sightings(arrays, species_code)
  expected <- apply(arrays$species_arrays[[species_code]][, -1, , drop = FALSE], 1, sum, na.rm = TRUE)
  expect_equal(grid$n_sightings, unname(expected))
})

test_that("plot_sightings for one season matches that season's slice", {
  local_null_device()
  res <- make_arrays()
  arrays <- res$arrays
  species_code <- res$config$species$active

  grid <- plot_sightings(arrays, species_code, season = 1)
  expected <- rowSums(arrays$species_arrays[[species_code]][, -1, 1, drop = FALSE], na.rm = TRUE)
  expect_equal(grid$n_sightings, unname(expected))
})

test_that("plot_sightings errors on an unconfigured species", {
  local_null_device()
  res <- make_arrays()
  expect_error(plot_sightings(res$arrays, "NOTASPECIES"), "no detection array")
})

test_that("plot_occupancy_map errors clearly when Z wasn't tracked", {
  skip_if_not_installed("coda")
  local_null_device()
  res <- make_arrays()

  # a real (tiny) mcmc.list that just never tracked Z - as if the model
  # were fit with jags_params = "colext" instead of "Z"
  chain <- coda::mcmc(matrix(rnorm(20), ncol = 2, dimnames = list(NULL, c("mu.a.0", "mu.b.0"))))
  fit <- coda::mcmc.list(chain, chain)

  expect_error(plot_occupancy_map(fit, res$arrays), "no Z")
})

make_covariate_matrix <- function(arrays, n_windows = 4) {
  set.seed(3)
  matrix(rnorm(arrays$num_cells * n_windows, mean = 15, sd = 2),
         nrow = arrays$num_cells, dimnames = list(NULL, paste0("ssn", seq_len(n_windows))))
}

test_that("plot_covariate_map defaults to the last window", {
  local_null_device()
  res <- make_arrays()
  cov <- make_covariate_matrix(res$arrays)

  grid <- plot_covariate_map(cov, res$arrays)
  expect_s3_class(grid, "sf")
  expect_equal(grid$covariate, unname(cov[, ncol(cov)]))
})

test_that("plot_covariate_map selects a window by position or by label", {
  local_null_device()
  res <- make_arrays()
  cov <- make_covariate_matrix(res$arrays)

  grid_by_pos <- plot_covariate_map(cov, res$arrays, window = 2)
  grid_by_label <- plot_covariate_map(cov, res$arrays, window = "ssn2")
  expect_equal(grid_by_pos$covariate, unname(cov[, 2]))
  expect_equal(grid_by_label$covariate, unname(cov[, 2]))
})

test_that("plot_covariate_map errors on a row-count mismatch", {
  local_null_device()
  res <- make_arrays()
  bad_cov <- matrix(1:10, nrow = 10)
  expect_error(plot_covariate_map(bad_cov, res$arrays), "arrays\\$num_cells")
})

test_that("plot_covariate_map errors on an unknown window label", {
  local_null_device()
  res <- make_arrays()
  cov <- make_covariate_matrix(res$arrays)
  expect_error(plot_covariate_map(cov, res$arrays, window = "nope"), "not found")
})

test_that("plot_covariate_map errors when cov isn't a matrix", {
  local_null_device()
  res <- make_arrays()
  expect_error(plot_covariate_map(data.frame(x = 1), res$arrays), "must be a matrix")
})
