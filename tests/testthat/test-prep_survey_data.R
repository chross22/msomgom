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
    MONTH = 8, DAY = 10, YEAR = 2018, TIME = 120000,
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

test_that("verbose = TRUE reports row counts through each filter step; FALSE (the default) is silent", {
  config <- load_config(make_prepped_config())
  expect_message(prep_survey_data(config, verbose = TRUE), "records read from")
  expect_no_message(prep_survey_data(config))
})

make_hand_built_config <- function(dat, name = "hand_built_test",
                                    beg_year = 2018, end_year = 2018,
                                    beg_month = 8, end_month = 9, ...) {
  configs_dir <- withr::local_tempdir(.local_envir = parent.frame())
  project_dir <- withr::local_tempdir(.local_envir = parent.frame())
  data_dir <- file.path(project_dir, "data")
  dir.create(data_dir, recursive = TRUE)
  data_file <- file.path(data_dir, "survey.csv")
  write.csv(dat, data_file, row.names = FALSE, na = "")

  path <- generate_config(
    name, configs_dir = configs_dir, project_dir = project_dir,
    data_file = "data/survey.csv",
    beg_year = beg_year, end_year = end_year, beg_month = beg_month, end_month = end_month,
    ...
  )
  load_config(path)
}

make_hand_built_record <- function(...) {
  defaults <- list(
    FILEID = "P1001a", EVENTNO = 1, PLATFORM = 99,
    MONTH = 8, DAY = 10, YEAR = 2018, TIME = 120000,
    LATITUDE = 44.6, LONGITUDE = -66.4,
    LEGTYPE = 5, LEGSTAGE = 1,
    ALT = NA, HEADING = 0, WX = "C", CLOUD = 1,
    VISIBLTY = 3, BEAUFORT = 2,
    SPECCODE = NA, IDREL = NA, NUMBER = NA, CONFIDNC = NA,
    BEHAV1 = NA, BEHAV2 = NA
  )
  overrides <- list(...)
  do.call(data.frame, modifyList(defaults, overrides))
}

test_that("prep_survey_data warns when zero records survive the platform/FILEID/date filters", {
  dat <- make_hand_built_record(PLATFORM = 1) # doesn't match the default platform_code (99)
  config <- make_hand_built_config(dat, "zero_rows_test")

  expect_warning(prep <- prep_survey_data(config), "No records remain")
  expect_equal(nrow(prep$dat), 0)
})

test_that("an unset platform_code/fileid_prefixes errors rather than keeping everything", {
  dat <- make_hand_built_record()

  config <- make_hand_built_config(dat, "no_platform_test", platform_code = NULL)
  expect_error(prep_survey_data(config), "survey.platform_code is not set")

  config <- make_hand_built_config(dat, "no_prefix_test", fileid_prefixes = NULL)
  expect_error(prep_survey_data(config), "survey.fileid_prefixes is not set")
})

test_that("platform_code accepts more than one code", {
  dat <- rbind(make_hand_built_record(EVENTNO = 1, PLATFORM = 99),
               make_hand_built_record(EVENTNO = 2, PLATFORM = 107))
  config <- make_hand_built_config(dat, "multi_platform_test", platform_code = c(99, 107))

  prep <- prep_survey_data(config)
  expect_setequal(prep$dat$PLATFORM, c(99, 107))
})

test_that("a set platform_code with no PLATFORM column errors clearly rather than dropping everything", {
  dat <- make_hand_built_record()
  dat$PLATFORM <- NULL
  config <- make_hand_built_config(dat, "no_platform_col_test")

  expect_error(prep_survey_data(config), "no PLATFORM column")
})

test_that("prep_survey_data warns on a record with no season covering its date", {
  # Aug 20 is within the configured month (8) but outside the configured
  # season's day-range (1-15) below, so it should get season = NA
  dat <- make_hand_built_record(DAY = 20)
  config <- make_hand_built_config(
    dat, "season_gap_test", end_month = 8,
    seasons = list(list(begin = c(8, 1), end = c(8, 15)))
  )

  expect_warning(prep <- prep_survey_data(config), "no season")
  expect_true(is.na(prep$dat$season))
})

test_that("prep_survey_data warns when zero records are on-effort", {
  dat <- make_hand_built_record(VISIBLTY = 1) # fails the on-effort visibility check
  config <- make_hand_built_config(dat, "zero_effort_test")

  expect_warning(prep <- prep_survey_data(config), "No on-effort records")
  expect_equal(prep$dat$on.off.eff, 0)
})

test_that("prep_survey_data errors clearly when the data file is missing and no remote source is configured", {
  project_dir <- withr::local_tempdir(.local_envir = parent.frame())
  config <- list(paths = list(
    data_file = file.path(project_dir, "nope.csv"),
    google_drive_filename = NULL, onedrive_filename = NULL
  ))
  expect_error(prep_survey_data(config), "neither google_drive_filename nor onedrive_filename")
})

test_that("prep_survey_data reports a clear error when Microsoft365R isn't installed for a OneDrive source", {
  skip_if(requireNamespace("Microsoft365R", quietly = TRUE),
          "Microsoft365R is installed; can't exercise the missing-package path")

  configs_dir <- withr::local_tempdir(.local_envir = parent.frame())
  project_dir <- withr::local_tempdir(.local_envir = parent.frame())
  path <- generate_config(
    "onedrive_test", configs_dir = configs_dir, project_dir = project_dir,
    data_file = "data/does_not_exist.csv", onedrive_filename = "survey/data.csv"
  )
  config <- load_config(path)

  expect_error(prep_survey_data(config), "Microsoft365R")
})

test_that("split_surveys_by derives per-survey FILEIDs when the source file uses one for everything", {
  # every record carries the same FILEID ("F"), across two days and two
  # platforms - one survey covering everything, as far as gridding is concerned
  dat <- rbind(
    make_hand_built_record(EVENTNO = 1, FILEID = "F", DAY = 10, PLATFORM = 99),
    make_hand_built_record(EVENTNO = 2, FILEID = "F", DAY = 10, PLATFORM = 107),
    make_hand_built_record(EVENTNO = 3, FILEID = "F", DAY = 11, PLATFORM = 99)
  )

  config <- make_hand_built_config(dat, "split_none_test", platform_code = c(99, 107),
                                   fileid_prefixes = "F")
  expect_equal(unique(prep_survey_data(config)$dat$FILEID), "F")

  config <- make_hand_built_config(dat, "split_date_test", platform_code = c(99, 107),
                                   fileid_prefixes = "F", split_surveys_by = "date")
  expect_setequal(prep_survey_data(config)$dat$FILEID, c("F_20180810", "F_20180810", "F_20180811"))

  config <- make_hand_built_config(dat, "split_date_platform_test", platform_code = c(99, 107),
                                   fileid_prefixes = "F", split_surveys_by = "date_platform")
  expect_setequal(prep_survey_data(config)$dat$FILEID,
                  c("F_20180810_99", "F_20180810_107", "F_20180811_99"))
})

test_that("an unrecognized split_surveys_by errors rather than silently doing nothing", {
  config <- make_hand_built_config(make_hand_built_record(), "bad_split_test")
  config$survey$split_surveys_by <- "week"

  expect_error(prep_survey_data(config), "split_surveys_by must be")
})

test_that("a FILEID column that looks logical to readr is kept as text", {
  # every value is "F", which readr guesses as a logical column - it would
  # arrive as "FALSE", silently renaming every survey in the file
  dat <- rbind(make_hand_built_record(EVENTNO = 1, FILEID = "F"),
               make_hand_built_record(EVENTNO = 2, FILEID = "F"))
  config <- make_hand_built_config(dat, "logical_fileid_test", fileid_prefixes = "F")

  expect_equal(unique(prep_survey_data(config)$dat$FILEID), "F")
})

test_that("a zero-padded PLATFORM code matches an unpadded config code", {
  dat <- make_hand_built_record(PLATFORM = "099")
  config <- make_hand_built_config(dat, "padded_platform_test")

  expect_equal(nrow(prep_survey_data(config)$dat), 1)
})

test_that("PLATFORM matches by value: named platforms and zero-padded codes both work", {
  dat <- rbind(make_hand_built_record(EVENTNO = 1, PLATFORM = "Vessel"),
               make_hand_built_record(EVENTNO = 2, PLATFORM = "Aerial"))

  # a config that names the platform instead of coding it, matched case-insensitively
  config <- make_hand_built_config(dat, "named_platform_test", platform_code = "vessel")
  prep <- prep_survey_data(config)
  expect_equal(prep$dat$PLATFORM, "Vessel")

  config <- make_hand_built_config(dat, "named_platform_both_test",
                                   platform_code = c("Vessel", "Aerial"))
  expect_equal(nrow(prep_survey_data(config)$dat), 2)
})

test_that("a TIME written as a clock is read, not silently emptied", {
  expect_equal(parse_survey_time(c("12:34:56", "12:34")), c(123456, 123400))
  expect_equal(parse_survey_time("2024-04-01T12:34:56Z"), 123456)
  expect_equal(parse_survey_time(c("120000", NA, "")), c(120000, NA, NA))
  expect_equal(parse_survey_time(c(120000, 130000)), c(120000, 130000)) # already numeric
})

test_that("prep_survey_data dates a record whose TIME carries a clock", {
  dat <- make_hand_built_record(TIME = "12:34:56")
  config <- make_hand_built_config(dat, "clock_time_test")

  prep <- prep_survey_data(config)
  expect_equal(prep$dat$TIME, 123456)
  expect_false(is.na(prep$dat$datetime_GMT))
})

test_that("a numeric column emptied by the read warns instead of arriving as NA", {
  dat <- make_hand_built_record(BEAUFORT = "two") # not a form as.numeric() reads
  config <- make_hand_built_config(dat, "emptied_column_test")

  expect_warning(prep_survey_data(config), "entirely NA after being read as numbers")
})
