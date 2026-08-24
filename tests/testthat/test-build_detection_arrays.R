skip_if_not_installed("sf")
skip_if_not_installed("sfheaders")

make_arrays <- function() {
  configs_dir <- withr::local_tempdir(.local_envir = parent.frame())
  project_dir <- withr::local_tempdir(.local_envir = parent.frame())
  path <- generate_config(
    "grid_test", configs_dir = configs_dir, project_dir = project_dir,
    data_file = "data/mock.csv",
    beg_year = 2018, end_year = 2018, beg_month = 8, end_month = 9
  )
  generate_mock_data(path, surveys_per_season = 3, points_per_survey = 8, seed = 5)
  config <- load_config(path)
  prep <- prep_survey_data(config)
  list(arrays = build_detection_arrays(prep$tmpdat, prep$season_info, config), config = config)
}

test_that("build_detection_arrays returns arrays shaped consistently with the grid", {
  res <- make_arrays()
  arrays <- res$arrays

  expect_true(arrays$num_cells > 0)
  expect_equal(nrow(arrays$area_grid_sf), arrays$num_cells)
  expect_true("grid_id" %in% names(arrays$area_grid_sf))

  expect_equal(dim(arrays$effort3d)[1], arrays$num_cells)
  expect_equal(dim(arrays$effort3d)[3], arrays$num_ssn)
  expect_equal(dim(arrays$jday3d), dim(arrays$effort3d))
  expect_equal(dim(arrays$bft3d), dim(arrays$effort3d))
})

test_that("one species detection array is built per configured species code", {
  res <- make_arrays()
  expect_setequal(names(res$arrays$species_arrays), unlist(res$config$species$codes))
})

test_that("reps (repeat-visit counts) is a season x site matrix with only non-negative integers", {
  res <- make_arrays()
  arrays <- res$arrays

  expect_equal(dim(arrays$reps), c(arrays$num_ssn, arrays$num_cells))
  expect_true(all(arrays$reps >= 0))
})

test_that("max_survs is at least 1 and matches the species array's visit dimension", {
  res <- make_arrays()
  arrays <- res$arrays
  species_code <- res$config$species$active

  expect_gte(arrays$max_survs, 1)
  expect_equal(dim(arrays$species_arrays[[species_code]])[2], arrays$max_survs + 1)
})

test_that("a FILEID spanning more than one day errors naming the file and its dates", {
  configs_dir <- withr::local_tempdir()
  project_dir <- withr::local_tempdir()
  path <- generate_config(
    "multiday_test", configs_dir = configs_dir, project_dir = project_dir,
    data_file = "data/mock.csv",
    beg_year = 2018, end_year = 2018, beg_month = 8, end_month = 9
  )
  generate_mock_data(path, surveys_per_season = 3, points_per_survey = 8, seed = 5)
  config <- load_config(path)
  prep <- prep_survey_data(config)

  # relabel one survey's records as a second day of the survey before it, so a
  # single FILEID covers two calendar days - the multi-day file convention this
  # pipeline's one-FILEID-is-one-survey replicate structure can't represent
  fids <- unique(prep$tmpdat$FILEID)
  moved <- prep$tmpdat$FILEID == fids[2]
  prep$tmpdat$FILEID[moved] <- fids[1]

  expect_error(build_detection_arrays(prep$tmpdat, prep$season_info, config),
               paste0("FILEID '", fids[1], "'.*spans 2 calendar days"))
})

# The prep output itself, before any array is built - what the two guards
# below are handed in the real failure.
make_prep <- function() {
  configs_dir <- withr::local_tempdir(.local_envir = parent.frame())
  project_dir <- withr::local_tempdir(.local_envir = parent.frame())
  path <- generate_config(
    "guard_test", configs_dir = configs_dir, project_dir = project_dir,
    data_file = "data/mock.csv",
    beg_year = 2018, end_year = 2018, beg_month = 8, end_month = 9
  )
  generate_mock_data(path, surveys_per_season = 3, points_per_survey = 8, seed = 5)
  config <- load_config(path)
  list(prep = prep_survey_data(config), config = config)
}

test_that("an empty prep result is refused by name, not by a split failure", {
  # The real-world path: a config whose filters describe a different survey.
  # Before this guard the failure was "Not compatible with STRSXP: [type=NULL]"
  # from inside a split, which named neither the cause nor the fix.
  res <- make_prep()
  empty <- res$prep$tmpdat[0, , drop = FALSE]

  expect_error(build_detection_arrays(empty, res$prep$season_info, res$config),
               "No survey records to build arrays from")
})

test_that("records that all fall off-effort are refused by name", {
  res <- make_prep()
  off <- res$prep$tmpdat
  off$on.off.eff <- 0

  expect_error(build_detection_arrays(off, res$prep$season_info, res$config),
               "none are on-effort")
})

test_that("a season nothing surveyed builds as unobserved, not as a crash", {
  # The 1:0 bug: a season with zero surveys ran the survey loop with j = 1 on
  # an empty season_ufids, and the NA FILEID it indexed out surfaced as
  # "FILEID 'NA' spans 0 calendar days".
  res <- make_prep()
  tmp <- res$prep$tmpdat[res$prep$tmpdat$season != 1, , drop = FALSE]

  expect_message(
    arrays <- build_detection_arrays(tmp, res$prep$season_info, res$config),
    "season 1: 0 survey"
  )
  expect_equal(unname(arrays$reps[1, ]), rep(0, arrays$num_cells))
  expect_true(any(arrays$reps[2, ] > 0)) # the surveyed season is untouched

  # and the season reads as unsurveyed downstream, not as detections of zero
  pdf(NULL); on.exit(dev.off())
  state <- plot_detection_history(arrays, res$config$species$active)
  expect_true(all(is.na(state[, 1])))
})
