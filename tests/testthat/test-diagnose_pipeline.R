skip_if_not_installed("sf")
skip_if_not_installed("sfheaders")

make_healthy_config <- function(name = "diagnose_test", ...) {
  configs_dir <- withr::local_tempdir(.local_envir = parent.frame())
  project_dir <- withr::local_tempdir(.local_envir = parent.frame())
  path <- generate_config(
    name, configs_dir = configs_dir, project_dir = project_dir,
    data_file = "data/mock.csv",
    beg_year = 2018, end_year = 2019, beg_month = 8, end_month = 9,
    ...
  )
  generate_mock_data(path, surveys_per_season = 3, points_per_survey = 8, seed = 11)
  path
}

test_that("diagnose_pipeline reports FAIL and stops cleanly on a bad config path", {
  expect_output(
    result <- diagnose_pipeline("/does/not/exist.yaml"),
    "FAIL.*could not load config"
  )
  expect_null(result$config)
})

test_that("diagnose_pipeline reaches config/prep/arrays and reports ok on a healthy setup", {
  path <- make_healthy_config()

  out <- capture.output(result <- diagnose_pipeline(path))
  report <- paste(out, collapse = "\n")

  expect_false(is.null(result$config))
  expect_false(is.null(result$prep))
  expect_false(is.null(result$arrays))
  expect_match(report, "All checks passed", fixed = TRUE)
  expect_no_match(report, "FAIL")
})

test_that("diagnose_pipeline reports FAIL when the data filters leave nothing", {
  path <- make_healthy_config("diagnose_zero_rows", platform_code = 12345) # matches nothing in the mock data

  out <- capture.output(result <- diagnose_pipeline(path))
  report <- paste(out, collapse = "\n")

  expect_match(report, "FAIL.*0 records survived filtering")
  expect_null(result$arrays) # stopped before reaching the grid stage
})

test_that("diagnose_pipeline reports missing and mismatched covariates", {
  path <- make_healthy_config("diagnose_cov", covariates_psi = c("sst"))
  config <- load_config(path)
  prep <- prep_survey_data(config)
  arrays <- build_detection_arrays(prep$tmpdat, prep$season_info, config)

  # missing entirely
  out_missing <- capture.output(diagnose_pipeline(path, occ_covariates = list()))
  expect_match(paste(out_missing, collapse = "\n"), "FAIL.*'sst'.*missing from occ_covariates")

  # wrong shape
  bad_sst <- matrix(1, nrow = 1, ncol = 1)
  out_bad_shape <- capture.output(diagnose_pipeline(path, occ_covariates = list(sst = bad_sst)))
  expect_match(paste(out_bad_shape, collapse = "\n"), "FAIL.*'sst'.*shape")

  # correctly shaped
  windows <- season_windows_from_config(config)
  good_sst <- matrix(rnorm(arrays$num_cells * nrow(windows), 15, 2),
                      nrow = arrays$num_cells, dimnames = list(NULL, windows$label))
  out_good <- capture.output(diagnose_pipeline(path, occ_covariates = list(sst = good_sst)))
  expect_match(paste(out_good, collapse = "\n"), "ok.*'sst' shape matches")
})

test_that("diagnose_pipeline works from an already-loaded config, not just a path", {
  path <- make_healthy_config("diagnose_loaded")
  config <- load_config(path)

  out <- capture.output(result <- diagnose_pipeline(config))
  expect_match(paste(out, collapse = "\n"), "All checks passed", fixed = TRUE)
  expect_false(is.null(result$arrays))
})
