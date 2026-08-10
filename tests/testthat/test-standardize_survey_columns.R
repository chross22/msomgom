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
  # distsamp::standardize_narwc_columns() (the first pass) may resolve this
  # ambiguity itself with its own message before this package's own
  # ambiguity-warning path ever gets a chance to - either way, a warning is
  # expected and exactly one column should end up named EVENTNO.
  dat <- data.frame(Event = 1, EventNum = 2, ALT = 750)
  expect_warning(out <- standardize_survey_columns(dat))
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

test_that("generic substring fallback matches a column not in the alias list at all", {
  # neither name is an exact alias - "sightingeventnum"/"surveyaltft" only
  # match because they *contain* "eventnum"/"alt" as substrings
  dat <- data.frame(Sighting_Event_Num = 1, Survey_Alt_ft = 300, check.names = FALSE)
  out <- standardize_survey_columns(dat)
  expect_true("EVENTNO" %in% names(out))
  expect_true("ALT" %in% names(out))
  expect_equal(out$ALT, 300) # matched via substring, not defaulted
})

test_that("substring fallback still applies the ambiguity warning when several columns qualify", {
  dat <- data.frame(Boat_Alt = 1, Plane_Alt = 2, EVENTNO = 3)
  expect_warning(out <- standardize_survey_columns(dat), "Multiple columns look like 'ALT'")
  expect_equal(sum(names(out) == "ALT"), 1)
})

test_that("YEAR/MONTH/DAY are derived from a combined date column when missing", {
  # TIME is also missing here, so it gets derived too (message says
  # "YEAR/MONTH/DAY/TIME") - only the derived values are asserted, since
  # pinning the exact message text couples the test to which parts happened
  # to already be present, not to what this test actually cares about.
  dat <- data.frame(EVENTNO = 1:2, Date = c("2024-08-15", "2025-01-03"), ALT = 750)
  expect_message(out <- standardize_survey_columns(dat), "Derived.*from 'Date'")
  expect_equal(out$YEAR, c(2024, 2025))
  expect_equal(out$MONTH, c(8, 1))
  expect_equal(out$DAY, c(15, 3))
})

test_that("TIME is also derived from a combined datetime column when missing", {
  dat <- data.frame(EVENTNO = 1, SurveyDateTime = "2024-08-15 14:30:00", ALT = 750, check.names = FALSE)
  out <- standardize_survey_columns(dat)
  expect_equal(out$YEAR, 2024)
  expect_equal(out$TIME, 143000)
})

test_that("existing YEAR/MONTH/DAY/TIME columns are left alone, not overwritten by a date column", {
  dat <- data.frame(EVENTNO = 1, YEAR = 1999, MONTH = 6, DAY = 20, TIME = 90000,
                     Date = "2024-08-15", ALT = 750)
  expect_no_message(out <- standardize_survey_columns(dat))
  expect_equal(out$YEAR, 1999)
  expect_equal(out$TIME, 90000)
})

test_that("a date value that can't be parsed becomes NA with a warning naming the count", {
  dat <- data.frame(EVENTNO = 1:3, Date = c("2024-08-15", "not a date", NA), ALT = 750)
  expect_warning(out <- standardize_survey_columns(dat), "1 value.*couldn't be parsed")
  expect_equal(out$YEAR, c(2024, NA, NA))
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
    MONTH = 8, DAY = 10, YEAR = 2018, TIME = 120000,
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
    MONTH = 8, DAY = 10, YEAR = 2018, TIME = 120000,
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

test_that("a zone-named time column lands on TIME", {
  # This pipeline used to call the column GMT. Both packages now say TIME, so
  # the two vocabularies line up and data moves between them untranslated.
  for (nm in c("TIME_UTC", "Time_Loc", "UTC", "GMT")) {
    dat <- data.frame(EVENTNO = 1, ALT = 750, check.names = FALSE)
    dat[[nm]] <- 120000
    out <- standardize_survey_columns(dat)
    expect_true("TIME" %in% names(out), info = nm)
    expect_false("GMT" %in% names(out), info = nm)
  }
})

test_that("the substring fallback matches what an exact alias would not", {
  # This pipeline is willing to guess from a substring where distsamp refuses
  # to; that difference in appetite is deliberate on both sides.
  dat <- data.frame(EVENTNO = 1, Survey_Alt_ft = 300, check.names = FALSE)
  expect_no_warning(out <- standardize_survey_columns(dat))
  expect_equal(out$ALT, 300)
})
