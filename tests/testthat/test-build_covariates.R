skip_if_not_installed("sf")
skip_if_not_installed("terra")

# A config with a study area and date range, but no survey data needed: the
# covariate stage only reads dates, the polygon, and the covariates block.
make_covariate_config <- function(psi = character(0), sources = list()) {
  list(
    dates = list(beg_year = 2020, end_year = 2020, beg_month = 1, end_month = 1),
    study_area = list(polygon_matrix = rbind(c(0, 0), c(2, 0), c(2, 1), c(0, 1), c(0, 0))),
    covariates = list(psi = psi, phi = character(0), gamma = character(0),
                      sources = sources)
  )
}

make_grid <- function() {
  cells <- sf::st_sfc(
    sf::st_polygon(list(rbind(c(0, 0), c(1, 0), c(1, 1), c(0, 1), c(0, 0)))),
    sf::st_polygon(list(rbind(c(1, 0), c(2, 0), c(2, 1), c(1, 1), c(1, 0)))),
    crs = 4326
  )
  sf::st_sf(grid_id = 1:2, geometry = cells)
}

# A folder of dated rasters, so a recipe can be run end to end offline via
# dynocc's own load_covariate_netcdf() as the source function.
make_raster_dir <- function(env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  r <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 2, ymin = 0, ymax = 1)
  terra::values(r) <- c(10, 20, 30, 40)
  terra::writeRaster(r, file.path(dir, "sst_2020-01-05.tif"), overwrite = TRUE)
  terra::writeRaster(r, file.path(dir, "sst_2020-01-06.tif"), overwrite = TRUE)
  dir
}

jan_windows <- function() {
  data.frame(start_date = as.Date("2020-01-01"),
             end_date = as.Date("2020-01-31"), label = "jan")
}

test_that("a recipe naming a source function is run and averaged onto the grid", {
  dir <- make_raster_dir()
  config <- make_covariate_config(
    psi = "sst",
    sources = list(sst = list(
      fn = "load_covariate_netcdf",
      args = list(nc_dir = dir, var_names = "sst", pattern = "\\.tif$")
    ))
  )

  out <- build_covariates(config, make_grid(), windows = jan_windows())

  expect_named(out, "sst")
  expect_equal(dim(out$sst), c(2, 1))
  expect_false(anyNA(out$sst))
})

test_that("no configured covariates means no covariate stage at all", {
  expect_null(build_covariates(make_covariate_config(), make_grid()))
})

test_that("a covariate configured with no source at all says so", {
  config <- make_covariate_config(psi = "sst")
  expect_error(build_covariates(config, make_grid()), "covariates.sources is empty")
})

test_that("a process naming a column no recipe produces errors with both sides", {
  dir <- make_raster_dir()
  config <- make_covariate_config(
    psi = "chl", # nothing produces this
    sources = list(sst = list(
      fn = "load_covariate_netcdf",
      args = list(nc_dir = dir, var_names = "sst", pattern = "\\.tif$")
    ))
  )

  expect_error(build_covariates(config, make_grid(), windows = jan_windows()),
               "chl.*Built: sst")
})

test_that("two sources producing the same column is an error, not a silent win", {
  dir <- make_raster_dir()
  recipe <- list(fn = "load_covariate_netcdf",
                 args = list(nc_dir = dir, var_names = "sst", pattern = "\\.tif$"))
  config <- make_covariate_config(psi = "sst", sources = list(a = recipe, b = recipe))

  expect_error(build_covariates(config, make_grid(), windows = jan_windows()),
               "already produced")
})

test_that("resolve_covariate_fn reaches every allowed package and refuses the rest", {
  expect_identical(resolve_covariate_fn("load_covariate_netcdf"), load_covariate_netcdf)
  skip_if_not_installed("derivoce")
  expect_identical(resolve_covariate_fn("horizontal_gradient"),
                   derivoce::horizontal_gradient)
})

test_that("a config naming something that isn't a covariate function is refused", {
  # the point of the allowlist: a config file is data, not code
  expect_error(resolve_covariate_fn("system"), "not an exported function")
  expect_error(resolve_covariate_fn("no_such_covariate_fn"), "not an exported function")
})

test_that("years/months/bounding_box are filled from the config when the function takes them", {
  config <- make_covariate_config()
  fn <- function(vars, years = NULL, months = NULL, bounding_box) NULL

  args <- fill_covariate_args(fn, list(vars = "SST"), config)

  expect_equal(args$years, 2020)
  expect_equal(args$months, 1)
  expect_equal(args$bounding_box, list(xmin = 0, xmax = 2, ymin = 0, ymax = 1))
  expect_equal(args$vars, "SST")
})

test_that("an explicit argument wins over the implied one", {
  config <- make_covariate_config()
  fn <- function(vars, years = NULL, months = NULL, bounding_box) NULL

  args <- fill_covariate_args(fn, list(vars = "SST", months = 6:8), config)
  expect_equal(args$months, 6:8)
})

test_that("nothing is invented for a function that has no such formal", {
  config <- make_covariate_config()
  fn <- function(env_dat, vars = NULL) NULL

  args <- fill_covariate_args(fn, list(vars = "SST"), config)
  expect_named(args, "vars")
})

test_that("a misspelled argument is refused rather than silently dropped", {
  config <- make_covariate_config()
  fn <- function(env_dat, vars = NULL) NULL

  expect_error(fill_covariate_args(fn, list(varz = "SST"), config), "varz")
})

test_that("derive steps run in order, each on what the last produced", {
  dir <- make_raster_dir()
  # two derive steps, written both ways the config allows: a bare string and
  # a fn/args entry. Each adds a column the next can see.
  add_one <- function(env_dat) { env_dat$step1 <- 1; env_dat }
  add_two <- function(env_dat, mult = 1) { env_dat$step2 <- env_dat$step1 * mult; env_dat }

  local_mocked_bindings(
    resolve_covariate_fn = function(fn, what = "source") {
      switch(fn, add_one = add_one, add_two = add_two,
             load_covariate_netcdf = load_covariate_netcdf)
    }
  )

  recipe <- list(
    fn = "load_covariate_netcdf",
    args = list(nc_dir = dir, var_names = "sst", pattern = "\\.tif$"),
    derive = list("add_one", list(fn = "add_two", args = list(mult = 5)))
  )
  env_dat <- run_covariate_recipe(recipe, make_covariate_config())

  expect_equal(unique(env_dat$step1), 1)
  expect_equal(unique(env_dat$step2), 5)
})

test_that("a source with no fn names the recipe that is missing it", {
  config <- make_covariate_config()
  expect_error(run_covariate_recipe(list(args = list()), config, name = "ocean"),
               "'ocean' has no `fn`")
})

test_that("a derive step taking `bathy` has one fetched for the study area", {
  config <- make_covariate_config()
  fetched <- NULL
  # the injection must be lazy: a function with no `bathy` formal must not
  # trigger a bathymetry download at all
  testthat::local_mocked_bindings(
    study_area_bbox = function(cfg) list(xmin = 0, xmax = 2, ymin = 0, ymax = 1)
  )

  no_bathy <- function(env_dat, vars = NULL) NULL
  args <- fill_covariate_args(no_bathy, list(vars = "SST"), config)
  expect_named(args, "vars")
  expect_false("bathy" %in% names(args))
})

test_that("a derive step's arguments are filled and typo-checked like a source's", {
  config <- make_covariate_config()
  fn <- function(env_dat, vars = NULL, bounding_box = NULL) NULL

  args <- fill_covariate_args(fn, list(vars = "DEPTH"), config)
  expect_equal(args$bounding_box, list(xmin = 0, xmax = 2, ymin = 0, ymax = 1))

  expect_error(fill_covariate_args(fn, list(varz = "DEPTH"), config), "varz")
})
