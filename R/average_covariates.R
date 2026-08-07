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

#' Build covariate windows from an occupancy config's seasons
#'
#' One window per (season, year) combination already defined in an occupancy
#' config, using the same absolute season numbering (`1:num_ssn`) as
#' `jagsPrep.R`'s detection-covariate arrays, so results line up
#' column-for-column.
#'
#' @param config a config list, as returned by `load_config()`
#' @return data.frame with columns `ssn_no`, `year`, `season_in_year`,
#'   `start_date`, `end_date`, `label`
#' @seealso [regular_windows()] for windows independent of an occupancy
#'   config; [average_covariates()], which consumes the result
#' @family covariate windows
#' @examples
#' \dontrun{
#' config <- load_config("configs/bof_riwh.yaml")
#' windows <- season_windows_from_config(config)
#' }
#' @export
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

#' Build fixed-interval covariate windows
#'
#' Fixed-interval windows over an arbitrary date range, independent of any
#' occupancy config.
#'
#' @param start_date start of the range (character or Date)
#' @param end_date end of the range (character or Date)
#' @param by interval, e.g. `"1 month"`, `"1 week"`, `"1 year"`, `"10 days"`
#'   (anything `base::seq.Date()` accepts)
#' @return data.frame with columns `ssn_no`, `start_date`, `end_date`, `label`
#' @seealso [season_windows_from_config()] for windows tied to an occupancy
#'   config's own season/year structure; [average_covariates()], which
#'   consumes the result
#' @family covariate windows
#' @examples
#' regular_windows("2018-01-01", "2018-06-30", by = "1 month")
#' @export
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

#' Load a folder of covariate NetCDF files
#'
#' Reads a folder of covariate NetCDF files (one file per day, or one file
#' with a daily time dimension - both are handled) into the same
#' sf-point-per-day shape `datamatch::accessEnvDat()` returns: columns `x`,
#' `y`, one column per variable, `YEAR`, `MONTH`, `DAY`, geometry.
#'
#' Date is read from each raster layer's time dimension when the file has one
#' (the normal case for Copernicus NetCDFs); otherwise it's parsed from the
#' filename, which must contain a `YYYY-MM-DD` or `YYYYMMDD` date (see
#' `parse_date_from_filename()`).
#'
#' @param nc_dir directory containing the NetCDF files
#' @param var_names optional names for the raster layers/variables; if `NULL`,
#'   uses whatever names the NetCDF files themselves carry
#' @param pattern regex to select files within `nc_dir`
#' @return `sf` POINT object with one row per (grid-point, day)
#' @seealso [average_covariates()], which consumes the result;
#'   [parse_date_from_filename()] for the filename-date fallback;
#'   `datamatch::accessEnvDat()` for fetching Copernicus data directly instead
#'   of reading local files
#' @family covariates
#' @examples
#' \dontrun{
#' env_dat <- load_covariate_netcdf("data/covariates/sst", var_names = "sst")
#' }
#' @export
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
    df$DATE <- rep(layer_dates, length.out = nrow(df))
    df$YEAR <- as.numeric(format(df$DATE, "%Y"))
    df$MONTH <- as.numeric(format(df$DATE, "%m"))
    df$DAY <- as.numeric(format(df$DATE, "%d"))
    df$DATE <- NULL
    rows[[i]] <- df
  }

  covars <- do.call(rbind, rows)
  sf::st_as_sf(covars, coords = c("x", "y"), crs = sf::st_crs(4326))
}

#' Parse a date out of a covariate filename
#'
#' Used by `load_covariate_netcdf()` as a fallback when a raster file has no
#' readable time dimension.
#'
#' @param path a file path whose basename contains a `YYYY-MM-DD` or `YYYYMMDD` date
#' @return a `Date`
#' @seealso [load_covariate_netcdf()], which calls this
#' @keywords internal
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

#' Spatially and temporally average covariates onto the occupancy grid
#'
#' Averages every variable column in `env_dat` over each grid cell x window
#' combination.
#'
#' @param env_dat `sf` POINT object with `YEAR`/`MONTH`/`DAY` columns and one
#'   column per covariate variable (as returned by `load_covariate_netcdf()`
#'   or `datamatch::accessEnvDat()`)
#' @param area_grid_sf `sf` polygon grid with a `grid_id` column (e.g.
#'   `arrays$area_grid_sf` from a prior `build_detection_arrays()` call, so
#'   the grid matches exactly)
#' @param windows data.frame with `start_date`/`end_date`/`label` columns
#'   (e.g. from `season_windows_from_config()` or `regular_windows()`)
#' @param vars covariate column names in `env_dat` to average; if `NULL`,
#'   uses every column except `YEAR`/`MONTH`/`DAY`/geometry
#' @return named list of `[num_cells x nrow(windows)]` matrices, one per
#'   covariate variable, with columns ordered/labeled to match `windows$label`
#'   (`windows$ssn_no` if you used `season_windows_from_config()`, so column
#'   `t` lines up with year `t` / absolute season index `t` elsewhere in this
#'   pipeline)
#' @seealso [season_windows_from_config()] and [regular_windows()] for
#'   building `windows`; [load_covariate_netcdf()] for building `env_dat`;
#'   [build_detection_arrays()] for `area_grid_sf`; [fit_occupancy_model()],
#'   which takes this function's output as `occ_covariates`
#' @family covariates
#' @examples
#' \dontrun{
#' config <- load_config("configs/bof_riwh.yaml")
#' prep <- prep_survey_data(config)
#' arrays <- build_detection_arrays(prep$tmpdat, prep$season_info, config)
#'
#' env_dat <- load_covariate_netcdf("data/covariates/sst", var_names = "sst")
#' windows <- season_windows_from_config(config)
#' sst_avg <- average_covariates(env_dat, arrays$area_grid_sf, windows)
#' }
#' @export
average_covariates <- function(env_dat, area_grid_sf, windows, vars = NULL) {
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
      cell_means <- pts |>
        group_by(grid_id) |>
        summarise(mean_val = mean(.data[[v]], na.rm = TRUE), .groups = "drop")
      out[[v]][cell_means$grid_id, w] <- cell_means$mean_val
    }
  }

  out
}
