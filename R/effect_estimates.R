#' A fitted covariate's effect, in the shape fancyfx expects
#'
#' Implements [fancyfx::effect_estimates()] for a `fit_occupancy_model()`
#' result, so [fancyfx::plotEffects()]/[fancyfx::plotSmooths()] work on a
#' msomgom fit the same way they work on an `mgcv::gam` or any model
#' `marginaleffects` supports - without fancyfx needing to know anything about
#' this package. `fancyfx` is a `Suggests`-only dependency of msomgom, not the
#' other way around: this method lives here because interpreting a bare
#' `coda::mcmc.list` requires msomgom's own parameter-naming convention
#' (`mu.b.cov`, `mu.e.cov`, ...), which a generic plotting package has no way
#' to know.
#'
#' `var` must be a covariate `fit_occupancy_model()` was actually run with
#' (one of `config$covariates$psi/phi/gamma`, matched by name against
#' `occ_covariates`), and configured on exactly one process - a covariate
#' shared across processes isn't supported here, since there would be more
#' than one effect to return. The model must have been fit with
#' `jags_params = "colext"` (the default), since that's what tracks the
#' `mu.<prefix>.0`/`mu.<prefix>.cov` coefficients this reads; a `"Z"` fit only
#' tracks occupancy states.
#'
#' The evaluated grid spans the covariate's own observed range (from the raw
#' data passed to `fit_occupancy_model()`'s `occ_covariates`, not an arbitrary
#' multiple of its standard deviation), on the covariate's raw scale, so the
#' curve lines up with a rug drawn from that same raw data.
#'
#' @param model an object from `fit_occupancy_model()` (class `msomgom_fit`)
#' @param var name of the covariate whose effect to extract, as a string -
#'   matching a name in `occ_covariates`/`config$covariates$psi/phi/gamma`
#' @param scale `"auto"` (the default, resolves to `"link"`), `"link"` for the
#'   covariate's own contribution to the linear predictor (centered at zero at
#'   the covariate's mean, like a GAM partial effect), or `"response"` for the
#'   full predicted occupancy probability as the covariate varies, with any
#'   other covariates on the same process held at their mean
#' @param interval `"auto"` (the default, resolves to `"ci"`), `"ci"`/`"cri"`
#'   for the posterior credible interval at `level`, or `"se"` for a `+/- 1`
#'   posterior-SD band. `"auto"` resolves to `"ci"` because every msomgom fit
#'   is summarized from posterior draws, the same as fancyfx treats a `brms`/
#'   `rstanarm` fit - there is no standard error to build a `"se"` ribbon from
#'   independent of the posterior itself.
#' @param level credible-interval level, used when `interval` is `"ci"`/`"cri"`
#' @param n number of points at which to evaluate the effect
#' @param ... ignored; present so this matches [fancyfx::effect_estimates()]'s
#'   signature
#' @return a data.frame with columns `.x`, `.estimate`, `.lower`, `.upper`,
#'   and a `"quantity"` attribute naming what was computed - the same shape
#'   [fancyfx::effect_estimates()] documents for every model class
#' @seealso [fit_occupancy_model()], which produces `model` and attaches the
#'   covariate metadata this reads; [average_covariates()], which produces the
#'   covariate data in the first place
#' @family covariates
#' @examples
#' \dontrun{
#' fit <- fit_occupancy_model(arrays, config, occ_covariates = list(sst = sst_avg$sst))
#'
#' # standalone
#' effect_estimates(fit, "sst")
#'
#' # or, with fancyfx installed, the effect curve with a rug of the raw data:
#' fancyfx::plotEffects(fit, data.frame(sst = as.vector(sst_avg$sst)), "sst")
#' }
#' @exportS3Method fancyfx::effect_estimates
effect_estimates.msomgom_fit <- function(model, var,
                                          scale = c("auto", "link", "response"),
                                          interval = c("auto", "se", "ci", "cri"),
                                          level = 0.95,
                                          n = 100,
                                          ...) {
  scale <- match.arg(scale)
  interval <- match.arg(interval)
  if (interval == "cri") interval <- "ci"
  if (!is.numeric(level) || length(level) != 1 || is.na(level) || level <= 0 || level >= 1) {
    stop("level must be a single number strictly between 0 and 1, not: ", level)
  }

  hit <- msomgom_covariate_lookup(model, var)

  z_mat <- as.matrix(model)
  intercept_col <- paste0("mu.", hit$prefix, ".0")
  # rjags/dclone drop the bracket index for a length-1 vector node - the
  # tracked column is bare "mu.<prefix>.cov", not "mu.<prefix>.cov[1]" - but
  # keep the brackets for n_cov > 1, where every element gets one
  coef_col <- if (hit$n_cov == 1) {
    paste0("mu.", hit$prefix, ".cov")
  } else {
    paste0("mu.", hit$prefix, ".cov[", hit$index, "]")
  }
  missing_cols <- setdiff(c(intercept_col, coef_col), colnames(z_mat))
  if (length(missing_cols) > 0) {
    stop("model doesn't track ", paste(missing_cols, collapse = ", "), " - ",
         "re-fit with jags_params = \"colext\" (the default) to track covariate ",
         "coefficients; jags_params = \"Z\" only tracks occupancy states.")
  }

  # Every msomgom fit is summarized from posterior draws, so "auto" behaves
  # the way fancyfx treats a Bayesian (brms/rstanarm) fit: a credible
  # interval, not a +/- 1 SE ribbon built from something that isn't there.
  if (interval == "auto") interval <- "ci"
  if (scale == "auto") scale <- "link"

  grid <- seq(hit$min, hit$max, length.out = n)
  grid_std <- (grid - hit$mean) / hit$sd

  intercept_draws <- z_mat[, intercept_col]
  coef_draws <- z_mat[, coef_col]
  # [n draws x n grid points]: row i is posterior draw i's curve across the grid
  linpred_draws <- outer(coef_draws, grid_std, FUN = "*")

  if (scale == "response") {
    pred_draws <- stats::plogis(intercept_draws + linpred_draws)
    quantity <- "Predicted Occupancy Probability"
  } else {
    pred_draws <- linpred_draws
    quantity <- "Partial Effect (logit scale)"
  }

  est <- colMeans(pred_draws)
  if (interval == "se") {
    se <- apply(pred_draws, 2, stats::sd)
    lower <- est - se
    upper <- est + se
  } else {
    qs <- apply(pred_draws, 2, stats::quantile, probs = c((1 - level) / 2, 1 - (1 - level) / 2))
    lower <- qs[1, ]
    upper <- qs[2, ]
  }

  out <- data.frame(.x = grid, .estimate = est, .lower = lower, .upper = upper)
  attr(out, "quantity") <- quantity
  out
}

#' Look up a covariate's metadata on a fitted model
#'
#' @param model an object from `fit_occupancy_model()`
#' @param var covariate name
#' @return one row of `attr(model, "msomgom_covariates")`
#' @seealso [effect_estimates.msomgom_fit()], the only caller
#' @keywords internal
msomgom_covariate_lookup <- function(model, var) {
  meta <- attr(model, "msomgom_covariates")
  if (is.null(meta) || nrow(meta) == 0) {
    stop("model has no covariate metadata; effect_estimates() only works on a fit from ",
         "fit_occupancy_model() that was run with occ_covariates (config$covariates$psi/phi/gamma).")
  }
  hit <- meta[meta$name == var, , drop = FALSE]
  if (nrow(hit) == 0) {
    stop("'", var, "' is not a covariate this model was fit with. Available: ",
         paste(unique(meta$name), collapse = ", "))
  }
  if (nrow(hit) > 1) {
    stop("'", var, "' is configured on more than one process (",
         paste(hit$process, collapse = ", "), "); effect_estimates() needs it on exactly one.")
  }
  hit
}
