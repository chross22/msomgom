skip_if_not_installed("dplyr")

make_prepped_config <- function() {
  configs_dir <- withr::local_tempdir(.local_envir = parent.frame())
  project_dir <- withr::local_tempdir(.local_envir = parent.frame())
  path <- generate_config(
    "prep_test", configs_dir = configs_dir, project_dir = project_dir,
    data_file = "data/mock.csv",
    beg_year = 2018, end_year = 2018, beg_month = 8, end_month = 9
  )
  generate_mock_data(path, surveys_per_season = 3, points_per_survey = 8, decoy_fraction = 0.15, seed = 7)
  path
}

test_that("prep_survey_data drops decoy records (wrong platform, non-POP FILEID)", {
  config <- load_config(make_prepped_config())
  prep <- prep_survey_data(config)

  expect_true(all(prep$dat$PLATFORM == config$survey$platform_code))
  expect_true(all(substr(prep$dat$FILEID, 1, 1) %in% unlist(config$survey$fileid_prefixes)))
})

test_that("prep_survey_data's tmpdat is a strict subset of columns of dat", {
  config <- load_config(make_prepped_config())
  prep <- prep_survey_data(config)

  expect_true(all(names(prep$tmpdat) %in% names(prep$dat)))
  expect_equal(nrow(prep$tmpdat), nrow(prep$dat))
})

test_that("prep_survey_data assigns every kept record to a season", {
  config <- load_config(make_prepped_config())
  prep <- prep_survey_data(config)

  expect_false(any(is.na(prep$tmpdat$season)))
  expect_true(all(prep$tmpdat$season %in% seq_len(prep$season_info$num_ssn)))
})

test_that("on.off.eff is always 0 or 1, never NA", {
  config <- load_config(make_prepped_config())
  prep <- prep_survey_data(config)

  expect_true(all(prep$dat$on.off.eff %in% c(0, 1)))
})

test_that("survey.on_effort_legtypes controls which LEGTYPE codes count as on-effort", {
  configs_dir <- withr::local_tempdir(.local_envir = parent.frame())
  project_dir <- withr::local_tempdir(.local_envir = parent.frame())
  data_dir <- file.path(project_dir, "data")
  dir.create(data_dir, recursive = TRUE)

  # two otherwise-identical, on-effort-eligible records differing only in
  # LEGTYPE: 5 (the default ship code) vs. 2 (standing in for an aerial
  # survey's own on-effort code)
  dat <- data.frame(
    FILEID = c("P1001a", "P1001a"), EVENTNO = c(1, 2), PLATFORM = 99,
    MONTH = 8, DAY = 10, YEAR = 2018, GMT = 120000,
    LATITUDE = 44.6, LONGITUDE = -66.4,
    LEGTYPE = c(5, 2), LEGSTAGE = 1,
    ALT = NA, HEADING = 0, WX = "C", CLOUD = 1,
    VISIBLTY = 3, BEAUFORT = 2,
    SPECCODE = NA, IDREL = NA, NUMBER = NA, CONFIDNC = NA,
    BEHAV1 = NA, BEHAV2 = NA
  )
  data_file <- file.path(data_dir, "survey.csv")
  write.csv(dat, data_file, row.names = FALSE, na = "")

  path <- generate_config(
    "legtype_test", configs_dir = configs_dir, project_dir = project_dir,
    data_file = "data/survey.csv",
    beg_year = 2018, end_year = 2018, beg_month = 8, end_month = 9
  )

  prep_default <- prep_survey_data(load_config(path)) # default on_effort_legtypes = c(5, 6)
  expect_equal(prep_default$dat$on.off.eff, c(1, 0))

  raw <- yaml::read_yaml(path)
  raw$survey$on_effort_legtypes <- list(2)
  yaml::write_yaml(raw, path)

  prep_custom <- prep_survey_data(load_config(path))
  expect_equal(prep_custom$dat$on.off.eff, c(0, 1))
})
