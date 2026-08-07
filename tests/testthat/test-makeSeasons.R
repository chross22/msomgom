test_that("makeSeasons builds one row per year x season combination", {
  season <- makeSeasons(2020, 2021, rbind(c(8, 1), c(9, 1)), rbind(c(8, 31), c(9, 30)))

  expect_equal(nrow(season), 4) # 2 years x 2 seasons
  expect_equal(names(season), c("Y", "M_BEG", "D_BEG", "M_END", "D_END", "JDAY_BEG", "JDAY_END", "SSN_NO", "SSN_GRPD_NO"))
})

test_that("SSN_NO is a unique running index across all year x season combinations", {
  season <- makeSeasons(2020, 2021, rbind(c(8, 1), c(9, 1)), rbind(c(8, 31), c(9, 30)))
  expect_equal(season$SSN_NO, 1:4)
})

test_that("SSN_GRPD_NO restarts each year (index within year)", {
  season <- makeSeasons(2020, 2021, rbind(c(8, 1), c(9, 1)), rbind(c(8, 31), c(9, 30)))
  expect_equal(season$SSN_GRPD_NO, c(1, 2, 1, 2))
})

test_that("year/month/day columns and day-of-year are correct", {
  season <- makeSeasons(2020, 2020, rbind(c(8, 1)), rbind(c(8, 31)))
  expect_equal(season$Y, 2020)
  expect_equal(season$M_BEG, 8)
  expect_equal(season$D_BEG, 1)
  expect_equal(season$M_END, 8)
  expect_equal(season$D_END, 31)
  # Aug 1 2020 is day-of-year 214 (2020 is a leap year); Aug 31 is 244
  expect_equal(season$JDAY_BEG, 214)
  expect_equal(season$JDAY_END, 244)
})

test_that("a single year x single season works", {
  season <- makeSeasons(2020, 2020, rbind(c(1, 1)), rbind(c(12, 31)))
  expect_equal(nrow(season), 1)
  expect_equal(season$SSN_NO, 1)
})
