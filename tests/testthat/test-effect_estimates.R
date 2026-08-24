# dynocc_covariate_lookup(): pure logic, no JAGS/fancyfx needed.

make_fake_fit <- function(meta) {
  fit <- structure(list(), class = c("dynocc_fit", "mcmc.list"))
  attr(fit, "dynocc_covariates") <- meta
  fit
}

test_that("dynocc_covariate_lookup finds the right row by name", {
  meta <- data.frame(name = c("sst", "chl"), process = c("psi", "phi"),
                      prefix = c("b", "e"), index = c(1, 1), n_cov = c(1, 1),
                      mean = c(15, 2), sd = c(2, 0.5), min = c(10, 1), max = c(20, 3))
  fit <- make_fake_fit(meta)

  hit <- dynocc_covariate_lookup(fit, "chl")
  expect_equal(hit$process, "phi")
  expect_equal(hit$prefix, "e")
})

test_that("dynocc_covariate_lookup errors on an unknown covariate", {
  meta <- data.frame(name = "sst", process = "psi", prefix = "b", index = 1,
                      n_cov = 1, mean = 15, sd = 2, min = 10, max = 20)
  fit <- make_fake_fit(meta)
  expect_error(dynocc_covariate_lookup(fit, "nope"), "not a covariate")
})

test_that("dynocc_covariate_lookup errors when metadata is missing entirely", {
  fit <- make_fake_fit(NULL)
  expect_error(dynocc_covariate_lookup(fit, "sst"), "no covariate metadata")
})

test_that("dynocc_covariate_lookup errors when a covariate is on more than one process", {
  meta <- data.frame(name = c("sst", "sst"), process = c("psi", "phi"),
                      prefix = c("b", "e"), index = c(1, 1), n_cov = c(1, 1),
                      mean = c(15, 15), sd = c(2, 2), min = c(10, 10), max = c(20, 20))
  fit <- make_fake_fit(meta)
  expect_error(dynocc_covariate_lookup(fit, "sst"), "more than one process")
})

# End-to-end: real (tiny) JAGS fits, so these need a working rjags/dclone/JAGS
# install, same as tests/testthat/test-pipeline-integration.R.
skip_if_not_installed("sf")
skip_if_not_installed("rjags")
skip_if_not_installed("dclone")
skip_if_not_installed("coda")

make_effect_config <- function(name = "effect_test", ...) {
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
  config <- load_config(path)
  prep <- prep_survey_data(config)
  arrays <- build_detection_arrays(prep$tmpdat, prep$season_info, config)
  list(arrays = arrays, config = config)
}

fake_covariate_matrix <- function(arrays, windows, seed = 1, mean = 15, sd = 2) {
  set.seed(seed)
  matrix(rnorm(arrays$num_cells * nrow(windows), mean, sd),
         nrow = arrays$num_cells, dimnames = list(NULL, windows$label))
}

test_that("fit_occupancy_model tags class and attaches correct covariate metadata", {
  res <- make_effect_config("effect_meta", covariates_psi = c("sst"))
  windows <- season_windows_from_config(res$config)
  sst <- fake_covariate_matrix(res$arrays, windows)

  fit <- fit_occupancy_model(res$arrays, res$config, occ_covariates = list(sst = sst))

  expect_s3_class(fit, "dynocc_fit")
  expect_s3_class(fit, "mcmc.list") # unaffected: coda methods still dispatch

  meta <- attr(fit, "dynocc_covariates")
  expect_equal(meta$name, "sst")
  expect_equal(meta$process, "psi")
  expect_equal(meta$prefix, "b")
  expect_equal(meta$index, 1)
  expect_equal(meta$n_cov, 1)
  expect_equal(meta$mean, mean(sst, na.rm = TRUE))
  expect_equal(meta$sd, stats::sd(sst, na.rm = TRUE))
  expect_equal(meta$min, min(sst, na.rm = TRUE))
  expect_equal(meta$max, max(sst, na.rm = TRUE))
})

test_that("fit_occupancy_model with no covariates configured attaches no metadata", {
  res <- make_effect_config("effect_none")
  fit <- fit_occupancy_model(res$arrays, res$config)
  expect_null(attr(fit, "dynocc_covariates"))
})

test_that("effect_estimates() on a dynocc_fit returns fancyfx's documented shape", {
  skip_if_not_installed("fancyfx")
  res <- make_effect_config("effect_shape", covariates_psi = c("sst"))
  windows <- season_windows_from_config(res$config)
  sst <- fake_covariate_matrix(res$arrays, windows)
  fit <- fit_occupancy_model(res$arrays, res$config, occ_covariates = list(sst = sst))

  est <- fancyfx::effect_estimates(fit, "sst")
  expect_s3_class(est, "data.frame")
  expect_named(est, c(".x", ".estimate", ".lower", ".upper"))
  expect_equal(nrow(est), 100) # default n
  expect_equal(attr(est, "quantity"), "Partial Effect (logit scale)") # scale = "auto" -> "link"
  expect_true(all(est$.lower <= est$.estimate & est$.estimate <= est$.upper))
  # grid spans the covariate's own observed range, not an arbitrary multiple of sd
  expect_equal(range(est$.x), c(min(sst), max(sst)))
})

test_that("scale = 'response' returns predicted occupancy probability in [0, 1]", {
  skip_if_not_installed("fancyfx")
  res <- make_effect_config("effect_response", covariates_psi = c("sst"))
  windows <- season_windows_from_config(res$config)
  sst <- fake_covariate_matrix(res$arrays, windows)
  fit <- fit_occupancy_model(res$arrays, res$config, occ_covariates = list(sst = sst))

  est <- fancyfx::effect_estimates(fit, "sst", scale = "response")
  expect_equal(attr(est, "quantity"), "Predicted Occupancy Probability")
  expect_true(all(est$.estimate >= 0 & est$.estimate <= 1))
  expect_true(all(est$.lower >= 0 & est$.upper <= 1))
})

test_that("interval = 'se' gives a narrower band than the default credible interval", {
  skip_if_not_installed("fancyfx")
  res <- make_effect_config("effect_interval", covariates_psi = c("sst"))
  windows <- season_windows_from_config(res$config)
  sst <- fake_covariate_matrix(res$arrays, windows)
  fit <- fit_occupancy_model(res$arrays, res$config, occ_covariates = list(sst = sst))

  est_ci <- fancyfx::effect_estimates(fit, "sst", interval = "ci")
  est_se <- fancyfx::effect_estimates(fit, "sst", interval = "se")
  # a 95% credible interval is wider than a +/- 1 SD band for a roughly normal posterior
  expect_true(mean(est_ci$.upper - est_ci$.lower) > mean(est_se$.upper - est_se$.lower))
})

test_that("effect_estimates() errors clearly for an unconfigured covariate name", {
  skip_if_not_installed("fancyfx")
  res <- make_effect_config("effect_unknown", covariates_psi = c("sst"))
  windows <- season_windows_from_config(res$config)
  sst <- fake_covariate_matrix(res$arrays, windows)
  fit <- fit_occupancy_model(res$arrays, res$config, occ_covariates = list(sst = sst))

  expect_error(fancyfx::effect_estimates(fit, "chl"), "not a covariate")
})

test_that("effect_estimates() errors clearly on a fit with no covariates at all", {
  skip_if_not_installed("fancyfx")
  res <- make_effect_config("effect_no_meta")
  fit <- fit_occupancy_model(res$arrays, res$config)

  expect_error(fancyfx::effect_estimates(fit, "sst"), "no covariate metadata")
})

test_that("effect_estimates() errors clearly on a jags_params = 'Z' fit", {
  skip_if_not_installed("fancyfx")
  res <- make_effect_config("effect_zmode", covariates_psi = c("sst"), jags_params = "Z")
  windows <- season_windows_from_config(res$config)
  sst <- fake_covariate_matrix(res$arrays, windows)
  fit <- fit_occupancy_model(res$arrays, res$config, occ_covariates = list(sst = sst))

  expect_error(fancyfx::effect_estimates(fit, "sst"), "doesn't track")
})

test_that("a second covariate on the same process resolves its bracketed mcmc column correctly", {
  skip_if_not_installed("fancyfx")
  res <- make_effect_config("effect_multicov", covariates_psi = c("sst", "chl"))
  windows <- season_windows_from_config(res$config)
  sst <- fake_covariate_matrix(res$arrays, windows, seed = 1, mean = 15, sd = 2)
  chl <- fake_covariate_matrix(res$arrays, windows, seed = 2, mean = 2, sd = 0.5)
  fit <- fit_occupancy_model(res$arrays, res$config, occ_covariates = list(sst = sst, chl = chl))

  meta <- attr(fit, "dynocc_covariates")
  expect_equal(sort(meta$name), c("chl", "sst"))
  expect_true(all(meta$n_cov == 2))

  est_sst <- fancyfx::effect_estimates(fit, "sst")
  est_chl <- fancyfx::effect_estimates(fit, "chl")
  expect_equal(range(est_sst$.x), c(min(sst), max(sst)))
  expect_equal(range(est_chl$.x), c(min(chl), max(chl)))
  # the two covariates' fitted coefficients are (almost certainly) different,
  # so their effect curves shouldn't be identical
  expect_false(isTRUE(all.equal(est_sst$.estimate, est_chl$.estimate)))
})

test_that("plotEffects() runs end-to-end on a dynocc_fit", {
  skip_if_not_installed("fancyfx")
  res <- make_effect_config("effect_plot", covariates_psi = c("sst"))
  windows <- season_windows_from_config(res$config)
  sst <- fake_covariate_matrix(res$arrays, windows)
  fit <- fit_occupancy_model(res$arrays, res$config, occ_covariates = list(sst = sst))

  grDevices::pdf(NULL)
  on.exit(grDevices::dev.off())

  rug_dat <- data.frame(sst = as.vector(sst))
  p <- fancyfx::plotEffects(fit, rug_dat, "sst", xlab = "SST")
  expect_s3_class(p, "patchwork")
})
