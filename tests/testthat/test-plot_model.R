skip_if_not_installed("sf")
skip_if_not_installed("sfheaders")
skip_if_not_installed("ggplot2")
skip_if_not_installed("coda")

local_null_device <- function(env = parent.frame()) {
  grDevices::pdf(NULL)
  withr::defer(grDevices::dev.off(), envir = env)
}

make_arrays <- function() {
  configs_dir <- withr::local_tempdir(.local_envir = parent.frame())
  project_dir <- withr::local_tempdir(.local_envir = parent.frame())
  path <- generate_config(
    "model_plots", configs_dir = configs_dir, project_dir = project_dir,
    data_file = "data/mock.csv",
    beg_year = 2018, end_year = 2019, beg_month = 8, end_month = 9
  )
  generate_mock_data(path, surveys_per_season = 3, points_per_survey = 8, seed = 9)
  config <- load_config(path)
  prep <- prep_survey_data(config)
  list(arrays = build_detection_arrays(prep$tmpdat, prep$season_info, config),
       config = config)
}

# A Z fit over a known grid: two within-year seasons x two years = 4 seasons.
make_z_fit <- function(arrays, seed = 5) {
  set.seed(seed)
  n_cells <- arrays$num_cells
  n_within <- 2
  n_year <- arrays$num_ssn / n_within
  cols <- character(0)
  for (t in seq_len(n_year)) for (l in seq_len(n_within)) {
    cols <- c(cols, sprintf("Z[%d,%d,%d]", seq_len(n_cells), l, t))
  }
  m <- matrix(rbinom(200 * length(cols), 1, 0.4), ncol = length(cols),
              dimnames = list(NULL, cols))
  coda::mcmc.list(coda::mcmc(m), coda::mcmc(m))
}

test_that("plot_occupancy_trend returns one row per season, inside [0, 1]", {
  local_null_device()
  res <- make_arrays()
  fit <- make_z_fit(res$arrays)

  out <- plot_occupancy_trend(fit, res$arrays, res$config)

  expect_equal(nrow(out), res$arrays$num_ssn)
  expect_true(all(out$modeled_psi >= 0 & out$modeled_psi <= 1))
  expect_true(all(out$lower <= out$modeled_psi & out$modeled_psi <= out$upper))
  expect_s3_class(attr(out, "plot"), "ggplot")
})

test_that("plot_occupancy_trend summarizes draws, not per-cell means", {
  # the band has to come from the spread ACROSS draws of the per-draw
  # occupied share; averaging per-cell posterior means first would collapse
  # it to near zero width
  local_null_device()
  res <- make_arrays()
  fit <- make_z_fit(res$arrays)

  out <- plot_occupancy_trend(fit, res$arrays, res$config)
  expect_true(all(out$upper - out$lower > 0))
})

test_that("plot_occupancy_trend refuses a colext fit by name", {
  local_null_device()
  res <- make_arrays()
  m <- matrix(rnorm(100), ncol = 2, dimnames = list(NULL, c("mu.b.0", "mu.e.0")))
  fit <- coda::mcmc.list(coda::mcmc(m), coda::mcmc(m))

  expect_error(plot_occupancy_trend(fit, res$arrays, res$config), "jags_params")
})

test_that("plot_prior_posterior draws every tracked mu.* by default", {
  local_null_device()
  set.seed(2)
  cols <- c("mu.b.0", "mu.e.0", "mu.a.0")
  m <- matrix(rnorm(300 * 3), ncol = 3, dimnames = list(NULL, cols))
  fit <- coda::mcmc.list(coda::mcmc(m), coda::mcmc(m))

  out <- plot_prior_posterior(fit)

  expect_setequal(unique(out$parameter), cols)
  expect_s3_class(attr(out, "plot"), "ggplot")
})

test_that("plot_prior_posterior names a parameter the fit does not track", {
  local_null_device()
  m <- matrix(rnorm(100), ncol = 1, dimnames = list(NULL, "mu.b.0"))
  fit <- coda::mcmc.list(coda::mcmc(m), coda::mcmc(m))

  expect_error(plot_prior_posterior(fit, parameters = "mu.nope"), "mu.nope")
})

test_that("plot_prior_posterior refuses a fit with no mu.* at all", {
  local_null_device()
  m <- matrix(rbinom(50, 1, 0.5), ncol = 1, dimnames = list(NULL, "Z[1,1,1]"))
  fit <- coda::mcmc.list(coda::mcmc(m), coda::mcmc(m))

  expect_error(plot_prior_posterior(fit), "colext")
})

test_that("plot_season_panels builds one column per season from the arrays", {
  skip_if_not_installed("fancymaps")
  local_null_device()
  res <- make_arrays()

  grid <- plot_season_panels(res$arrays, what = "coverage")

  expect_s3_class(grid, "sf")
  expect_true(all(paste("season", seq_len(res$arrays$num_ssn)) %in% names(grid)))
  # the coverage column really is that season's repeat visits
  expect_equal(grid[["season 1"]], unname(res$arrays$reps[1, ]))
})

test_that("plot_season_panels takes a covariate matrix with its grid", {
  skip_if_not_installed("fancymaps")
  local_null_device()
  res <- make_arrays()
  mat <- matrix(seq_len(res$arrays$num_cells * res$arrays$num_ssn),
                nrow = res$arrays$num_cells)

  grid <- plot_season_panels(mat, res$arrays, seasons = c(1, 2))

  # only the requested seasons get a column (the geometry column's own name
  # comes from build_detection_arrays(), so it is not asserted here)
  expect_true(all(c("season 1", "season 2") %in% names(grid)))
  expect_false("season 3" %in% names(grid))
  expect_equal(grid[["season 1"]], mat[, 1])
})

test_that("plot_season_panels checks the matrix against the grid", {
  skip_if_not_installed("fancymaps")
  local_null_device()
  res <- make_arrays()

  expect_error(plot_season_panels(matrix(1:4, nrow = 2), res$arrays),
               "rows but the grid has")
  expect_error(
    plot_season_panels(matrix(1, nrow = res$arrays$num_cells), res$arrays,
                       seasons = 99),
    "outside 1"
  )
})
