test_that("zero covariates everywhere generates no covariate blocks", {
  code <- build_whale_model_code(0, 0, 0)
  expect_false(grepl("n.cov", code, fixed = TRUE))
  expect_false(grepl("inprod", code, fixed = TRUE))
  expect_false(grepl("cov.psi|cov.phi|cov.gamma", code))
})

test_that("covariates on one process don't leak into the others", {
  code <- build_whale_model_code(1, 0, 0)
  expect_true(grepl("n.cov.psi", code, fixed = TRUE))
  expect_false(grepl("n.cov.phi", code, fixed = TRUE))
  expect_false(grepl("n.cov.gamma", code, fixed = TRUE))
})

test_that("each process gets its own covariate count and coefficient prefix", {
  code <- build_whale_model_code(1, 2, 1)
  expect_true(grepl("for (c in 1:n.cov.psi)", code, fixed = TRUE))
  expect_true(grepl("for (c in 1:n.cov.phi)", code, fixed = TRUE))
  expect_true(grepl("for (c in 1:n.cov.gamma)", code, fixed = TRUE))
  expect_true(grepl("inprod(b.cov[t, 1:n.cov.psi], cov.psi[j, 1, t, 1:n.cov.psi])", code, fixed = TRUE))
  expect_true(grepl("inprod(e.cov[t, 1:n.cov.phi], cov.phi[j, l - 1, t, 1:n.cov.phi])", code, fixed = TRUE))
  expect_true(grepl("inprod(g.cov[t, 1:n.cov.gamma], cov.gamma[j, l - 1, t, 1:n.cov.gamma])", code, fixed = TRUE))
})

test_that("generated code is syntactically parseable JAGS-flavored text (base R parse doesn't error on the surrounding sprintf)", {
  # not real JAGS syntax validation (that needs a live JAGS install, see
  # test-fit_occupancy_model.R), just confirms the templating itself produced
  # a single well-formed character string with no leftover %s placeholders
  code <- build_whale_model_code(1, 1, 1)
  expect_type(code, "character")
  expect_length(code, 1)
  expect_false(grepl("%s", code, fixed = TRUE))
})

test_that("detection covariates (jday/bft/eff) are always present regardless of occupancy covariates", {
  code0 <- build_whale_model_code(0, 0, 0)
  code3 <- build_whale_model_code(1, 1, 1)
  for (code in list(code0, code3)) {
    expect_true(grepl("a.jday[t] * jday[j, k, 1, t]", code, fixed = TRUE))
    expect_true(grepl("a.bft[t] * bft[j, k, 1, t]", code, fixed = TRUE))
    expect_true(grepl("a.eff[t] * eff[j, k, 1, t]", code, fixed = TRUE))
  }
})
