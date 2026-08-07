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
