test_that("regular_windows builds non-overlapping consecutive monthly windows", {
  windows <- regular_windows("2018-01-01", "2018-03-31", by = "1 month")

  expect_equal(nrow(windows), 3)
  expect_equal(windows$start_date, as.Date(c("2018-01-01", "2018-02-01", "2018-03-01")))
  expect_equal(windows$end_date, as.Date(c("2018-01-31", "2018-02-28", "2018-03-31")))
  # consecutive, no gaps or overlaps
  expect_equal(windows$end_date[-nrow(windows)] + 1, windows$start_date[-1])
})

test_that("regular_windows ssn_no is a sequential index matching row order", {
  windows <- regular_windows("2018-01-01", "2018-06-30", by = "1 month")
  expect_equal(windows$ssn_no, seq_len(nrow(windows)))
})

test_that("season_windows_from_config produces one window per year x season, matching makeSeasons", {
  config <- list(
    dates = list(beg_year = 2020, end_year = 2021),
    ssn_beg = rbind(c(8, 1), c(9, 1)),
    ssn_end = rbind(c(8, 31), c(9, 30))
  )
  windows <- season_windows_from_config(config)

  expect_equal(nrow(windows), 4)
  expect_equal(windows$ssn_no, 1:4)
  expect_equal(windows$year, c(2020, 2020, 2021, 2021))
  expect_equal(windows$season_in_year, c(1, 2, 1, 2))
  expect_equal(windows$start_date, as.Date(c("2020-08-01", "2020-09-01", "2021-08-01", "2021-09-01")))
  expect_equal(windows$end_date, as.Date(c("2020-08-31", "2020-09-30", "2021-08-31", "2021-09-30")))
  expect_equal(windows$label, paste0("ssn", 1:4))
})

test_that("parse_date_from_filename reads YYYY-MM-DD and YYYYMMDD", {
  expect_equal(parse_date_from_filename("sst_2020-03-15.nc"), as.Date("2020-03-15"))
  expect_equal(parse_date_from_filename("/some/path/sst_20200315.nc"), as.Date("2020-03-15"))
})

test_that("parse_date_from_filename errors clearly when no date is present", {
  expect_error(parse_date_from_filename("sst_no_date.nc"), "Could not parse a date")
})
