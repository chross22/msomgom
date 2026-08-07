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
