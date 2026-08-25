skip_if_not_installed("coda")

# A fit whose draws are known exactly, so every reported number is checkable
# by hand. mu.b.0 = 0 -> psi 0.5; mu.e.0 = qlogis(0.8) -> phi 0.8;
# mu.g.0 = qlogis(0.1) -> gamma 0.1; mu.a.0 = qlogis(0.25) -> p 0.25.
make_known_fit <- function(n = 200, jitter = 0.01, seed = 1) {
  set.seed(seed)
  cols <- c("mu.b.0", "mu.e.0", "mu.g.0", "mu.a.0", "mu.a.bft")
  centres <- c(0, stats::qlogis(0.8), stats::qlogis(0.1), stats::qlogis(0.25), 0.5)
  m <- sapply(seq_along(cols), function(i) rnorm(n, centres[i], jitter))
  colnames(m) <- cols
  fit <- coda::mcmc.list(coda::mcmc(m), coda::mcmc(m))
  class(fit) <- c("dynocc_fit", class(fit))
  fit
}

test_that("intercepts come back on the probability scale", {
  s <- occupancy_summary(make_known_fit())

  psi <- s$parameters[s$parameters$parameter == "psi", ]
  expect_equal(psi$mean, 0.5, tolerance = 0.01)
  expect_equal(psi$scale, "probability")

  phi <- s$parameters[s$parameters$parameter == "phi", ]
  expect_equal(phi$mean, 0.8, tolerance = 0.01)
})

test_that("equilibrium occupancy and turnover match the closed form", {
  s <- occupancy_summary(make_known_fit())

  # phi 0.8, gamma 0.1 -> psi_eq = 0.1 / (0.1 + 0.2) = 1/3
  eq <- s$derived[s$derived$quantity == "equilibrium occupancy", ]
  expect_equal(eq$mean, 1 / 3, tolerance = 0.01)

  # turnover = gamma * (1 - psi_eq) / psi_eq = 0.1 * (2/3) / (1/3) = 0.2
  turn <- s$derived[s$derived$quantity == "turnover", ]
  expect_equal(turn$mean, 0.2, tolerance = 0.01)
})

test_that("cumulative detection compounds over the visits given", {
  s <- occupancy_summary(make_known_fit(), visits = 3)

  one <- s$derived[s$derived$quantity == "detection, one visit", ]
  expect_equal(one$mean, 0.25, tolerance = 0.01)

  many <- s$derived[s$derived$quantity == "detection, 3 visits", ]
  expect_equal(many$mean, 1 - 0.75^3, tolerance = 0.01) # 0.578
})

test_that("visits default to a typical surveyed cell-season", {
  arrays <- list(reps = matrix(c(0, 0, 4, 4, 4, 10), nrow = 2))
  s <- occupancy_summary(make_known_fit(), arrays = arrays)
  expect_equal(s$visits, 4) # median of the non-zero entries
})

test_that("a parameter whose posterior is its prior is flagged, not reported", {
  # sd 3.16 draws = exactly the dnorm(0, 0.1) prior, which is what an
  # unidentified parameter returns - and it looks perfectly converged
  set.seed(2)
  m <- cbind("mu.b.0" = rnorm(4000, 0, 0.05),
             "mu.e.0" = rnorm(4000, 0, dynocc_prior_sd()))
  fit <- coda::mcmc.list(coda::mcmc(m), coda::mcmc(m))
  class(fit) <- c("dynocc_fit", class(fit))

  s <- occupancy_summary(fit)
  expect_true(s$parameters$learned[s$parameters$parameter == "psi"])
  expect_false(s$parameters$learned[s$parameters$parameter == "phi"])
  expect_output(print(s), "Posterior ~= prior for")
  expect_output(print(s), "phi")
})

test_that("slopes stay on the log-odds scale, since a slope is not a probability", {
  s <- occupancy_summary(make_known_fit())

  bft <- s$parameters[s$parameters$parameter == "mu.a.bft", ]
  expect_equal(bft$scale, "log-odds per SD")
  expect_equal(bft$mean, 0.5, tolerance = 0.01) # not plogis(0.5)
})

test_that("transformation happens on draws, not on summaries", {
  # a wide posterior centred at 0: mean(plogis(x)) is 0.5 but the interval is
  # what separates the two approaches - plogis(quantile) == quantile(plogis)
  # only because plogis is monotone, so check the mean of a skewed case
  set.seed(3)
  m <- cbind("mu.b.0" = rnorm(8000, 2, 2))
  fit <- coda::mcmc.list(coda::mcmc(m), coda::mcmc(m))
  class(fit) <- c("dynocc_fit", class(fit))

  s <- occupancy_summary(fit)
  expect_equal(s$parameters$mean[1], mean(stats::plogis(m[, 1])), tolerance = 0.01)
  expect_false(isTRUE(all.equal(s$parameters$mean[1], stats::plogis(2), tolerance = 0.01)))
})

test_that("a Z fit is refused by name", {
  m <- cbind("Z[1,1,1]" = rbinom(50, 1, 0.5))
  fit <- coda::mcmc.list(coda::mcmc(m), coda::mcmc(m))
  class(fit) <- c("dynocc_fit", class(fit))

  expect_error(occupancy_summary(fit), "colext")
})

test_that("a single visit does not report the same number twice", {
  s <- occupancy_summary(make_known_fit(), visits = 1)
  expect_true("detection, one visit" %in% s$derived$quantity)
  expect_false(any(grepl("1 visits", s$derived$quantity)))
})
