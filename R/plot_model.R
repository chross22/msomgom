# --- reading the fit --------------------------------------------------------
#
# Maps say where. These say whether the fit is worth reading a map of, and
# they use fancyfx's theme and palette so a dynocc figure sits beside a
# fancyfx effect curve without a change of visual language.

fancyfx_theme <- function(base_size = 12) {
  if (requireNamespace("fancyfx", quietly = TRUE)) {
    fancyfx::theme_fancyfx(base_size = base_size)
  } else {
    ggplot2::theme_minimal(base_size = base_size)
  }
}

fancyfx_colours <- function(n = 6) {
  if (requireNamespace("fancyfx", quietly = TRUE)) {
    fancyfx::fancyfx_palette(n)
  } else {
    grDevices::hcl.colors(n, "Dark 3")
  }
}

require_ggplot2 <- function(what) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    stop("The 'ggplot2' package is required for ", what,
         ". Install it with install.packages('ggplot2').", call. = FALSE)
  }
}

#' Plot occupancy across seasons, modeled against naive
#'
#' The single figure that answers "is this species occupying more or less of
#' the study area over time" - the question a multi-season occupancy model is
#' usually fit to answer, and one that `compare_naive_vs_modeled_occupancy()`
#' currently only reports as a table.
#'
#' Both series are drawn: the modeled trajectory with its credible band, and
#' the naive proportion of surveyed cells with a detection. The gap between
#' them is the detection correction, which is the reason to fit the model at
#' all - if they sit on top of each other, detection is near certain and the
#' model is doing little; if the modeled line runs far above, most occupied
#' cells were never seen, and the naive series would have understated
#' occupancy badly.
#'
#' Requires a `"Z"` fit, since it is the latent states that give occupancy
#' per season. A `"colext"` fit tracks coefficients instead - see
#' [occupancy_summary()] for what that offers, and [plot_process_map()] for
#' the surfaces it implies.
#'
#' @param fit an `mcmc.list` that tracked `Z`, or a path to a saved fit
#' @param arrays the list from [build_detection_arrays()]
#' @param config a config list, as returned by [load_config()]
#' @param level credible-interval level for the band (default 0.95)
#' @param naive whether to draw the naive series alongside (default `TRUE`)
#' @return invisibly, the data.frame behind the figure - one row per season
#'   with `season`, `naive_psi`, `modeled_psi`, `lower`, `upper` - with the
#'   `ggplot` attached as the `"plot"` attribute
#' @seealso [compare_naive_vs_modeled_occupancy()] for the same numbers as a
#'   table; [occupancy_summary()] for the derived quantities behind them
#' @family diagnostic plots
#' @examples
#' \dontrun{
#' fit <- fit_occupancy_model(arrays, config) # config$jags$params must be "Z"
#' plot_occupancy_trend(fit, arrays, config)
#' }
#' @export
plot_occupancy_trend <- function(fit, arrays, config, level = 0.95,
                                 naive = TRUE) {
  require_ggplot2("plot_occupancy_trend()")
  if (is.character(fit)) fit <- load_mcmc_list(fit)

  z_mat <- as.matrix(fit)
  z_cols <- grep("^Z\\[", colnames(z_mat), value = TRUE)
  if (!length(z_cols)) {
    stop("fit has no Z[...] columns, so there is no per-season occupancy to ",
         "plot - re-fit with jags_params = \"Z\". A \"colext\" fit tracks ",
         "coefficients instead; occupancy_summary() reads those.", call. = FALSE)
  }
  idx <- do.call(rbind, lapply(strsplit(sub("^Z\\[", "", sub("\\]$", "", z_cols)), ","), as.integer))
  n_within <- max(idx[, 2])
  abs_season <- (idx[, 3] - 1) * n_within + idx[, 2]

  # Occupancy per season per draw: the share of cells occupied, summarized
  # across draws. Averaging the per-cell posterior means instead would throw
  # away the correlation between cells and give a band that is too narrow.
  probs <- c((1 - level) / 2, 1 - (1 - level) / 2)
  seasons <- sort(unique(abs_season))
  per_season <- lapply(seasons, function(s) {
    occupied <- rowMeans(z_mat[, z_cols[abs_season == s], drop = FALSE])
    qs <- stats::quantile(occupied, probs = probs, names = FALSE)
    data.frame(season = s, modeled_psi = mean(occupied),
               lower = qs[1], upper = qs[2])
  })
  out <- do.call(rbind, per_season)

  if (naive) {
    comparison <- compare_naive_vs_modeled_occupancy(fit, arrays, config)
    out$naive_psi <- comparison$naive_psi[match(out$season, comparison$season)]
  }

  pal <- fancyfx_colours(2)
  fig <- ggplot2::ggplot(out, ggplot2::aes(x = .data$season)) +
    ggplot2::geom_ribbon(ggplot2::aes(ymin = .data$lower, ymax = .data$upper),
                         fill = pal[1], alpha = 0.2) +
    ggplot2::geom_line(ggplot2::aes(y = .data$modeled_psi, colour = "Modeled"),
                       linewidth = 0.9) +
    ggplot2::geom_point(ggplot2::aes(y = .data$modeled_psi, colour = "Modeled"))
  if (naive && !all(is.na(out$naive_psi))) {
    fig <- fig +
      ggplot2::geom_line(ggplot2::aes(y = .data$naive_psi, colour = "Naive"),
                         linetype = "dashed", linewidth = 0.8) +
      ggplot2::geom_point(ggplot2::aes(y = .data$naive_psi, colour = "Naive"),
                          shape = 21, fill = "white")
  }
  fig <- fig +
    ggplot2::scale_colour_manual(values = c(Modeled = pal[1], Naive = pal[2]),
                                 name = NULL) +
    ggplot2::scale_y_continuous(limits = c(0, 1)) +
    ggplot2::labs(x = "Season", y = "Occupancy",
                  title = paste0("Occupancy across seasons (", config$species$active, ")"),
                  subtitle = if (naive) {
                    "Gap between the series is the detection correction"
                  } else NULL) +
    fancyfx_theme()
  print(fig)
  with_plot(out, fig)
}

#' Plot each parameter's posterior against the prior it started from
#'
#' The check that catches the failure no convergence diagnostic can: a
#' parameter the data never informed, whose posterior is still its prior.
#' That arrives looking flawless - `Rhat` 1.00 and every draw effective,
#' because sampling a prior is easy - and it is exactly what hid this
#' package's inert colonization/persistence dynamics through every fit it had
#' produced.
#'
#' One panel per parameter: the prior as a dashed line, the posterior filled
#' beneath it. A posterior sitting under its prior curve learned nothing, and
#' should not be interpreted whatever its credible interval says.
#'
#' @param fit a `dynocc_fit` from [fit_occupancy_model()] with
#'   `jags_params = "colext"`
#' @param parameters which parameters to draw; `NULL` (the default) takes
#'   every `mu.*` the fit tracked
#' @param prior_sd standard deviation of the prior, on the logit scale -
#'   defaults to the `dnorm(0, 0.1)` every `mu.*` in this model is given
#' @return invisibly, a data.frame of the drawn draws, with the `ggplot`
#'   attached as the `"plot"` attribute
#' @seealso [occupancy_summary()], which reports the same check as a
#'   contraction number per parameter; [plot_convergence()], which cannot see
#'   this failure at all
#' @family diagnostic plots
#' @examples
#' \dontrun{
#' fit <- fit_occupancy_model(arrays, config)
#' plot_prior_posterior(fit)
#' }
#' @export
plot_prior_posterior <- function(fit, parameters = NULL, prior_sd = NULL) {
  require_ggplot2("plot_prior_posterior()")
  prior_sd <- prior_sd %||% dynocc_prior_sd()

  draws <- as.matrix(fit)
  parameters <- parameters %||% grep("^mu\\.", colnames(draws), value = TRUE)
  missing_pars <- setdiff(parameters, colnames(draws))
  if (length(missing_pars)) {
    stop("fit does not track: ", paste(missing_pars, collapse = ", "),
         ". It tracks: ", paste(colnames(draws), collapse = ", "), call. = FALSE)
  }
  if (!length(parameters)) {
    stop("fit tracks no mu.* parameters to compare against a prior - this ",
         "reads a \"colext\" fit (the default); a \"Z\" fit tracks states.",
         call. = FALSE)
  }

  long <- do.call(rbind, lapply(parameters, function(p) {
    data.frame(parameter = p, value = draws[, p], stringsAsFactors = FALSE)
  }))

  # The prior curve, evaluated across whatever range the panels span, so the
  # comparison is like-for-like rather than each panel rescaling it.
  grid <- seq(min(long$value, -3 * prior_sd), max(long$value, 3 * prior_sd),
              length.out = 200)
  prior <- do.call(rbind, lapply(parameters, function(p) {
    data.frame(parameter = p, value = grid,
               density = stats::dnorm(grid, 0, prior_sd),
               stringsAsFactors = FALSE)
  }))

  pal <- fancyfx_colours(2)
  fig <- ggplot2::ggplot(long, ggplot2::aes(x = .data$value)) +
    ggplot2::geom_density(fill = pal[1], colour = pal[1], alpha = 0.35) +
    ggplot2::geom_line(data = prior,
                       ggplot2::aes(x = .data$value, y = .data$density),
                       linetype = "dashed", colour = "grey40") +
    ggplot2::facet_wrap(~ parameter, scales = "free_y") +
    ggplot2::labs(x = "Value (logit scale)", y = "Density",
                  title = "Posterior against prior",
                  caption = paste0("Dashed: the dnorm(0, ", round(prior_sd, 2),
                                   ") prior. A posterior under it learned nothing.")) +
    fancyfx_theme()
  print(fig)
  with_plot(long, fig)
}

#' Map every season on one shared scale
#'
#' Small multiples of a per-season quantity - occupancy, effort, sightings -
#' drawn on a single scale, so the panels can be compared. Panels drawn
#' separately cannot be: each gets its own scale, and a cell that looks dark
#' in June and light in July may be identical in both.
#'
#' @param x either an `arrays` list from [build_detection_arrays()] (for
#'   `"coverage"` or `"sightings"`), or a `[num_cells x num_ssn]` matrix such
#'   as one element of [average_covariates()]'s return value
#' @param arrays the list from [build_detection_arrays()], for the grid; taken
#'   from `x` when `x` is itself an arrays list
#' @param what for an arrays list: `"coverage"` or `"sightings"`
#' @param species species code, when `what` is `"sightings"`
#' @param kind `"surface"` for a positive quantity, `"probability"` for a 0-1
#'   one
#' @param seasons which seasons to draw; `NULL` (the default) draws them all
#' @param title figure title
#' @return invisibly, the `sf` grid carrying one column per drawn season, with
#'   the `ggplot` attached as the `"plot"` attribute
#' @seealso [plot_survey_coverage()] and [plot_sightings()] for one season at
#'   a time; `fancymaps::map_panels()`, which draws this
#' @family diagnostic plots
#' @examples
#' \dontrun{
#' plot_season_panels(arrays, what = "coverage")
#' plot_season_panels(sst_avg$sst, arrays, kind = "surface")
#' }
#' @export
plot_season_panels <- function(x, arrays = NULL,
                               what = c("coverage", "sightings"),
                               species = NULL,
                               kind = c("surface", "probability"),
                               seasons = NULL, title = NULL) {
  if (!requireNamespace("fancymaps", quietly = TRUE)) {
    stop("The 'fancymaps' package is required for small multiples on a shared ",
         "scale. Install it with remotes::install_github('chross22/fancymaps'), ",
         "or draw one season at a time with plot_survey_coverage(arrays, ",
         "season = n).", call. = FALSE)
  }
  kind <- match.arg(kind)

  if (is.list(x) && !is.null(x$area_grid_sf)) {
    arrays <- x
    what <- match.arg(what)
    mat <- if (what == "coverage") {
      t(arrays$reps)
    } else {
      if (is.null(species)) species <- names(arrays$species_arrays)[1]
      if (!(species %in% names(arrays$species_arrays))) {
        stop("species '", species, "' has no detection array. Available: ",
             paste(names(arrays$species_arrays), collapse = ", "), call. = FALSE)
      }
      apply(arrays$species_arrays[[species]][, -1, , drop = FALSE], c(1, 3),
            sum, na.rm = TRUE)
    }
    title <- title %||% if (what == "coverage") "Survey coverage by season" else
      paste0("Sightings by season (", species, ")")
  } else {
    if (is.null(arrays)) {
      stop("`arrays` is required when `x` is a matrix - the grid to draw it ",
           "on comes from there.", call. = FALSE)
    }
    mat <- as.matrix(x)
    title <- title %||% "By season"
  }

  if (nrow(mat) != nrow(arrays$area_grid_sf)) {
    stop("x has ", nrow(mat), " rows but the grid has ",
         nrow(arrays$area_grid_sf), " cells.", call. = FALSE)
  }
  seasons <- seasons %||% seq_len(ncol(mat))
  bad <- seasons[seasons < 1 | seasons > ncol(mat)]
  if (length(bad)) {
    stop("season(s) ", paste(bad, collapse = ", "), " are outside 1..",
         ncol(mat), ".", call. = FALSE)
  }

  grid <- arrays$area_grid_sf
  columns <- paste0("season ", seasons)
  for (i in seq_along(seasons)) grid[[columns[i]]] <- mat[, seasons[i]]

  fig <- fancymaps::map_panels(grid, values = columns, kind = kind,
                               title = title)
  print(fig)
  with_plot(grid, fig)
}
