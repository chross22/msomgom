# Spatially and temporally averages environmental covariates onto the
# occupancy model's hex grid, at whatever timescale you ask for - either the
# occupancy model's own season/year windows (so the output slots straight into
# psi/phi/gamma covariate arrays), or arbitrary regular/custom date windows for
# other uses.
#
# Input format matches chross22/datamatch::accessEnvDat()'s return value: an sf
# POINT object with one row per (grid-point, day), columns for each covariate
# variable plus YEAR/MONTH/DAY. No hard dependency on the datamatch package
# itself - load_covariate_netcdf() below builds the same shape directly from a
# folder of daily NetCDF files, for when you already have local files instead
# of calling accessEnvDat() to fetch them.
#
# Typical use, tied to an occupancy-model config:
#   source("load_config.R"); source("average_covariates.R")
#   config <- load_config("configs/bof_riwh.yaml")
#   env_dat <- load_covariate_netcdf("data/covariates/sst", var_names = "sst")
#   windows <- season_windows_from_config(config)
#   sst_avg <- average_covariates(env_dat, area_grid_sf, windows)
#   # sst_avg$sst is a [num_cells x num_ssn] matrix - same num_ssn indexing
#   # jagsPrep.R's effort3d/jday3d/bft3d already use, so it reshapes into a
#   # [site, season, year] array the same way (see jags.R's dets4d/bft4d/etc.)
#
# Arbitrary timescale, independent of any occupancy config:
#   windows <- regular_windows("2018-01-01", "2020-12-31", by = "1 month")
#   sst_avg <- average_covariates(env_dat, area_grid_sf, windows)

# --- window builders -----------------------------------------------------

# one window per (season, year) combination already defined in an occupancy
# config, using the same absolute season numbering (1:num_ssn) as
# jagsPrep.R's detection-covariate arrays, so results line up column-for-column.
season_windows_from_config <- function(config) {
  season <- makeSeasons(config$dates$beg_year, config$dates$end_year, config$ssn_beg, config$ssn_end)
  data.frame(
    ssn_no = season$SSN_NO,
    year = season$Y,
    season_in_year = season$SSN_GRPD_NO,
    start_date = as.Date(paste(season$Y, season$M_BEG, season$D_BEG, sep = "-")),
    end_date = as.Date(paste(season$Y, season$M_END, season$D_END, sep = "-")),
    label = paste0("ssn", season$SSN_NO)
  )
}

# fixed-interval windows over an arbitrary date range, e.g. by = "1 month",
# "1 week", "1 year", "10 days" (anything base::seq.Date() accepts)
regular_windows <- function(start_date, end_date, by = "1 month") {
  start_date <- as.Date(start_date)
  end_date <- as.Date(end_date)
  breaks <- seq(start_date, end_date, by = by)
  if (breaks[length(breaks)] < end_date) breaks <- c(breaks, end_date + 1)
  data.frame(
    ssn_no = seq_len(length(breaks) - 1),
    start_date = breaks[-length(breaks)],
    end_date = breaks[-1] - 1,
    label = format(breaks[-length(breaks)], "%Y-%m-%d")
  )
}

# --- loading covariate data -----------------------------------------------

# reads a folder of covariate NetCDF files (one file per day, or one file with
# a daily time dimension - both are handled) into the same sf-point-per-day
# shape datamatch::accessEnvDat() returns: columns x, y, <one column per
# variable>, YEAR, MONTH, DAY, geometry.
#
# Date is read from each raster layer's time dimension when the file has one
# (the normal case for Copernicus NetCDFs); otherwise it's parsed from the
# filename, which must contain a YYYY-MM-DD or YYYYMMDD date.
load_covariate_netcdf <- function(nc_dir, var_names = NULL, pattern = "\\.nc$") {
  if (!requireNamespace("terra", quietly = TRUE)) {
    stop("The 'terra' package is required. Install it with install.packages('terra').")
  }
  if (!requireNamespace("sf", quietly = TRUE)) {
    stop("The 'sf' package is required. Install it with install.packages('sf').")
  }

  files <- list.files(nc_dir, pattern = pattern, full.names = TRUE)
  if (length(files) == 0) stop("No files matching '", pattern, "' found in ", nc_dir)

  rows <- vector("list", length(files))
  for (i in seq_along(files)) {
    r <- terra::rast(files[i])
    if (!is.null(var_names)) {
      names(r) <- rep_len(var_names, terra::nlyr(r))[seq_len(terra::nlyr(r))]
    }

    layer_dates <- tryCatch(as.Date(terra::time(r)), error = function(e) rep(as.Date(NA), terra::nlyr(r)))
    if (all(is.na(layer_dates))) {
      layer_dates <- rep(parse_date_from_filename(files[i]), terra::nlyr(r))
    }

    df <- as.data.frame(r, xy = TRUE)
    df$DATE <- layer_dates[seq_len(nrow(df))]
    df$YEAR <- as.numeric(format(df$DATE, "%Y"))
    df$MONTH <- as.numeric(format(df$DATE, "%m"))
    df$DAY <- as.numeric(format(df$DATE, "%d"))
    df$DATE <- NULL
    rows[[i]] <- df
  }

  covars <- do.call(rbind, rows)
  sf::st_as_sf(covars, coords = c("x", "y"), crs = sf::st_crs(4326))
}

parse_date_from_filename <- function(path) {
  fname <- basename(path)
  m <- regmatches(fname, regexpr("\\d{4}-\\d{2}-\\d{2}", fname))
  if (length(m) == 0 || m == "") {
    m <- regmatches(fname, regexpr("\\d{8}", fname))
    if (length(m) == 0 || m == "") {
      stop("Could not parse a date from filename '", fname, "'; either give files a YYYY-MM-DD/YYYYMMDD date, ",
           "or use NetCDF files with a proper time dimension terra::time() can read.")
    }
    return(as.Date(m, format = "%Y%m%d"))
  }
  as.Date(m, format = "%Y-%m-%d")
}

# --- averaging -------------------------------------------------------------

# averages every variable column in env_dat over each grid cell x window
# combination. env_dat must have YEAR/MONTH/DAY columns and point geometry
# (as returned by load_covariate_netcdf() or datamatch::accessEnvDat());
# area_grid_sf must have a grid_id column (e.g. arrays$area_grid_sf from a
# prior build_detection_arrays() call, so the grid matches exactly).
#
# Returns a named list of [num_cells x nrow(windows)] matrices, one per
# covariate variable, with columns ordered/labeled to match windows$label
# (windows$ssn_no if you used season_windows_from_config(), so column t lines
# up with year t / absolute season index t elsewhere in this pipeline).
average_covariates <- function(env_dat, area_grid_sf, windows, vars = NULL) {
  library(sf)
  library(dplyr)

  if (is.null(vars)) {
    non_var_cols <- c("YEAR", "MONTH", "DAY", attr(env_dat, "sf_column"))
    vars <- setdiff(names(env_dat), non_var_cols)
  }

  env_dat <- sf::st_transform(env_dat, sf::st_crs(area_grid_sf))
  num_cells <- nrow(area_grid_sf)

  out <- lapply(vars, function(v) {
    m <- matrix(NA_real_, nrow = num_cells, ncol = nrow(windows), dimnames = list(NULL, windows$label))
    m
  })
  names(out) <- vars

  env_date <- as.Date(with(env_dat, paste(YEAR, MONTH, DAY, sep = "-")))

  for (w in seq_len(nrow(windows))) {
    in_window <- which(env_date >= windows$start_date[w] & env_date <= windows$end_date[w])
    if (length(in_window) == 0) next

    pts <- env_dat[in_window, ]
    pts$grid_id <- as.integer(sf::st_join(pts, area_grid_sf["grid_id"], join = sf::st_intersects)$grid_id)
    pts <- sf::st_drop_geometry(pts)
    pts <- pts[!is.na(pts$grid_id), ]
    if (nrow(pts) == 0) next

    for (v in vars) {
      cell_means <- pts %>%
        group_by(grid_id) %>%
        summarise(mean_val = mean(.data[[v]], na.rm = TRUE), .groups = "drop")
      out[[v]][cell_means$grid_id, w] <- cell_means$mean_val
    }
  }

  out
}
