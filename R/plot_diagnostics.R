#' Map survey coverage across the study grid
#'
#' Plots the number of surveys that covered each grid cell, either summed
#' across every season or for one season alone. Built directly from `reps`
#' (`build_detection_arrays()`'s repeat-visit matrix), so it shows exactly
#' what the model saw as survey effort, not a rederivation from raw data.
#'
#' A cell that's well-covered everywhere but the model still won't converge
#' points at the detection covariates (bft/jday/eff) or too few MCMC
#' iterations; a cell that's unexpectedly blank points at the study-area
#' polygon or grid construction instead.
#'
#' @param arrays the list returned by `build_detection_arrays()`
#' @param season which season (`1:arrays$num_ssn`) to show; `NULL` (the
#'   default) sums coverage across every season
#' @param main plot title; auto-generated from `season` if `NULL`
#' @param ... passed on to `plot()`
#' @return invisibly, `arrays$area_grid_sf` with an `n_surveys` column added
#' @seealso [plot_sightings()], [plot_occupancy_map()], [plot_covariate_map()],
#'   [build_detection_arrays()], which produces `arrays`
#' @family diagnostic plots
#' @examples
#' \dontrun{
#' arrays <- build_detection_arrays(prep$tmpdat, prep$season_info, config)
#' plot_survey_coverage(arrays)
#' plot_survey_coverage(arrays, season = 3)
#' }
#' @export
plot_survey_coverage <- function(arrays, season = NULL, main = NULL, ...) {
  reps <- arrays$reps
  if (!is.null(season)) {
    if (season < 1 || season > nrow(reps)) {
      stop("season must be between 1 and ", nrow(reps), " (arrays$num_ssn).")
    }
    coverage <- reps[season, ]
  } else {
    coverage <- colSums(reps)
  }

  grid <- arrays$area_grid_sf
  grid$n_surveys <- coverage

  if (is.null(main)) {
    main <- if (is.null(season)) "Survey coverage (all seasons)" else paste0("Survey coverage (season ", season, ")")
  }
  plot(grid["n_surveys"], main = main, ...)
  invisible(grid)
}

#' Map sighting counts across the study grid
#'
#' Plots total sighting counts per grid cell for one species, from the
#' detection-history array `build_detection_arrays()` built for it - so this
#' shows exactly what feeds the model, not a rederivation from the raw
#' survey CSV.
#'
#' @param arrays the list returned by `build_detection_arrays()`
#' @param species species code; must be a name in `arrays$species_arrays`
#' @param season which season (`1:arrays$num_ssn`) to show; `NULL` (the
#'   default) sums sightings across every season
#' @param main plot title; auto-generated from `species`/`season` if `NULL`
#' @param ... passed on to `plot()`
#' @return invisibly, `arrays$area_grid_sf` with an `n_sightings` column added
#' @seealso [plot_survey_coverage()], [plot_occupancy_map()], [plot_covariate_map()],
#'   [build_detection_arrays()], which produces `arrays`
#' @family diagnostic plots
#' @examples
#' \dontrun{
#' arrays <- build_detection_arrays(prep$tmpdat, prep$season_info, config)
#' plot_sightings(arrays, "RIWH")
#' plot_sightings(arrays, "RIWH", season = 2)
#' }
#' @export
plot_sightings <- function(arrays, species, season = NULL, main = NULL, ...) {
  if (!(species %in% names(arrays$species_arrays))) {
    stop("species '", species, "' has no detection array; available: ",
         paste(names(arrays$species_arrays), collapse = ", "))
  }

  # column 1 of dim 2 is grid_id, not a survey slot - see build_detection_arrays()
  dets <- arrays$species_arrays[[species]][, -1, , drop = FALSE]

  if (!is.null(season)) {
    if (season < 1 || season > dim(dets)[3]) {
      stop("season must be between 1 and ", dim(dets)[3], " (arrays$num_ssn).")
    }
    counts <- rowSums(dets[, , season, drop = FALSE], na.rm = TRUE)
  } else {
    counts <- apply(dets, 1, sum, na.rm = TRUE)
  }

  grid <- arrays$area_grid_sf
  grid$n_sightings <- counts

  if (is.null(main)) {
    main <- paste0(species, " sightings", if (is.null(season)) " (all seasons)" else paste0(" (season ", season, ")"))
  }
  plot(grid["n_sightings"], main = main, ...)
  invisible(grid)
}

#' Map posterior occupancy probability across the study grid
#'
#' Plots posterior mean occupancy (the latent state `Z`) per grid cell for
#' one year, from a fit run with `Z` tracked (`jags_params = "Z"` in the
#' config, or `pars = "Z"`). `evaluate_occupancy_model()`'s
#' `compare_naive_vs_modeled_occupancy()` reports the same modeled-occupancy
#' numbers as a per-year table; this puts them on the map instead.
#'
#' @param fit an `mcmc.list` that tracked `Z` (e.g. from
#'   `fit_occupancy_model()`), or a path to a saved `.RData` file containing
#'   one
#' @param arrays the list returned by `build_detection_arrays()` (must be the
#'   same one `fit` was fit against, so sites/grid cells line up)
#' @param year which year to show; defaults to the last year tracked in `fit`
#' @param main plot title; auto-generated from `year` if `NULL`
#' @param ... passed on to `plot()`
#' @return invisibly, `arrays$area_grid_sf` with an `occupancy` column added
#'   (posterior mean `Z` for the chosen year)
#' @seealso [plot_survey_coverage()], [plot_sightings()], [plot_covariate_map()],
#'   [compare_naive_vs_modeled_occupancy()] for the same numbers as a table,
#'   [load_mcmc_list()] for how a saved `.RData` path is resolved
#' @family diagnostic plots
#' @examples
#' \dontrun{
#' fit <- fit_occupancy_model(arrays, config) # config$jags$params must be "Z"
#' plot_occupancy_map(fit, arrays)
#' plot_occupancy_map(fit, arrays, year = 2)
#' }
#' @export
plot_occupancy_map <- function(fit, arrays, year = NULL, main = NULL, ...) {
  if (is.character(fit)) {
    fit <- load_mcmc_list(fit)
  }
  if (!inherits(fit, "mcmc.list")) {
    stop("plot_occupancy_map() expects an mcmc.list (what fit_occupancy_model() ",
         "returns with jags_params = \"Z\"), or a path to a saved .RData file containing one.")
  }

  z_mat <- as.matrix(fit)
  z_cols <- grep("^Z\\[", colnames(z_mat), value = TRUE)
  if (length(z_cols) == 0) {
    stop("fit has no Z[...] columns; re-fit with jags_params = \"Z\" to track occupancy state.")
  }
  idx <- do.call(rbind, lapply(strsplit(sub("^Z\\[", "", sub("\\]$", "", z_cols)), ","), as.integer))
  z_post_mean <- colMeans(z_mat[, z_cols, drop = FALSE])

  years_available <- sort(unique(idx[, 3]))
  if (is.null(year)) {
    year <- max(years_available)
  } else if (!(year %in% years_available)) {
    stop("year must be one of: ", paste(years_available, collapse = ", "))
  }

  year_rows <- which(idx[, 3] == year)
  occ_by_site <- setNames(z_post_mean[year_rows], idx[year_rows, 1])

  grid <- arrays$area_grid_sf
  grid$occupancy <- unname(occ_by_site[as.character(grid$grid_id)])

  if (is.null(main)) main <- paste0("Posterior occupancy (year ", year, ")")
  plot(grid["occupancy"], main = main, ...)
  invisible(grid)
}

#' Map a covariate across the study grid
#'
#' Plots one window's worth of a covariate matrix - e.g. `sst_avg$sst` from
#' `average_covariates()` - across the grid, so it can be checked visually
#' before it goes into `fit_occupancy_model()`. A covariate that's `NA`
#' everywhere, constant, or has an unexpected spatial pattern is much faster
#' to spot here than after a fit quietly does nothing with it.
#'
#' @param cov a `[num_cells x num_windows]` covariate matrix, i.e. one
#'   element of `average_covariates()`'s return list (e.g. `sst_avg$sst`)
#' @param arrays the list returned by `build_detection_arrays()`; `cov` must
#'   come from `average_covariates()` called with this same `arrays$area_grid_sf`,
#'   so rows line up
#' @param window which column of `cov` to show, by position or by
#'   `colnames(cov)` label (e.g. a `windows$label` value); defaults to the
#'   last column
#' @param var_name name to use in the auto-generated title (e.g. `"sst"`);
#'   ignored if `main` is given
#' @param main plot title; auto-generated from `var_name`/`window` if `NULL`
#' @param ... passed on to `plot()`
#' @return invisibly, `arrays$area_grid_sf` with a `covariate` column added
#'   (the chosen window's values)
#' @seealso [average_covariates()], which produces `cov`; [plot_survey_coverage()],
#'   [plot_sightings()], [plot_occupancy_map()]
#' @family diagnostic plots
#' @examples
#' \dontrun{
#' sst_avg <- average_covariates(env_dat, arrays$area_grid_sf, windows)
#' plot_covariate_map(sst_avg$sst, arrays, var_name = "sst")
#' plot_covariate_map(sst_avg$sst, arrays, window = 3, var_name = "sst")
#' }
#' @export
plot_covariate_map <- function(cov, arrays, window = NULL, var_name = NULL, main = NULL, ...) {
  if (!is.matrix(cov)) {
    stop("cov must be a matrix, e.g. one element of average_covariates()'s return value ",
         "(like sst_avg$sst).")
  }
  if (nrow(cov) != arrays$num_cells) {
    stop("cov has ", nrow(cov), " row(s) but arrays$num_cells is ", arrays$num_cells,
         "; cov must come from average_covariates() called with this same arrays$area_grid_sf.")
  }

  window_labels <- colnames(cov)
  if (is.null(window)) {
    window_idx <- ncol(cov)
  } else if (is.character(window)) {
    window_idx <- match(window, window_labels)
    if (is.na(window_idx)) {
      stop("window '", window, "' not found in colnames(cov): ",
           paste(window_labels, collapse = ", "))
    }
  } else {
    if (window < 1 || window > ncol(cov)) {
      stop("window must be between 1 and ", ncol(cov), " (ncol(cov)).")
    }
    window_idx <- window
  }

  grid <- arrays$area_grid_sf
  grid$covariate <- cov[, window_idx]

  if (is.null(main)) {
    label <- if (!is.null(window_labels)) window_labels[window_idx] else window_idx
    var_label <- if (!is.null(var_name)) var_name else "covariate"
    main <- paste0(var_label, " (", label, ")")
  }
  plot(grid["covariate"], main = main, ...)
  invisible(grid)
}
