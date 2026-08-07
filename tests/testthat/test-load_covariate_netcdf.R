skip_if_not_installed("terra")
skip_if_not_installed("sf")

test_that("load_covariate_netcdf reads a folder of single-day raster files, using the filename date fallback", {
  nc_dir <- withr::local_tempdir(.local_envir = parent.frame())
  r <- terra::rast(nrows = 2, ncols = 2, nlyrs = 1)
  terra::values(r) <- 1:4

  terra::writeRaster(r, file.path(nc_dir, "sst_2020-01-01.tif"), overwrite = TRUE)
  terra::writeRaster(r, file.path(nc_dir, "sst_2020-01-02.tif"), overwrite = TRUE)

  env_dat <- load_covariate_netcdf(nc_dir, var_names = "sst", pattern = "\\.tif$")

  expect_s3_class(env_dat, "sf")
  expect_true(all(c("sst", "YEAR", "MONTH", "DAY") %in% names(env_dat)))
  expect_equal(sort(unique(env_dat$DAY)), c(1, 2))
  expect_equal(unique(env_dat$YEAR), 2020)
  expect_equal(unique(env_dat$MONTH), 1)
  expect_equal(nrow(env_dat), 8) # 4 cells x 2 days
})

test_that("load_covariate_netcdf errors clearly when no files match the pattern", {
  nc_dir <- withr::local_tempdir(.local_envir = parent.frame())
  expect_error(load_covariate_netcdf(nc_dir), "No files matching")
})
