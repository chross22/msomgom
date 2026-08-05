#' Evaluate a fitted occupancy model
#'
#' Reports MCMC convergence diagnostics (Gelman-Rubin Rhat, effective sample
#' size), a posterior parameter summary table, trace/density plots, and (when
#' the model was run with `jags.params = "Z"`) a comparison of naive vs.
#' model-estimated occupancy per year.
#'
#' Does not change or re-derive anything about the model itself (see
#' `jags.R`) - a real posterior-predictive goodness-of-fit check would need
#' derived nodes added to `whale.mod`, which is a model-design change, not an
#' evaluation one.
#'
#' @examples
#' \dontrun{
#' fit <- fit_occupancy_model(arrays, config)
#' evaluate_occupancy_model(fit, arrays, config)
#'
#' # or, to re-evaluate a previously saved run without re-fitting:
#' evaluate_occupancy_model("output/mock_test/RIWH.colext.RData", config = config)
#' }
#'
#' @param fit an `mcmc.list` (e.g. from `fit_occupancy_model()`), or a path to
#'   a saved `.RData` file containing one
#' @param arrays optional; the list returned by `build_detection_arrays()`.
#'   Required for the naive-vs-modeled occupancy comparison when `fit` tracked `Z`.
#' @param config optional; a config list, as returned by `load_config()`.
#'   Used to resolve `output_dir` and for the naive-vs-modeled occupancy comparison.
#' @param output_dir directory to save `mcmc_diagnostics.pdf` to; defaults to
#'   `config$paths$output_dir`, or the working directory if `config` is also `NULL`
#' @param save_plots logical; whether to save trace/density plots
#' @return invisibly, `list(parameters = <summary data.frame>, occupancy_comparison = <data.frame or NULL>)`
evaluate_occupancy_model <- function(fit, arrays = NULL, config = NULL,
                                      output_dir = NULL, save_plots = TRUE) {
  library(coda)

  if (is.character(fit)) {
    fit <- load_mcmc_list(fit)
  }
  if (!inherits(fit, "mcmc.list")) {
    stop("evaluate_occupancy_model() expects an mcmc.list (what fit_occupancy_model() ",
         "returns), or a path to a saved .RData file containing one.")
  }

  param_summary <- summary(fit)
  ess <- effectiveSize(fit)

  n_chains <- length(fit)
  if (n_chains >= 2) {
    rhat <- gelman.diag(fit, multivariate = FALSE)$psrf[, "Point est."]
  } else {
    warning("Only one chain in fit; can't compute Gelman-Rubin Rhat (needs >= 2 chains). ",
            "Set jags.n_chains >= 2 in the config for a real convergence check.")
    rhat <- setNames(rep(NA_real_, nrow(param_summary$statistics)), rownames(param_summary$statistics))
  }

  results <- data.frame(
    parameter = rownames(param_summary$statistics),
    mean = param_summary$statistics[, "Mean"],
    sd = param_summary$statistics[, "SD"],
    q2.5 = param_summary$quantiles[, "2.5%"],
    q50 = param_summary$quantiles[, "50%"],
    q97.5 = param_summary$quantiles[, "97.5%"],
    eff_size = as.numeric(ess[rownames(param_summary$statistics)]),
    rhat = as.numeric(rhat[rownames(param_summary$statistics)]),
    row.names = NULL
  )
  results$converged <- ifelse(is.na(results$rhat), NA, results$rhat < 1.1)

  cat("\n=== Posterior parameter summary ===\n")
  print(results, digits = 3)

  not_converged <- !is.na(results$rhat) & results$rhat >= 1.1
  if (any(not_converged)) {
    warning("Rhat >= 1.1 for: ", paste(results$parameter[not_converged], collapse = ", "),
            ". Chains may not have converged - consider increasing jags.n_adapt/n_burn/n_iter.")
  }
  low_ess <- results$eff_size < 100
  if (any(low_ess)) {
    warning("Effective sample size < 100 for: ", paste(results$parameter[low_ess], collapse = ", "),
            ". Posterior estimates for these parameters are noisy - consider increasing jags.n_iter.")
  }

  occupancy_comparison <- NULL
  z_rows <- grepl("^Z\\[", rownames(param_summary$statistics))
  if (any(z_rows) && !is.null(arrays)) {
    occupancy_comparison <- compare_naive_vs_modeled_occupancy(fit, arrays, config)
    cat("\n=== Naive vs. modeled occupancy (posterior mean Z) ===\n")
    print(occupancy_comparison, digits = 3)
  }

  if (save_plots) {
    if (is.null(output_dir)) {
      output_dir <- if (!is.null(config)) config$paths$output_dir else "."
    }
    if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)
    plot_path <- file.path(output_dir, "mcmc_diagnostics.pdf")
    pdf(plot_path)
    plot(fit)
    dev.off()
    message("Saved trace/density plots to ", plot_path)
  }

  invisible(list(parameters = results, occupancy_comparison = occupancy_comparison))
}

#' Load a saved MCMC fit
#'
#' Loads the first `mcmc.list` found in a saved `.RData` file (as written by
#' `fit_occupancy_model()`'s `save(whale.pars, file = ...)`).
#'
#' @param path path to a `.RData` file containing an `mcmc.list`
#' @return the `mcmc.list` object
load_mcmc_list <- function(path) {
  if (!file.exists(path)) stop("File not found: ", path)
  e <- new.env()
  load(path, envir = e)
  is_mcmc_list <- vapply(ls(e), function(n) inherits(get(n, envir = e), "mcmc.list"), logical(1))
  if (!any(is_mcmc_list)) stop("No mcmc.list object found in ", path)
  get(ls(e)[is_mcmc_list][1], envir = e)
}

#' Compare naive vs. modeled occupancy per year
#'
#' Naive occupancy (proportion of sites with >=1 detection, ignoring
#' never-surveyed sites) vs. the model's posterior mean occupancy state (`Z`),
#' one row per year - mirrors the `psi.naive` calculation in `jags.R` so the
#' two are directly comparable. Requires `fit` to have tracked `Z` (i.e. the
#' model was run with `jags.params = "Z"`).
#'
#' @param fit an `mcmc.list` that tracked `Z`
#' @param arrays the list returned by `build_detection_arrays()`
#' @param config a config list, as returned by `load_config()`
#' @return data.frame with columns `year`, `n_sites`, `naive_psi`, `modeled_psi`
compare_naive_vs_modeled_occupancy <- function(fit, arrays, config) {
  species_code <- config$species$active
  max_survs <- arrays$max_survs
  spp3d_01 <- arrays$species_arrays[[species_code]]
  spp3d_01[spp3d_01 > 1] <- 1
  dets <- spp3d_01[, 2:(max_survs + 1), ]

  n.season <- 1
  n.year <- dim(dets)[3] / n.season
  dets4d <- array(dim = c(dim(dets)[1], dim(dets)[2], n.season, n.year), data = as.vector(dets))

  z_mat <- as.matrix(fit)
  z_cols <- grep("^Z\\[", colnames(z_mat), value = TRUE)
  idx <- do.call(rbind, lapply(strsplit(sub("^Z\\[", "", sub("\\]$", "", z_cols)), ","), as.integer))
  z_post_mean <- colMeans(z_mat[, z_cols, drop = FALSE])

  out <- data.frame(year = integer(0), n_sites = integer(0), naive_psi = double(0), modeled_psi = double(0))
  for (t in seq_len(n.year)) {
    naive_z <- apply(dets4d[, , , t, drop = FALSE], MARGIN = 1, max, na.rm = TRUE)
    naive_z <- naive_z[is.finite(naive_z)] # drop never-surveyed sites
    year_idx <- which(idx[, 3] == t)
    out <- rbind(out, data.frame(
      year = t,
      n_sites = length(naive_z),
      naive_psi = mean(naive_z),
      modeled_psi = mean(z_post_mean[year_idx])
    ))
  }
  out
}
