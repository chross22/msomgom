make_test_config_path <- function() {
  configs_dir <- withr::local_tempdir(.local_envir = parent.frame())
  project_dir <- withr::local_tempdir(.local_envir = parent.frame())
  generate_config(
    "mock_test", configs_dir = configs_dir, project_dir = project_dir,
    data_file = "data/mock.csv",
    beg_year = 2018, end_year = 2018, beg_month = 8, end_month = 9
  )
}

test_that("generate_mock_data writes a CSV with the expected schema", {
  config_path <- make_test_config_path()
  out_path <- normalizePath(file.path(tempdir(), paste0("mock_", basename(tempfile()), ".csv")), mustWork = FALSE)

  generate_mock_data(config_path, out_path = out_path, surveys_per_season = 2, points_per_survey = 5, seed = 1)
  on.exit(unlink(out_path))

  expect_true(file.exists(out_path))
  dat <- read.csv(out_path, na.strings = "")

  required_cols <- c("FILEID", "EVENTNO", "PLATFORM", "MONTH", "DAY", "YEAR", "GMT",
                      "LATITUDE", "LONGITUDE", "LEGTYPE", "LEGSTAGE", "VISIBLTY", "BEAUFORT",
                      "SPECCODE", "IDREL", "NUMBER", "CONFIDNC")
  expect_true(all(required_cols %in% names(dat)))
  expect_gt(nrow(dat), 0)
})

test_that("mock data includes decoy records the pipeline's filters should drop", {
  config_path <- make_test_config_path()
  out_path <- normalizePath(file.path(tempdir(), paste0("mock_", basename(tempfile()), ".csv")), mustWork = FALSE)
  generate_mock_data(config_path, out_path = out_path, surveys_per_season = 3, points_per_survey = 10,
                      decoy_fraction = 0.2, seed = 2)
  on.exit(unlink(out_path))

  dat <- read.csv(out_path, na.strings = "")
  expect_true(any(dat$PLATFORM != 99))
  expect_true(any(grepl("^O", dat$FILEID)))
})

test_that("generate_mock_data is reproducible given the same seed", {
  config_path <- make_test_config_path()
  out1 <- normalizePath(file.path(tempdir(), paste0("mock1_", basename(tempfile()), ".csv")), mustWork = FALSE)
  out2 <- normalizePath(file.path(tempdir(), paste0("mock2_", basename(tempfile()), ".csv")), mustWork = FALSE)
  on.exit(unlink(c(out1, out2)))

  generate_mock_data(config_path, out_path = out1, seed = 42)
  generate_mock_data(config_path, out_path = out2, seed = 42)

  expect_identical(readLines(out1), readLines(out2))
})

test_that("all mock sightings use species drawn from the configured codes plus decoys", {
  config_path <- make_test_config_path()
  out_path <- normalizePath(file.path(tempdir(), paste0("mock_", basename(tempfile()), ".csv")), mustWork = FALSE)
  generate_mock_data(config_path, out_path = out_path, sighting_probability = 0.9, seed = 3)
  on.exit(unlink(out_path))

  dat <- read.csv(out_path, na.strings = "")
  sightings <- dat[!is.na(dat$SPECCODE), ]
  expect_true(all(sightings$SPECCODE %in% c("RIWH", "HUWH", "FIWH", "MIWH", "HAPO")))
  expect_true("RIWH" %in% sightings$SPECCODE) # the configured target species should appear
})
