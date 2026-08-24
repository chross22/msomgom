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
#' @param season which absolute season to show (the same index
#'   `plot_detection_history()`, `season_windows_from_config()`, and the
#'   detection arrays use); defaults to the last season tracked in `fit`
#' @param stat `"mean"` (the default) or `"sd"`: the posterior mean of `Z` is
#'   the occupancy map, and its posterior SD is the uncertainty map - a cell
#'   the chains never agree on shows up bright in `"sd"` and unremarkable in
#'   `"mean"`
#' @param main plot title; auto-generated from `season`/`stat` if `NULL`
#' @param ... passed on to `plot()`
#' @param year deprecated older name for `season`, kept so existing calls
#'   keep working - it always meant the arrays' 3rd-dimension index, which is
#'   the absolute season
#' @return invisibly, `arrays$area_grid_sf` with an `occupancy` column added
#'   (posterior mean or SD of `Z` for the chosen season, per `stat`)
#' @seealso [plot_survey_coverage()], [plot_sightings()], [plot_covariate_map()],
#'   [plot_process_map()] for the fitted psi/phi/gamma surfaces of a
#'   `"colext"` fit (which tracks no `Z` to map),
#'   [compare_naive_vs_modeled_occupancy()] for the same numbers as a table,
#'   [load_mcmc_list()] for how a saved `.RData` path is resolved
#' @family diagnostic plots
#' @examples
#' \dontrun{
#' fit <- fit_occupancy_model(arrays, config) # config$jags$params must be "Z"
#' plot_occupancy_map(fit, arrays)
#' plot_occupancy_map(fit, arrays, season = 2)
#' }
#' @export
plot_occupancy_map <- function(fit, arrays, season = NULL, stat = c("mean", "sd"),
                               main = NULL, ..., year = NULL) {
  stat <- match.arg(stat)
  if (is.null(season) && !is.null(year)) season <- year
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
  z_post_mean <- if (stat == "sd") {
    apply(z_mat[, z_cols, drop = FALSE], 2, stats::sd)
  } else {
    colMeans(z_mat[, z_cols, drop = FALSE])
  }

  # Z is indexed [site, within-year season, year]; fold the last two into the
  # absolute season index the rest of this package speaks
  n_within <- max(idx[, 2])
  abs_season <- (idx[, 3] - 1) * n_within + idx[, 2]
  seasons_available <- sort(unique(abs_season))
  if (is.null(season)) {
    season <- max(seasons_available)
  } else if (!(season %in% seasons_available)) {
    stop("season must be one of: ", paste(seasons_available, collapse = ", "))
  }

  season_rows <- which(abs_season == season)
  occ_by_site <- setNames(z_post_mean[season_rows], idx[season_rows, 1])

  grid <- arrays$area_grid_sf
  grid$occupancy <- unname(occ_by_site[as.character(grid$grid_id)])

  if (is.null(main)) {
    main <- paste0(if (stat == "sd") "Posterior occupancy SD (season " else "Posterior occupancy (season ",
                   season, ")")
  }
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

#' Plot the detection history the model actually sees
#'
#' One tile per site x season: was the cell surveyed, and if so, was the
#' species detected? This is the entire information content of the occupancy
#' model's likelihood in one figure - everything else (covariates, priors)
#' only shapes how these tiles are interpolated.
#'
#' Read it for structure before fitting: a season that is almost all grey
#' (unsurveyed) will pull its occupancy estimates toward the prior and the
#' colonization/persistence dynamics, not the data; a species whose detections
#' are confined to a few sites across every season is a candidate for a
#' spatially-varying detection covariate rather than more iterations.
#'
#' @param arrays the list returned by `build_detection_arrays()`
#' @param species species code; must be a name in `arrays$species_arrays`
#' @param main plot title; auto-generated from `species` if `NULL`
#' @param ... passed on to `image()`
#' @return invisibly, the `<site x season>` state matrix: `NA` = unsurveyed,
#'   `0` = surveyed without a detection, `1` = detected
#' @seealso [plot_survey_coverage()], [plot_sightings()],
#'   [plot_occupancy_map()], [build_detection_arrays()], which produces
#'   `arrays`
#' @family diagnostic plots
#' @examples
#' \dontrun{
#' arrays <- build_detection_arrays(prep$tmpdat, prep$season_info, config)
#' plot_detection_history(arrays, "RIWH")
#' }
#' @export
plot_detection_history <- function(arrays, species, main = NULL, ...) {
  if (!(species %in% names(arrays$species_arrays))) {
    stop("species '", species, "' not in arrays$species_arrays. Available: ",
         paste(names(arrays$species_arrays), collapse = ", "))
  }

  spp3d <- arrays$species_arrays[[species]]
  # visit columns are 2:(max_survs + 1); column 1 is the site id
  dets <- spp3d[, 2:(arrays$max_survs + 1), , drop = FALSE]

  surveyed <- t(arrays$reps)          # <site x season>, NA where never visited
  surveyed[is.na(surveyed)] <- 0

  state <- matrix(NA_real_, nrow = arrays$num_cells, ncol = arrays$num_ssn)
  detected <- apply(dets, c(1, 3), function(x) any(x > 0, na.rm = TRUE))
  state[surveyed > 0] <- 0
  state[surveyed > 0 & detected] <- 1

  if (is.null(main)) main <- paste0("Detection history (", species, ")")

  # image() drops a constant matrix's scale, so the colors are pinned to the
  # three states explicitly via breaks
  graphics::image(x = seq_len(arrays$num_ssn), y = seq_len(arrays$num_cells),
        z = t(state), col = c("lightsteelblue3", "firebrick"),
        breaks = c(-0.5, 0.5, 1.5),
        xlab = "Season", ylab = "Site (grid cell)", main = main, ...)
  graphics::legend("topright", inset = c(0, -0.02), xpd = TRUE, bty = "n", cex = 0.8,
         fill = c("white", "lightsteelblue3", "firebrick"),
         border = c("grey70", NA, NA),
         legend = c("unsurveyed", "no detection", "detected"))

  invisible(state)
}

#' Plot MCMC convergence at a glance
#'
#' Every tracked parameter as one point: Gelman-Rubin Rhat against effective
#' sample size, with the conventional thresholds drawn (Rhat < 1.1,
#' ESS >= 100 - the same ones `evaluate_occupancy_model()` warns about).
#' Parameters outside either threshold are labeled by name.
#'
#' The two axes fail differently: high Rhat means the chains disagree about
#' where the posterior is (run longer, or reparameterize), while low ESS with
#' good Rhat means they agree but mix slowly (thin less, run longer, or accept
#' noisier estimates). A point bad on both axes usually indicates a parameter
#' the data barely inform - check the detection history
#' ([plot_detection_history()]) before buying more iterations.
#'
#' @param fit an `mcmc.list` (what `fit_occupancy_model()` returns), a path to
#'   a saved fit, or the list `evaluate_occupancy_model()` returns invisibly
#'   (its `$parameters` data.frame is used directly, skipping recomputation)
#' @param rhat_threshold Rhat above this is flagged (default 1.1)
#' @param ess_threshold effective sample size below this is flagged
#'   (default 100)
#' @param main plot title
#' @param ... passed on to `plot()`
#' @return invisibly, a data.frame with columns `parameter`, `eff_size`,
#'   `rhat`, and `flagged`
#' @seealso [evaluate_occupancy_model()], which computes the same diagnostics
#'   as numbers; [fit_occupancy_model()], which produces `fit`
#' @family diagnostic plots
#' @examples
#' \dontrun{
#' fit <- fit_occupancy_model(arrays, config)
#' plot_convergence(fit)
#' }
#' @export
plot_convergence <- function(fit, rhat_threshold = 1.1, ess_threshold = 100,
                             main = "MCMC convergence", ...) {
  if (is.list(fit) && !is.null(fit$parameters)) {
    results <- fit$parameters
  } else {
    if (!requireNamespace("coda", quietly = TRUE)) {
      stop("The 'coda' package is required. Install it with install.packages('coda').")
    }
    if (is.character(fit)) fit <- load_mcmc_list(fit)
    if (!inherits(fit, "mcmc.list")) {
      stop("plot_convergence() expects an mcmc.list, a path to a saved fit, or ",
           "the list evaluate_occupancy_model() returns.")
    }
    if (length(fit) < 2) {
      stop("Rhat needs >= 2 chains and this fit has ", length(fit),
           ". Set jags.n_chains >= 2 in the config for a real convergence check.")
    }
    ess <- coda::effectiveSize(fit)
    rhat <- coda::gelman.diag(fit, multivariate = FALSE)$psrf[, "Point est."]
    results <- data.frame(parameter = names(rhat),
                          eff_size = as.numeric(ess[names(rhat)]),
                          rhat = as.numeric(rhat), row.names = NULL)
  }
  if (all(is.na(results$rhat))) {
    stop("Every Rhat is NA (a single-chain fit). Set jags.n_chains >= 2 in ",
         "the config for a real convergence check.")
  }

  results$flagged <- !is.na(results$rhat) &
    (results$rhat >= rhat_threshold | results$eff_size < ess_threshold)

  plot(results$eff_size, results$rhat, log = "x",
       xlab = "Effective sample size (log scale)",
       ylab = "Gelman-Rubin Rhat", main = main,
       pch = ifelse(results$flagged, 19, 1),
       col = ifelse(results$flagged, "firebrick", "grey30"), ...)
  graphics::abline(h = rhat_threshold, lty = 2, col = "grey60")
  graphics::abline(v = ess_threshold, lty = 2, col = "grey60")
  if (any(results$flagged)) {
    graphics::text(results$eff_size[results$flagged], results$rhat[results$flagged],
         labels = results$parameter[results$flagged],
         pos = 4, cex = 0.7, col = "firebrick", xpd = TRUE)
  }

  invisible(results)
}
