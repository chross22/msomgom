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

test_that("plot_detection_history's states agree with reps and the species array", {
  local_null_device()
  res <- make_arrays()
  arrays <- res$arrays
  species_code <- res$config$species$active

  state <- plot_detection_history(arrays, species_code)

  expect_equal(dim(state), c(arrays$num_cells, arrays$num_ssn))

  surveyed <- t(arrays$reps)
  surveyed[is.na(surveyed)] <- 0
  # unsurveyed <-> NA
  expect_equal(is.na(state), surveyed == 0)
  # a detection tile means the species array really has one there
  dets <- arrays$species_arrays[[species_code]][, -1, , drop = FALSE]
  detected <- apply(dets, c(1, 3), function(x) any(x > 0, na.rm = TRUE))
  expect_equal(!is.na(state) & state == 1, detected & surveyed > 0, ignore_attr = TRUE)
})

test_that("plot_detection_history errors on an unknown species", {
  local_null_device()
  res <- make_arrays()
  expect_error(plot_detection_history(res$arrays, "NOTASPECIES"), "not in arrays")
})

test_that("plot_convergence flags exactly the parameters outside the thresholds", {
  skip_if_not_installed("coda")
  local_null_device()

  results <- list(parameters = data.frame(
    parameter = c("good", "bad_rhat", "bad_ess"),
    eff_size = c(500, 500, 10),
    rhat = c(1.0, 1.5, 1.0)
  ))

  out <- plot_convergence(results)
  expect_equal(out$flagged, c(FALSE, TRUE, TRUE))
})

test_that("plot_convergence computes rhat/ess from a raw mcmc.list", {
  skip_if_not_installed("coda")
  local_null_device()

  set.seed(1)
  draws <- function() coda::mcmc(matrix(rnorm(400), ncol = 2, dimnames = list(NULL, c("mu.a.0", "mu.b.0"))))
  fit <- coda::mcmc.list(draws(), draws())

  out <- plot_convergence(fit)
  expect_setequal(out$parameter, c("mu.a.0", "mu.b.0"))
  expect_false(any(out$flagged)) # iid normal draws converge by construction
})

test_that("plot_convergence refuses a single-chain fit by name", {
  skip_if_not_installed("coda")
  local_null_device()
  fit <- coda::mcmc.list(coda::mcmc(matrix(rnorm(100), ncol = 1, dimnames = list(NULL, "mu.a.0"))))
  expect_error(plot_convergence(fit), "n_chains")
})

# A hand-built colext fit whose draws are constant, so every posterior
# summary is exactly computable: two chains, coefficients mu.b.0 = 0.5,
# mu.b.cov = 2 (one psi covariate named sst, standardized against mean 10,
# sd 2), phi and gamma intercept-only at -1 and 1.
make_fake_colext_fit <- function(draws = 50) {
  skip_if_not_installed("coda")
  cols <- c("mu.b.0", "mu.b.cov", "mu.e.0", "mu.g.0")
  m <- matrix(rep(c(0.5, 2, -1, 1), each = draws), ncol = 4,
              dimnames = list(NULL, cols))
  fit <- coda::mcmc.list(coda::mcmc(m), coda::mcmc(m))
  class(fit) <- c("dynocc_fit", class(fit))
  attr(fit, "dynocc_covariates") <- data.frame(
    name = "sst", process = "psi", prefix = "b", index = 1L, n_cov = 1L,
    mean = 10, sd = 2, min = 6, max = 14, stringsAsFactors = FALSE
  )
  fit
}

test_that("predict() reproduces the model's own linear predictor per cell", {
  local_null_device()
  res <- make_arrays()
  arrays <- res$arrays
  fit <- make_fake_colext_fit()

  sst <- matrix(12, nrow = arrays$num_cells, ncol = arrays$num_ssn)
  sst[1, ] <- 8 # one cell colder than the rest

  pred <- predict(fit, arrays, "psi", occ_covariates = list(sst = sst))

  # standardized: (12-10)/2 = 1 -> plogis(0.5 + 2); cell 1: (8-10)/2 = -1
  expect_equal(pred$mean[1], plogis(0.5 - 2))
  expect_equal(pred$mean[2], plogis(0.5 + 2))
  expect_equal(pred$sd, rep(0, arrays$num_cells)) # constant draws
  expect_equal(attr(pred, "process"), "psi")
  expect_equal(nrow(pred), arrays$num_cells)
})

test_that("an intercept-only process predicts flat, with a message", {
  local_null_device()
  res <- make_arrays()
  fit <- make_fake_colext_fit()

  expect_message(pred <- predict(fit, res$arrays, "phi"), "spatially flat")
  expect_equal(unique(pred$mean), plogis(-1))
})

test_that("predict() demands the covariates the process was fit with", {
  local_null_device()
  res <- make_arrays()
  fit <- make_fake_colext_fit()

  expect_error(predict(fit, res$arrays, "psi"), "sst")
})

test_that("predict() names the missing coefficient on a Z-style fit", {
  local_null_device()
  res <- make_arrays()
  chain <- coda::mcmc(matrix(rbinom(20, 1, 0.5), ncol = 2,
                             dimnames = list(NULL, c("Z[1,1,1]", "Z[2,1,1]"))))
  fit <- coda::mcmc.list(chain, chain)
  class(fit) <- c("dynocc_fit", class(fit))

  expect_error(predict(fit, res$arrays, "psi"), "mu.b.0")
})

test_that("plot_process_map() returns the grid with the full summary", {
  local_null_device()
  res <- make_arrays()
  arrays <- res$arrays
  fit <- make_fake_colext_fit()
  sst <- matrix(12, nrow = arrays$num_cells, ncol = arrays$num_ssn)

  grid <- plot_process_map(fit, arrays, "psi", occ_covariates = list(sst = sst),
                           stat = "sd")
  expect_s3_class(grid, "sf")
  expect_true(all(c("mean", "sd", "lower", "upper") %in% names(grid)))
  expect_equal(unique(grid$mean), plogis(0.5 + 2))
})

test_that("predict() rejects an out-of-range season", {
  local_null_device()
  res <- make_arrays()
  fit <- make_fake_colext_fit()
  expect_error(predict(fit, res$arrays, "phi", season = 999), "between 1 and")
})

test_that("plot_occupancy_map stat = 'sd' maps the posterior SD of Z", {
  skip_if_not_installed("coda")
  local_null_device()
  res <- make_arrays()
  arrays <- res$arrays

  n_cells <- arrays$num_cells
  cols <- sprintf("Z[%d,1,1]", seq_len(n_cells))
  set.seed(4)
  m <- matrix(rbinom(200 * n_cells, 1, 0.5), ncol = n_cells, dimnames = list(NULL, cols))
  fit <- coda::mcmc.list(coda::mcmc(m), coda::mcmc(m))

  grid <- plot_occupancy_map(fit, arrays, year = 1, stat = "sd")
  expect_equal(grid$occupancy, unname(apply(rbind(m, m), 2, sd)))
})
