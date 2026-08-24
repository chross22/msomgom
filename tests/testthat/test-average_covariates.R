skip_if_not_installed("sf")

make_test_grid <- function() {
  # a 2x1 grid of 1-degree square cells
  cells <- sf::st_sfc(
    sf::st_polygon(list(rbind(c(0, 0), c(1, 0), c(1, 1), c(0, 1), c(0, 0)))),
    sf::st_polygon(list(rbind(c(1, 0), c(2, 0), c(2, 1), c(1, 1), c(1, 0)))),
    crs = 4326
  )
  sf::st_sf(grid_id = 1:2, geometry = cells)
}

make_test_env_dat <- function() {
  # two points in cell 1, one in cell 2, spanning two days
  df <- data.frame(
    lon = c(0.5, 0.5, 1.5),
    lat = c(0.5, 0.5, 0.5),
    sst = c(10, 20, 100),
    YEAR = 2020, MONTH = 1, DAY = c(1, 2, 1)
  )
  sf::st_as_sf(df, coords = c("lon", "lat"), crs = 4326)
}

test_that("average_covariates averages points within each grid cell and window", {
  grid <- make_test_grid()
  env_dat <- make_test_env_dat()
  windows <- data.frame(start_date = as.Date("2020-01-01"), end_date = as.Date("2020-01-31"), label = "jan")

  result <- average_covariates(env_dat, grid, windows)

  expect_named(result, "sst")
  expect_equal(dim(result$sst), c(2, 1))
  expect_equal(unname(result$sst[1, 1]), mean(c(10, 20))) # cell 1: both Jan points
  expect_equal(unname(result$sst[2, 1]), 100)             # cell 2: the one point
})

test_that("a window with no covariate coverage comes back NA, not 0", {
  grid <- make_test_grid()
  env_dat <- make_test_env_dat()
  windows <- data.frame(
    start_date = as.Date(c("2020-01-01", "2020-06-01")),
    end_date = as.Date(c("2020-01-31", "2020-06-30")),
    label = c("jan", "jun")
  )

  result <- average_covariates(env_dat, grid, windows)

  expect_true(all(!is.na(result$sst[, "jan"])))
  expect_true(all(is.na(result$sst[, "jun"])))
})

test_that("windows filter by date correctly (points outside a window don't leak in)", {
  grid <- make_test_grid()
  env_dat <- make_test_env_dat()
  windows <- data.frame(
    start_date = as.Date("2020-01-01"), end_date = as.Date("2020-01-01"), label = "day1"
  )

  result <- average_covariates(env_dat, grid, windows)

  # only the day-1 point in cell 1 (value 10) should count, not day-2's 20
  expect_equal(unname(result$sst[1, 1]), 10)
})

test_that("columns are ordered/labeled to match windows$label", {
  grid <- make_test_grid()
  env_dat <- make_test_env_dat()
  windows <- data.frame(
    start_date = as.Date(c("2020-01-01", "2020-01-02")),
    end_date = as.Date(c("2020-01-01", "2020-01-02")),
    label = c("first", "second")
  )

  result <- average_covariates(env_dat, grid, windows)
  expect_equal(colnames(result$sst), c("first", "second"))
})

test_that("vars defaults to every non-YEAR/MONTH/DAY/geometry column", {
  grid <- make_test_grid()
  env_dat <- make_test_env_dat()
  env_dat$chl <- c(1, 2, 3)
  windows <- data.frame(start_date = as.Date("2020-01-01"), end_date = as.Date("2020-01-31"), label = "jan")

  result <- average_covariates(env_dat, grid, windows)
  expect_setequal(names(result), c("sst", "chl"))
})

test_that("datamatch provenance columns are excluded from the default vars", {
  grid <- make_test_grid()
  env_dat <- make_test_env_dat()
  # what accessCopernicus() (datamatch >= 0.2.0) sends along with the values
  env_dat$sst_source <- "glorys"
  env_dat$sst_depth <- 0.49
  env_dat$.datamatch_source <- "copernicus"
  env_dat$HOUR <- 0
  windows <- data.frame(start_date = as.Date("2020-01-01"), end_date = as.Date("2020-01-31"), label = "jan")

  result <- average_covariates(env_dat, grid, windows)

  expect_named(result, "sst")
  expect_equal(unname(result$sst[1, 1]), mean(c(10, 20)))
})

test_that("a covariate that merely ends in _depth is kept", {
  grid <- make_test_grid()
  env_dat <- make_test_env_dat()
  env_dat$mixed_layer_depth <- 30 # no 'mixed_layer' column, so a real covariate
  windows <- data.frame(start_date = as.Date("2020-01-01"), end_date = as.Date("2020-01-31"), label = "jan")

  result <- average_covariates(env_dat, grid, windows)

  expect_named(result, c("sst", "mixed_layer_depth"))
})

test_that("an unrecognized non-numeric column is skipped with a message, not averaged to NA", {
  grid <- make_test_grid()
  env_dat <- make_test_env_dat()
  env_dat$platform <- "vessel"
  windows <- data.frame(start_date = as.Date("2020-01-01"), end_date = as.Date("2020-01-31"), label = "jan")

  expect_message(result <- average_covariates(env_dat, grid, windows), "platform")
  expect_named(result, "sst")
})

test_that("explicitly naming a non-numeric var errors instead of warning NA", {
  grid <- make_test_grid()
  env_dat <- make_test_env_dat()
  env_dat$sst_source <- "glorys"
  windows <- data.frame(start_date = as.Date("2020-01-01"), end_date = as.Date("2020-01-31"), label = "jan")

  expect_error(average_covariates(env_dat, grid, windows, vars = "sst_source"), "non-numeric")
})

test_that("explicitly naming a missing var errors with the columns that exist", {
  grid <- make_test_grid()
  env_dat <- make_test_env_dat()
  windows <- data.frame(start_date = as.Date("2020-01-01"), end_date = as.Date("2020-01-31"), label = "jan")

  expect_error(average_covariates(env_dat, grid, windows, vars = "chl"), "not found.*sst")
})

test_that("an env_dat of nothing but provenance errors rather than returning empty", {
  grid <- make_test_grid()
  env_dat <- make_test_env_dat()
  env_dat$sst_source <- "glorys"
  env_dat$sst <- NULL
  # sst gone, so sst_source no longer has its base var - but it's character,
  # so the non-numeric skip catches it and nothing is left
  windows <- data.frame(start_date = as.Date("2020-01-01"), end_date = as.Date("2020-01-31"), label = "jan")

  expect_error(suppressMessages(average_covariates(env_dat, grid, windows)), "No averageable")
})
