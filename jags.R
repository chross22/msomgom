# Fits a dynamic (colonization/persistence) occupancy model in JAGS for one
# configured species, using the detection-history and covariate arrays from
# jagsPrep.R::build_detection_arrays().
#
# The model itself (whale.mod below) and its "each array slice along the 3rd
# dimension is treated as its own year, with numseasons fixed at 1" structure
# are unchanged from the original single-species model - only the species
# selection, MCMC settings, and output path are config-driven. Extending this
# to a true hierarchical multi-species model (fitting all configured species
# jointly with shared priors) is a deliberately separate follow-up.
#
# Returns the jags.parfit() result.

fit_occupancy_model <- function(arrays, config) {
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

  psi.naive <- table(apply(dets4d, c(1, 3, 4), max, na.rm = TRUE))[3] / (table(apply(dets4d, c(1, 3, 4), max, na.rm = TRUE))[3] + table(apply(dets4d, c(1, 3, 4), max, na.rm = TRUE))[2])
  z.naive <- apply(dets4d, MARGIN = c(1, 3, 4), max, na.rm = TRUE)
  z.naive[z.naive == "-Inf"] <- rbinom(n = sum(z.naive == "-Inf"), size = 1, prob = psi.naive)
  inits <- list(Z = z.naive)

  ##### Model specification #####

  whale.mod <- function() {

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

      ### Process & Observation model of points
      for (j in 1:n.site) {

        # Occupancy for season 1 in each year, but no covariates here
        logit(psi[j, 1, t]) <- b.0[t]
        Z[j, 1, t] ~ dbin(psi[j, 1, t], 1)

        # Detectability for season 1 in each year
        for (k in 1:n.visit) {
          logit(p[j, k, 1, t]) <- a.0[t] + a.jday[t] * jday[j, k, 1, t] + a.bft[t] * bft[j, k, 1, t] + a.eff[t] * eff[j, k, 1, t]
          mu.p[j, k, 1, t] <- p[j, k, 1, t] * Z[j, 1, t]
          y[j, k, 1, t] ~ dbin(mu.p[j, k, 1, t], 1)
        }

        # Colonization & persistence for seasons 2-N in each year
        for (l in 2:n.season) {

          logit(phi[j, l - 1, t]) <- e.0[t]
          logit(gamma[j, l - 1, t]) <- g.0[t]
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

  nc <- config$jags$n_chains
  n.adapt <- config$jags$n_adapt
  n.burn <- config$jags$n_burn
  n.iter <- config$jags$n_iter
  thin <- config$jags$thin

  parSelect <- config$jags$params
  if (parSelect == "colext") {
    pars <- c("mu.b.0", "mu.a.0", "mu.a.jday", "mu.a.bft", "mu.a.eff", "mu.g.0", "mu.e.0")
  } else if (parSelect == "Z") {
    pars <- c("Z")
  }

  ### Parallelize across chains ##
  start.time <- Sys.time()
  cl <- makePSOCKcluster(nc)
  tmp <- clusterEvalQ(cl, library(dclone))
  parLoadModule(cl, "glm")
  parListModules(cl)
  whale.pars <- jags.parfit(cl, jags.data, params = pars, whale.mod, inits = inits, n.chains = nc,
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
