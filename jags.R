#' Fit the dynamic occupancy model
#'
#' Fits a dynamic (colonization/persistence) occupancy model in JAGS for one
#' configured species, using the detection-history and covariate arrays from
#' `jagsPrep.R::build_detection_arrays()`.
#'
#' Detection probability (`p`) has always had covariates (jday/bft/eff); this
#' also supports environmental covariates on initial occupancy (`psi`),
#' persistence (`phi`), and colonization (`gamma`) - config-driven, and each
#' process independently gets zero or more covariates, fed by
#' `average_covariates.R`'s per-site/per-season/year arrays.
#'
#' The "each array slice along the 3rd dimension is treated as its own year,
#' with numseasons fixed at 1" structure is unchanged from the original
#' single-species model. Extending this to a true hierarchical multi-species
#' model (fitting all configured species jointly with shared priors) is a
#' deliberately separate follow-up.
#'
#' @param arrays the list returned by `build_detection_arrays()`
#' @param config a config list, as returned by `load_config()`
#' @param occ_covariates optional named list of `[num_cells x num_ssn]`
#'   matrices (e.g. `average_covariates()`'s return value). `config$covariates$psi/phi/gamma`
#'   each list which of those names apply to that process; a process with no
#'   covariates configured is modeled exactly as it was before this existed
#'   (intercept-only). JAGS can't compile a zero-length covariate loop, so the
#'   model text is generated per-run (see `build_whale_model_code()`) rather
#'   than being one static model.
#' @return the `jags.parfit()` result (an `mcmc.list`)
#' @references The model follows MacKenzie et al. (2003), \emph{Estimating
#'   site occupancy, colonization, and local extinction when a species is
#'   detected imperfectly}, Ecology 84:2200-2207
#'   (\doi{10.1890/02-3090}), an extension of the single-season detection
#'   model of MacKenzie et al. (2002), Ecology 83:2248-2255. Fit with JAGS
#'   (Plummer 2003).
#' @seealso [build_detection_arrays()], which produces `arrays`;
#'   [average_covariates()], which produces suitable `occ_covariates`;
#'   [evaluate_occupancy_model()], the next pipeline stage;
#'   [build_whale_model_code()] for how the BUGS model text itself is generated
#' @family pipeline stages
#' @examples
#' \dontrun{
#' config <- load_config("configs/bof_riwh.yaml")
#' prep <- prep_survey_data(config)
#' arrays <- build_detection_arrays(prep$tmpdat, prep$season_info, config)
#'
#' # no environmental covariates
#' fit <- fit_occupancy_model(arrays, config)
#'
#' # with covariates on psi/phi (config$covariates$psi/phi must list "sst")
#' fit <- fit_occupancy_model(arrays, config, occ_covariates = list(sst = sst_avg$sst))
#' }
fit_occupancy_model <- function(arrays, config, occ_covariates = NULL) {
  library(R2jags)
  library(rjags)
  library(dclone) # built-in functionality for parallel MCMC with jags via jags.parfit()

  species_code <- config$species$active
  if (!(species_code %in% names(arrays$species_arrays))) {
    stop("species.active ('", species_code, "') has no detection array; check species.codes in the config.")
  }

  max_survs <- arrays$max_survs
  bft3d <- arrays$bft3d
  jday3d <- arrays$jday3d
  effort3d <- arrays$effort3d

  # prepare data
  spp3d_01 <- arrays$species_arrays[[species_code]]
  I <- which(spp3d_01 > 1)
  spp3d_01[I] <- 1

  dets <- spp3d_01[, 2:(max_survs + 1), ]
  bft <- bft3d[, 2:(max_survs + 1), ]
  jday <- jday3d[, 2:(max_survs + 1), ]
  eff <- effort3d[, 2:(max_survs + 1), ]

  # count seasons, sites, years, visits
  numseasons <- 1
  n.season <- numseasons
  n.site <- dim(dets)[1]
  n.year <- dim(dets)[3] / numseasons
  n.visit <- dim(dets)[2]

  # standardize covariates (mean = 0, sd = 1, all NA converted to 0)
  bft.st <- (bft - mean(bft, na.rm = TRUE)) / sd(bft, na.rm = TRUE)
  bft.st[is.na(bft.st)] <- 0
  jday.st <- (jday - mean(jday, na.rm = TRUE)) / sd(jday, na.rm = TRUE)
  jday.st[is.na(jday.st)] <- 0
  eff.st <- (eff - mean(eff, na.rm = TRUE)) / sd(eff, na.rm = TRUE)
  eff.st[is.na(eff.st)] <- 0

  y.array <- array(dim = c(n.site, n.visit, n.season, n.year))
  dets4d <- array(dim = dim(y.array), data = as.vector(dets))
  bft4d <- array(dim = dim(y.array), data = as.vector(bft.st))
  jday4d <- array(dim = dim(y.array), data = as.vector(jday.st))
  eff4d <- array(dim = dim(y.array), data = as.vector(eff.st))

  ############## Occupancy-process (psi/phi/gamma) covariates #####################

  process_covariate_array <- function(process_name) {
    cov_names <- unlist(config$covariates[[process_name]])
    if (is.null(cov_names) || length(cov_names) == 0) {
      return(list(n_cov = 0, array = NULL))
    }
    missing_names <- setdiff(cov_names, names(occ_covariates))
    if (length(missing_names) > 0) {
      stop("config$covariates$", process_name, " references covariate(s) not found in occ_covariates: ",
           paste(missing_names, collapse = ", "))
    }
    n_cov <- length(cov_names)
    out <- array(dim = c(n.site, n.season, n.year, n_cov))
    for (c_idx in seq_len(n_cov)) {
      mat <- occ_covariates[[cov_names[c_idx]]] # [num_cells x num_ssn]
      mat.st <- (mat - mean(mat, na.rm = TRUE)) / sd(mat, na.rm = TRUE)
      mat.st[is.na(mat.st)] <- 0
      out[, , , c_idx] <- array(dim = c(n.site, n.season, n.year), data = as.vector(mat.st))
    }
    list(n_cov = n_cov, array = out)
  }

  psi_cov <- process_covariate_array("psi")
  phi_cov <- process_covariate_array("phi")
  gamma_cov <- process_covariate_array("gamma")

  ############## JAGS Model & Run #####################

  jags.data <- list(y = dets4d,
                     bft = bft4d,
                     jday = jday4d,
                     eff = eff4d,
                     n.site = n.site,
                     n.season = n.season,
                     n.visit = n.visit,
                     n.year = n.year
  )
  if (psi_cov$n_cov > 0) jags.data$cov.psi <- psi_cov$array
  if (phi_cov$n_cov > 0) jags.data$cov.phi <- phi_cov$array
  if (gamma_cov$n_cov > 0) jags.data$cov.gamma <- gamma_cov$array
  if (psi_cov$n_cov > 0) jags.data$n.cov.psi <- psi_cov$n_cov
  if (phi_cov$n_cov > 0) jags.data$n.cov.phi <- phi_cov$n_cov
  if (gamma_cov$n_cov > 0) jags.data$n.cov.gamma <- gamma_cov$n_cov

  psi.naive <- table(apply(dets4d, c(1, 3, 4), max, na.rm = TRUE))[3] / (table(apply(dets4d, c(1, 3, 4), max, na.rm = TRUE))[3] + table(apply(dets4d, c(1, 3, 4), max, na.rm = TRUE))[2])
  z.naive <- apply(dets4d, MARGIN = c(1, 3, 4), max, na.rm = TRUE)
  z.naive[z.naive == "-Inf"] <- rbinom(n = sum(z.naive == "-Inf"), size = 1, prob = psi.naive)
  inits <- list(Z = z.naive)

  ##### Model specification #####
  # Generated as text rather than a static R function: JAGS can't compile a
  # for-loop/inprod() over a zero-length covariate dimension (confirmed by
  # testing - it errors with "Unknown variable" rather than treating a
  # 1:0-length loop as a no-op), so a process with no configured covariates
  # needs its covariate block omitted from the model text entirely, not just
  # zeroed out in the data.
  model_code <- build_whale_model_code(psi_cov$n_cov, phi_cov$n_cov, gamma_cov$n_cov)
  model_file <- tempfile(fileext = ".bug")
  writeLines(model_code, model_file)

  nc <- config$jags$n_chains
  n.adapt <- config$jags$n_adapt
  n.burn <- config$jags$n_burn
  n.iter <- config$jags$n_iter
  thin <- config$jags$thin

  parSelect <- config$jags$params
  if (parSelect == "colext") {
    pars <- c("mu.b.0", "mu.a.0", "mu.a.jday", "mu.a.bft", "mu.a.eff", "mu.g.0", "mu.e.0")
    if (psi_cov$n_cov > 0) pars <- c(pars, "mu.b.cov")
    if (phi_cov$n_cov > 0) pars <- c(pars, "mu.e.cov")
    if (gamma_cov$n_cov > 0) pars <- c(pars, "mu.g.cov")
  } else if (parSelect == "Z") {
    pars <- c("Z")
  }

  ### Parallelize across chains ##
  start.time <- Sys.time()
  cl <- makePSOCKcluster(nc)
  tmp <- clusterEvalQ(cl, library(dclone))
  parLoadModule(cl, "glm")
  parListModules(cl)
  whale.pars <- jags.parfit(cl, jags.data, params = pars, model_file, inits = inits, n.chains = nc,
                            n.adapt = n.adapt, n.update = n.burn, thin = thin, n.iter = n.iter)
  stopCluster(cl)
  end.time <- Sys.time()
  elapsed.time <- difftime(end.time, start.time, units = "mins")
  print(elapsed.time)

  if (isTRUE(config$jags$save_results)) {
    output_dir <- config$paths$output_dir
    if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)
    fn <- file.path(output_dir, paste0(species_code, ".", parSelect, ".RData"))
    save(whale.pars, file = fn)
    save(elapsed.time, file = file.path(output_dir, "elapsedtime.RData"))
  }

  whale.pars
}

#' Generate the BUGS/JAGS model code
#'
#' Builds the BUGS/JAGS model code for the dynamic occupancy model, with
#' covariate blocks on psi/phi/gamma included only for processes that have
#' `n_cov_* > 0` (see `fit_occupancy_model()`'s documentation for why). With
#' `n_cov_psi = n_cov_phi = n_cov_gamma = 0`, this generates exactly the
#' original intercept-only model.
#'
#' @param n_cov_psi number of covariates on initial occupancy (`psi`)
#' @param n_cov_phi number of covariates on persistence (`phi`)
#' @param n_cov_gamma number of covariates on colonization (`gamma`)
#' @return character string of BUGS/JAGS model code, ready to `writeLines()` to a `.bug` file
#' @seealso [fit_occupancy_model()], which calls this internally
#' @family pipeline stages
#' @examples
#' cat(build_whale_model_code(0, 0, 0))       # intercept-only, the original model
#' cat(build_whale_model_code(1, 0, 2))       # 1 covariate on psi, 2 on gamma, none on phi
build_whale_model_code <- function(n_cov_psi, n_cov_phi, n_cov_gamma) {
  # coef_prefix (b/e/g) names the coefficients, matching the existing
  # b.0/e.0/g.0 intercept convention for psi/phi/gamma respectively.
  # process (psi/phi/gamma) names the n.cov.<process>/cov.<process> data
  # arrays, matching how fit_occupancy_model() builds jags.data.
  cov_priors <- function(n_cov, coef_prefix, process) {
    if (n_cov == 0) return("")
    sprintf("
    for (c in 1:n.cov.%s) {
      mu.%s.cov[c] ~ dnorm(0, 0.1)
      tau.%s.cov[c] ~ dgamma(0.1, 0.1)
    }", process, coef_prefix, coef_prefix)
  }
  cov_year_effects <- function(n_cov, coef_prefix, process) {
    if (n_cov == 0) return("")
    sprintf("
      for (c in 1:n.cov.%s) {
        %s.cov[t, c] ~ dnorm(mu.%s.cov[c], tau.%s.cov[c])
      }", process, coef_prefix, coef_prefix, coef_prefix)
  }
  cov_term <- function(n_cov, coef_prefix, process, season_index) {
    if (n_cov == 0) return("")
    sprintf(" + inprod(%s.cov[t, 1:n.cov.%s], cov.%s[j, %s, t, 1:n.cov.%s])",
            coef_prefix, process, process, season_index, process)
  }

  psi_priors <- cov_priors(n_cov_psi, "b", "psi")
  phi_priors <- cov_priors(n_cov_phi, "e", "phi")
  gamma_priors <- cov_priors(n_cov_gamma, "g", "gamma")

  psi_year <- cov_year_effects(n_cov_psi, "b", "psi")
  phi_year <- cov_year_effects(n_cov_phi, "e", "phi")
  gamma_year <- cov_year_effects(n_cov_gamma, "g", "gamma")

  psi_term <- cov_term(n_cov_psi, "b", "psi", "1")
  phi_term <- cov_term(n_cov_phi, "e", "phi", "l - 1")
  gamma_term <- cov_term(n_cov_gamma, "g", "gamma", "l - 1")

  sprintf('
model {

  ## Priors

  # Priors on annual random effects
  mu.b.0 ~ dnorm(0, 0.1)
  tau.b.0 ~ dgamma(0.1, 0.1)

  mu.a.0 ~ dnorm(0, 0.1)
  tau.a.0 ~ dgamma(0.1, 0.1)

  mu.a.bft ~ dnorm(0, 0.1)
  tau.a.bft ~ dgamma(0.1, 0.1)

  mu.a.jday ~ dnorm(0, 0.1)
  tau.a.jday ~ dgamma(0.1, 0.1)

  mu.a.eff ~ dnorm(0, 0.1)
  tau.a.eff ~ dgamma(0.1, 0.1)

  mu.g.0 ~ dnorm(0, 0.1)
  tau.g.0 ~ dgamma(0.1, 0.1)

  mu.e.0 ~ dnorm(0, 0.1)
  tau.e.0 ~ dgamma(0.1, 0.1)
  %s
  %s
  %s

  ### Hierarchically loop over each year
  for (t in 1:n.year) {

    # Year-specific hierarchical effects
    b.0[t] ~ dnorm(mu.b.0, tau.b.0)
    a.0[t] ~ dnorm(mu.a.0, tau.a.0)
    a.jday[t] ~ dnorm(mu.a.jday, tau.a.jday)
    a.bft[t] ~ dnorm(mu.a.bft, tau.a.bft)
    a.eff[t] ~ dnorm(mu.a.eff, tau.a.eff)

    g.0[t] ~ dnorm(mu.g.0, tau.g.0)
    e.0[t] ~ dnorm(mu.e.0, tau.e.0)
    %s
    %s
    %s

    ### Process & Observation model of points
    for (j in 1:n.site) {

      # Occupancy for season 1 in each year
      logit(psi[j, 1, t]) <- b.0[t]%s
      Z[j, 1, t] ~ dbin(psi[j, 1, t], 1)

      # Detectability for season 1 in each year
      for (k in 1:n.visit) {
        logit(p[j, k, 1, t]) <- a.0[t] + a.jday[t] * jday[j, k, 1, t] + a.bft[t] * bft[j, k, 1, t] + a.eff[t] * eff[j, k, 1, t]
        mu.p[j, k, 1, t] <- p[j, k, 1, t] * Z[j, 1, t]
        y[j, k, 1, t] ~ dbin(mu.p[j, k, 1, t], 1)
      }

      # Colonization & persistence for seasons 2-N in each year
      for (l in 2:n.season) {

        logit(phi[j, l - 1, t]) <- e.0[t]%s
        logit(gamma[j, l - 1, t]) <- g.0[t]%s
        psi[j, l, t] <- phi[j, l - 1, t] * Z[j, l - 1, t] + gamma[j, l - 1, t] * (1 - Z[j, l - 1, t])
        Z[j, l, t] ~ dbin(psi[j, l, t], 1)

        # Detectability for seasons 2-N in each year
        for (k in 1:n.visit) {
          logit(p[j, k, l, t]) <- a.0[t] + a.jday[t] * jday[j, k, l, t] + a.bft[t] * bft[j, k, l, t] + a.eff[t] * eff[j, k, l, t]
          mu.p[j, k, l, t] <- p[j, k, l, t] * Z[j, l, t]
          y[j, k, l, t] ~ dbin(mu.p[j, k, l, t], 1)
        }
      }
    }
  }
}
', psi_priors, phi_priors, gamma_priors, psi_year, phi_year, gamma_year, psi_term, phi_term, gamma_term)
}
