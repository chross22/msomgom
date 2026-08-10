test_that("exact canonical names are left untouched", {
  dat <- data.frame(EVENTNO = 1, LATITUDE = 2, ALT = 750)
  out <- standardize_survey_columns(dat)
  expect_equal(names(out), c("EVENTNO", "LATITUDE", "ALT"))
})

test_that("case-insensitive and alias matches are renamed to the canonical name", {
  dat <- data.frame(Event = 1, lat = 2, Long = 3, ALT = 750)
  out <- standardize_survey_columns(dat)
  expect_true(all(c("EVENTNO", "LATITUDE", "LONGITUDE") %in% names(out)))
})

test_that("punctuation/spacing in a real-world header still matches", {
  dat <- data.frame("Event No." = 1, "Sp. Code" = "RIWH", ALT = 750, check.names = FALSE)
  out <- standardize_survey_columns(dat)
  expect_true("EVENTNO" %in% names(out))
  expect_true("SPECCODE" %in% names(out))
})

test_that("an ambiguous match warns and uses the first candidate, not silently picking one", {
  dat <- data.frame(Event = 1, EventNum = 2, ALT = 750)
  expect_warning(out <- standardize_survey_columns(dat), "Multiple columns look like 'EVENTNO'")
  expect_equal(sum(names(out) == "EVENTNO"), 1)
})

test_that("ALT missing entirely warns and is filled with the default", {
  dat <- data.frame(EVENTNO = 1:3)
  expect_warning(out <- standardize_survey_columns(dat), "ALT column not found")
  expect_equal(out$ALT, rep(750, 3))
})

test_that("alt_default overrides the fallback value", {
  dat <- data.frame(EVENTNO = 1)
  expect_warning(out <- standardize_survey_columns(dat, alt_default = 500))
  expect_equal(out$ALT, 500)
})

test_that("ALT found by alias matching is used as-is, no default/warning", {
  dat <- data.frame(EVENTNO = 1, Altitude = 300)
  expect_no_warning(out <- standardize_survey_columns(dat))
  expect_equal(out$ALT, 300)
})

# End-to-end through prep_survey_data(), with a hand-built CSV using
# real-world-style column names instead of the exact NARWC ones.
skip_if_not_installed("dplyr")

test_that("prep_survey_data reads a CSV with non-canonical column names via alias matching", {
  configs_dir <- withr::local_tempdir(.local_envir = parent.frame())
  project_dir <- withr::local_tempdir(.local_envir = parent.frame())
  data_dir <- file.path(project_dir, "data")
  dir.create(data_dir, recursive = TRUE)

  # same record as make_hand_built_record() elsewhere in the suite, but with
  # real-world-style header variants and no ALT column at all
  dat <- data.frame(
    FileID = "P1001a", Event = 1, PLATFORM = 99,
    MONTH = 8, DAY = 10, YEAR = 2018, GMT = 120000,
    Lat = 44.6, Long = -66.4,
    LEGTYPE = 5, LEGSTAGE = 1,
    HEADING = 0, WX = "C", CLOUD = 1,
    Visibility = 3, BEAUFORT = 2,
    Species = NA, IDREL = NA, NUMBER = NA, CONFIDNC = NA,
    check.names = FALSE
  )
  data_file <- file.path(data_dir, "survey.csv")
  write.csv(dat, data_file, row.names = FALSE, na = "")

  path <- generate_config(
    "alias_test", configs_dir = configs_dir, project_dir = project_dir,
    data_file = "data/survey.csv",
    beg_year = 2018, end_year = 2018, beg_month = 8, end_month = 9
  )
  config <- load_config(path)

  expect_warning(prep <- prep_survey_data(config), "ALT column not found")
  expect_equal(nrow(prep$dat), 1)
  expect_equal(prep$dat$ALT, 750)
  expect_equal(prep$dat$LATITUDE, 44.6)
})

test_that("prep_survey_data errors clearly when a required column can't be matched at all", {
  configs_dir <- withr::local_tempdir(.local_envir = parent.frame())
  project_dir <- withr::local_tempdir(.local_envir = parent.frame())
  data_dir <- file.path(project_dir, "data")
  dir.create(data_dir, recursive = TRUE)

  # no column anywhere close to SPECCODE
  dat <- data.frame(
    FILEID = "P1001a", EVENTNO = 1, PLATFORM = 99,
    MONTH = 8, DAY = 10, YEAR = 2018, GMT = 120000,
    LATITUDE = 44.6, LONGITUDE = -66.4,
    LEGTYPE = 5, LEGSTAGE = 1, ALT = 750,
    HEADING = 0, WX = "C", CLOUD = 1,
    VISIBLTY = 3, BEAUFORT = 2,
    IDREL = NA, NUMBER = NA, CONFIDNC = NA
  )
  data_file <- file.path(data_dir, "survey.csv")
  write.csv(dat, data_file, row.names = FALSE, na = "")

  path <- generate_config(
    "missing_col_test", configs_dir = configs_dir, project_dir = project_dir,
    data_file = "data/survey.csv",
    beg_year = 2018, end_year = 2018, beg_month = 8, end_month = 9
  )
  config <- load_config(path)

  expect_error(prep_survey_data(config), "SPECCODE")
})

test_that("the vocabulary shared with distsamp is recognised here too", {
  # These aliases came across from distsamp::narwc_schema()$aliases. The two
  # tables are synced by hand, so this test is what catches them drifting.
  dat <- data.frame(
    FileID = "A", Event = 1, LAT_DD = 43, LONG_DD = -69,
    LEGTYPE_BK = 2, Visiblity = 5, GroupSize = 3, ALT = 750,
    check.names = FALSE
  )
  out <- standardize_survey_columns(dat)
  expect_true(all(c("FILEID", "EVENTNO", "LATITUDE", "LONGITUDE", "LEGTYPE",
                    "VISIBLTY", "NUMBER") %in% names(out)))
})

test_that("a zone-named time column still lands on GMT, not TIME", {
  # distsamp standardises time to TIME; this pipeline reads GMT throughout
  # (data_prep.R, padstr0.R). Sharing the vocabulary must not import that.
  for (nm in c("TIME_UTC", "Time_Loc", "UTC")) {
    dat <- data.frame(EVENTNO = 1, ALT = 750, check.names = FALSE)
    dat[[nm]] <- 120000
    out <- standardize_survey_columns(dat)
    expect_true("GMT" %in% names(out), info = nm)
    expect_false("TIME" %in% names(out), info = nm)
  }
})
