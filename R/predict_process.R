#' Predict a process's probability surface across the study grid
#'
#' Turns a coefficient-level (`jags_params = "colext"`, the default) fit into
#' a per-cell probability surface for one of the three occupancy processes:
#' initial occupancy (`psi`), persistence (`phi`), or colonization (`gamma`).
#' Each posterior draw's coefficients are pushed through that draw's inverse
#' logit at every cell, so the summaries are true posterior summaries of the
#' surface, not transformations of coefficient summaries.
#'
#' This is the spatial view a `colext` fit implies but never stores: `Z` isn't
#' tracked, so there is no realized occupancy map ([plot_occupancy_map()]
#' needs `jags_params = "Z"` for that) - but wherever a process has covariates,
#' its fitted probability varies cell by cell, and this reconstructs exactly
#' the linear predictor the JAGS model used, including the fit's own
#' standardization of each covariate (stored on the fit at fitting time).
#'
#' Two honest limitations, both worth knowing when reading a map:
#' the year-level intercepts (`b.0[t]`, `e.0[t]`, `g.0[t]`) are not tracked,
#' only their hyper-means (`mu.b.0`, ...), so this is the population-level
#' surface - `season` moves the map only through the covariate values, not
#' through a year effect. And a process with no covariates configured is
#' spatially flat by construction; the surface is still computed (it's the
#' posterior of the intercept, which is not nothing), with a message saying
#' so.
#'
#' @param object a `dynocc_fit` from `fit_occupancy_model()` (must be a
#'   `"colext"` fit - a `"Z"` fit tracks states, not coefficients)
#' @param arrays the list returned by `build_detection_arrays()` (must be the
#'   same one `object` was fit against, so cells line up)
#' @param process which process to predict: `"psi"` (initial occupancy),
#'   `"phi"` (persistence), or `"gamma"` (colonization)
#' @param occ_covariates the same named list of `[num_cells x num_ssn]`
#'   matrices that was passed to `fit_occupancy_model()` (e.g. from
#'   [average_covariates()]). Required when `process` has covariates
#'   configured; ignored otherwise
#' @param season which season's covariate values to predict at
#'   (`1:arrays$num_ssn`); defaults to the last season
#' @param level credible-interval level for `lower`/`upper` (default 0.95)
#' @param ... ignored; present to match [stats::predict()]'s signature
#' @return a data.frame with one row per grid cell: `grid_id`, `mean`, `sd`,
#'   `lower`, `upper` (posterior mean, SD, and credible interval of the
#'   process probability), with attributes `process`, `season`, and `level`
#' @seealso [plot_process_map()], which draws this;
#'   [effect_estimates.dynocc_fit()] for the same coefficients as a curve
#'   along one covariate; [plot_occupancy_map()] for realized occupancy from
#'   a `"Z"` fit
#' @family covariates
#' @examples
#' \dontrun{
#' fit <- fit_occupancy_model(arrays, config, occ_covariates = list(sst = sst_avg$sst))
#' predict(fit, arrays, "psi", occ_covariates = list(sst = sst_avg$sst))
#' }
#' @export
predict.dynocc_fit <- function(object, arrays, process = c("psi", "phi", "gamma"),
                               occ_covariates = NULL, season = NULL,
                               level = 0.95, ...) {
  process <- match.arg(process)
  prefix <- c(psi = "b", phi = "e", gamma = "g")[[process]]

  if (!is.numeric(level) || length(level) != 1 || is.na(level) || level <= 0 || level >= 1) {
    stop("level must be a single number strictly between 0 and 1, not: ", level)
  }
  if (is.null(season)) season <- arrays$num_ssn
  if (season < 1 || season > arrays$num_ssn) {
    stop("season must be between 1 and ", arrays$num_ssn, " (arrays$num_ssn).")
  }

  z_mat <- as.matrix(object)
  intercept_col <- paste0("mu.", prefix, ".0")
  if (!(intercept_col %in% colnames(z_mat))) {
    stop("model doesn't track ", intercept_col, " - re-fit with jags_params = ",
         "\"colext\" (the default) to track process coefficients; a \"Z\" fit ",
         "tracks occupancy states instead (see plot_occupancy_map()).")
  }

  meta <- attr(object, "dynocc_covariates")
  meta <- meta[meta$process == process, , drop = FALSE]

  # [draws x cells]
  linpred <- matrix(z_mat[, intercept_col], nrow = nrow(z_mat), ncol = arrays$num_cells)

  if (is.null(meta) || nrow(meta) == 0) {
    message("No covariates were configured on ", process, ", so this surface ",
            "is spatially flat: the posterior of ", intercept_col, " alone.")
  } else {
    missing_covs <- setdiff(meta$name, names(occ_covariates))
    if (length(missing_covs)) {
      stop(process, " was fit with covariate(s) ", paste(missing_covs, collapse = ", "),
           " - pass the same occ_covariates list fit_occupancy_model() was given, ",
           "so per-cell values are available to predict at.")
    }
    for (i in seq_len(nrow(meta))) {
      m <- meta[i, ]
      mat <- occ_covariates[[m$name]]
      if (!is.matrix(mat) || nrow(mat) != arrays$num_cells || ncol(mat) < season) {
        stop("occ_covariates[[\"", m$name, "\"]] must be a [", arrays$num_cells,
             " x ", arrays$num_ssn, "] matrix (num_cells x num_ssn), the same ",
             "shape fit_occupancy_model() was given.")
      }
      # the fit's own standardization, replayed exactly: stored mean/sd, NA -> 0
      z <- (mat[, season] - m$mean) / m$sd
      z[is.na(z)] <- 0
      coef_col <- if (m$n_cov == 1) {
        paste0("mu.", prefix, ".cov")
      } else {
        paste0("mu.", prefix, ".cov[", m$index, "]")
      }
      if (!(coef_col %in% colnames(z_mat))) {
        stop("model doesn't track ", coef_col, " - was this fit made before ",
             "covariates were configured on ", process, "?")
      }
      linpred <- linpred + outer(z_mat[, coef_col], z)
    }
  }

  prob <- stats::plogis(linpred)
  qs <- apply(prob, 2, stats::quantile,
              probs = c((1 - level) / 2, 1 - (1 - level) / 2))

  out <- data.frame(
    grid_id = arrays$area_grid_sf$grid_id,
    mean = colMeans(prob),
    sd = apply(prob, 2, stats::sd),
    lower = qs[1, ],
    upper = qs[2, ]
  )
  attr(out, "process") <- process
  attr(out, "season") <- season
  attr(out, "level") <- level
  out
}

#' Map a fitted process probability across the study grid
#'
#' Draws [predict.dynocc_fit()]'s surface: posterior mean (or posterior SD,
#' the uncertainty map) of initial occupancy, persistence, or colonization,
#' per grid cell. This is the spatial payoff of a covariate fit - where the
#' model thinks the species persists, colonizes, or starts out present - and
#' the `"sd"` map is the honest companion: a striking mean surface over cells
#' the posterior barely constrains is a prior in a costume.
#'
#' @param fit a `dynocc_fit` from `fit_occupancy_model()` (a `"colext"` fit)
#' @param arrays the list returned by `build_detection_arrays()` (the same one
#'   `fit` was fit against)
#' @param process `"psi"`, `"phi"`, or `"gamma"` - see [predict.dynocc_fit()]
#' @param occ_covariates the same named list of covariate matrices
#'   `fit_occupancy_model()` was given; required when `process` has covariates
#' @param season which season's covariate values to map (`1:arrays$num_ssn`);
#'   defaults to the last season
#' @param stat `"mean"` (the default) or `"sd"` for the posterior-uncertainty
#'   map
#' @param main plot title; auto-generated if `NULL`
#' @param ... passed on to `plot()`
#' @return invisibly, `arrays$area_grid_sf` with the full
#'   [predict.dynocc_fit()] summary columns (`mean`, `sd`, `lower`, `upper`)
#'   added
#' @seealso [predict.dynocc_fit()] for the numbers; [plot_occupancy_map()]
#'   for realized occupancy from a `"Z"` fit; [plot_covariate_map()] for the
#'   covariate that shaped the surface
#' @family diagnostic plots
#' @examples
#' \dontrun{
#' fit <- fit_occupancy_model(arrays, config, occ_covariates = list(sst = sst_avg$sst))
#' plot_process_map(fit, arrays, "psi", occ_covariates = list(sst = sst_avg$sst))
#' plot_process_map(fit, arrays, "gamma", occ_covariates = list(sst = sst_avg$sst),
#'                  stat = "sd")
#' }
#' @export
plot_process_map <- function(fit, arrays, process = c("psi", "phi", "gamma"),
                             occ_covariates = NULL, season = NULL,
                             stat = c("mean", "sd"), main = NULL, ...) {
  process <- match.arg(process)
  stat <- match.arg(stat)

  pred <- stats::predict(fit, arrays, process, occ_covariates = occ_covariates,
                         season = season)

  grid <- arrays$area_grid_sf
  grid$mean <- pred$mean
  grid$sd <- pred$sd
  grid$lower <- pred$lower
  grid$upper <- pred$upper

  if (is.null(main)) {
    label <- c(psi = "Initial occupancy (psi)", phi = "Persistence (phi)",
               gamma = "Colonization (gamma)")[[process]]
    main <- paste0(label, ", posterior ", stat,
                   " (season ", attr(pred, "season"), ")")
  }
  plot(grid[stat], main = main, ...)
  invisible(grid)
}
