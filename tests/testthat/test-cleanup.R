test_that("cleanup_outputs removes the data file and figs/ directory", {
  data_file <- withr::local_tempfile(fileext = ".csv", .local_envir = parent.frame())
  writeLines("a,b\n1,2", data_file)
  output_dir <- withr::local_tempdir(.local_envir = parent.frame())
  dir.create(file.path(output_dir, "figs"), recursive = TRUE)

  config <- list(paths = list(data_file = data_file, output_dir = output_dir))
  cleanup_outputs(config)

  expect_false(file.exists(data_file))
  expect_false(dir.exists(file.path(output_dir, "figs")))
})

test_that("cleanup_outputs doesn't error when there's nothing to clean up", {
  output_dir <- withr::local_tempdir(.local_envir = parent.frame())
  config <- list(paths = list(data_file = file.path(output_dir, "does_not_exist.csv"), output_dir = output_dir))
  expect_no_error(cleanup_outputs(config))
})

test_that("cleanup_outputs returns NULL invisibly", {
  output_dir <- withr::local_tempdir(.local_envir = parent.frame())
  config <- list(paths = list(data_file = file.path(output_dir, "nope.csv"), output_dir = output_dir))
  expect_null(withVisible(cleanup_outputs(config))$value)
  expect_false(withVisible(cleanup_outputs(config))$visible)
})
