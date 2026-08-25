# --- interpreting a fit -----------------------------------------------------
#
# A colext fit's parameters are logit-scale hyper-means, which is the shape
# JAGS needs and the wrong shape for reading. Everything here converts draws
# (not summaries) to the probability scale, derives the quantities that answer
# the questions people actually ask of a dynamic occupancy model, and checks
# each parameter against its prior - because a posterior that IS its prior is
# the one failure that looks like perfect convergence.

# Every mu.* in build_whale_model_code() gets dnorm(0, 0.1); JAGS's second
# argument is precision, so the prior SD is 1/sqrt(0.1).
dynocc_prior_sd <- function() sqrt(1 / 0.1)

#' Summarize a fit the way it is read, not the way it was fit
#'
#' Converts a `"colext"` fit's logit-scale hyper-means to probabilities,
#' derives the quantities a dynamic occupancy model is usually asked for
#' (equilibrium occupancy, turnover, cumulative detection), and flags any
#' parameter whose posterior barely moved from its prior.
#'
#' Every transformation is applied to the posterior draws and summarized
#' afterwards, never to the summaries - `plogis(mean(x))` is not
#' `mean(plogis(x))`, and the difference is largest exactly where the
#' posterior is widest.
#'
#' @section What is reported:
#' The parameter table gives each hyper-mean on the probability scale
#' (`psi`, `phi`, `gamma`, `p`), and any covariate coefficient on its own
#' scale - log-odds per standard deviation of the covariate, since
#' `fit_occupancy_model()` standardizes covariates before fitting, and since
#' a slope is not a probability.
#'
#' The derived table answers:
#' \itemize{
#'   \item **equilibrium occupancy**, `gamma / (gamma + (1 - phi))` - where
#'     occupancy settles if these dynamics ran indefinitely. Read against the
#'     estimated initial occupancy: far apart means the system is not at
#'     steady state over the seasons modeled.
#'   \item **turnover**, `gamma * (1 - psi_eq) / psi_eq` - the share of
#'     occupied cells that were empty the season before. High turnover with
#'     high persistence is a different system than either alone, and average
#'     occupancy cannot tell them apart.
#'   \item **cumulative detection**, `1 - (1 - p)^visits` - the chance of
#'     seeing the species at least once in an occupied cell over a season's
#'     visits. This is the number that says how badly naive occupancy
#'     understates the truth.
#' }
#'
#' @section The prior check:
#' `contraction` is `1 - sd(posterior) / sd(prior)` on the logit scale. Near
#' 1, the data determined the parameter; near 0, the posterior is the prior
#' wearing a posterior's name - which arrives looking like flawless
#' convergence (`Rhat` 1.00, every draw effective) because sampling a prior
#' is easy. `learned` is `FALSE` below `threshold`, and those parameters
#' should not be interpreted, whatever their credible interval says.
#'
#' @param fit a `dynocc_fit` from [fit_occupancy_model()] with
#'   `jags_params = "colext"` (the default) - a `"Z"` fit tracks states, not
#'   the coefficients this reads
#' @param arrays optionally the list from [build_detection_arrays()], used
#'   only to take a realistic number of visits per surveyed cell-season for
#'   the cumulative-detection row
#' @param visits number of visits for cumulative detection; defaults to the
#'   median over surveyed cell-seasons in `arrays`, or 3 if `arrays` is not
#'   given
#' @param level credible-interval level (default 0.95)
#' @param threshold contraction below which a parameter is reported as not
#'   learned (default 0.05)
#' @return an object of class `dynocc_summary`: a list of `parameters` and
#'   `derived` data.frames, both with `mean`/`lower`/`upper` columns, plus
#'   `visits` and `level`. Has a `print()` method
#' @seealso [evaluate_occupancy_model()] for convergence and the
#'   naive-vs-modeled comparison; [plot_convergence()], which should be read
#'   before this; [plot_process_map()] for the same estimates in space
#' @family pipeline stages
#' @examples
#' \dontrun{
#' fit <- fit_occupancy_model(arrays, config)
#' occupancy_summary(fit, arrays)
#' }
#' @export
occupancy_summary <- function(fit, arrays = NULL, visits = NULL,
                              level = 0.95, threshold = 0.05) {
  if (!is.numeric(level) || length(level) != 1 || is.na(level) || level <= 0 || level >= 1) {
    stop("level must be a single number strictly between 0 and 1, not: ", level)
  }
  draws <- as.matrix(fit)
  probs <- c((1 - level) / 2, 1 - (1 - level) / 2)
  prior_sd <- dynocc_prior_sd()

  intercepts <- c(psi = "mu.b.0", phi = "mu.e.0", gamma = "mu.g.0", p = "mu.a.0")
  found <- intercepts[intercepts %in% colnames(draws)]
  if (!length(found)) {
    stop("This fit tracks none of ", paste(intercepts, collapse = ", "),
         " - occupancy_summary() reads a \"colext\" fit (the default). A ",
         "\"Z\" fit tracks occupancy states instead; see plot_occupancy_map() ",
         "and evaluate_occupancy_model() for those.", call. = FALSE)
  }

  row_for <- function(name, x, logit_draws, scale) {
    qs <- stats::quantile(x, probs = probs, names = FALSE)
    contraction <- 1 - stats::sd(logit_draws) / prior_sd
    data.frame(parameter = name, scale = scale, mean = mean(x),
               lower = qs[1], upper = qs[2],
               contraction = contraction, learned = contraction >= threshold,
               stringsAsFactors = FALSE)
  }

  parameters <- do.call(rbind, lapply(names(found), function(nm) {
    logit_draws <- draws[, found[[nm]]]
    row_for(nm, stats::plogis(logit_draws), logit_draws, "probability")
  }))

  # Detection slopes and any covariate coefficients stay on the logit scale:
  # a slope is not a probability, and the covariate was standardized, so the
  # unit is one standard deviation of it.
  slope_cols <- grep("^mu\\.(a\\.(jday|bft|eff)|[beg]\\.cov)", colnames(draws), value = TRUE)
  if (length(slope_cols)) {
    parameters <- rbind(parameters, do.call(rbind, lapply(slope_cols, function(cl) {
      row_for(cl, draws[, cl], draws[, cl], "log-odds per SD")
    })))
  }
  rownames(parameters) <- NULL

  # --- derived, per draw so the intervals propagate -------------------------
  if (is.null(visits)) {
    visits <- if (!is.null(arrays) && !is.null(arrays$reps)) {
      surveyed <- arrays$reps[arrays$reps > 0]
      if (length(surveyed)) stats::median(surveyed) else 3
    } else 3
  }

  derived <- NULL
  add_derived <- function(d, name, x, note) {
    qs <- stats::quantile(x, probs = probs, names = FALSE)
    rbind(d, data.frame(quantity = name, mean = mean(x), lower = qs[1],
                        upper = qs[2], note = note, stringsAsFactors = FALSE))
  }

  has <- function(nm) nm %in% names(found)
  if (has("phi") && has("gamma")) {
    phi <- stats::plogis(draws[, intercepts[["phi"]]])
    gamma <- stats::plogis(draws[, intercepts[["gamma"]]])
    psi_eq <- gamma / (gamma + (1 - phi))
    derived <- add_derived(derived, "equilibrium occupancy", psi_eq,
                           "where occupancy settles if these dynamics persisted")
    derived <- add_derived(derived, "turnover", gamma * (1 - psi_eq) / psi_eq,
                           "share of occupied cells that were empty the season before")
  }
  if (has("p")) {
    p <- stats::plogis(draws[, intercepts[["p"]]])
    derived <- add_derived(derived, "detection, one visit", p,
                           "chance of seeing the species on a single survey of an occupied cell")
    # With a single visit the cumulative row is the same number twice, which
    # reads as a bug rather than as arithmetic.
    if (visits > 1) {
      derived <- add_derived(derived, paste0("detection, ", visits, " visits"),
                             1 - (1 - p)^visits,
                             "chance of at least one detection across a season's visits")
    }
  }
  if (!is.null(derived)) rownames(derived) <- NULL

  structure(list(parameters = parameters, derived = derived,
                 visits = visits, level = level, threshold = threshold),
            class = "dynocc_summary")
}

#' @param x a `dynocc_summary`
#' @param digits significant digits for the reported numbers
#' @param ... ignored
#' @rdname occupancy_summary
#' @export
print.dynocc_summary <- function(x, digits = 3, ...) {
  pct <- paste0(round(x$level * 100), "%")

  cat("\n=== What the model estimates (", pct, " credible intervals) ===\n", sep = "")
  params <- x$parameters
  params$contraction <- round(params$contraction, 2)
  print(format(params, digits = digits), row.names = FALSE)

  if (!is.null(x$derived)) {
    cat("\n=== What that implies ===\n")
    print(format(x$derived[, c("quantity", "mean", "lower", "upper")], digits = digits),
          row.names = FALSE)
    cat("\n")
    for (i in seq_len(nrow(x$derived))) {
      cat("  ", x$derived$quantity[i], ": ", x$derived$note[i], "\n", sep = "")
    }
  }

  unlearned <- x$parameters$parameter[!x$parameters$learned]
  if (length(unlearned)) {
    cat("\n!! Posterior ~= prior for: ", paste(unlearned, collapse = ", "), "\n",
        "   These parameters were not informed by the data (contraction < ",
        x$threshold, "). They will look perfectly converged - sampling a prior\n",
        "   is easy - and they should not be interpreted. Check that the ",
        "detection\n   history has records in the relevant seasons.\n", sep = "")
  }
  invisible(x)
}
