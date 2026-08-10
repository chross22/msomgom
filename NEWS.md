# msomgom 0.1.0

First tagged release. `msomgom` fits a dynamic (multi-season,
colonization/persistence) occupancy model, following MacKenzie et al.
(2003), to cetacean vessel-survey sightings via JAGS. Everything below is
config-driven; nothing is hardcoded to the Bay of Fundy/right-whale case it
was originally built around.

## Package

* Converted from a collection of `source()`d scripts into a standard,
  installable R package (`DESCRIPTION`/`NAMESPACE`, `R/`, `man/`, `inst/`,
  `vignettes/`, `tests/testthat/`). `devtools::check()` passes 0 errors/0
  warnings/0 notes.
* `vignette("getting-started", package = "msomgom")` walks through the whole
  pipeline end-to-end on mock data, including two real JAGS fits.
* A `testthat` suite covers both pure-logic units and full end-to-end
  pipeline runs against mock data.

## Pipeline

* `run_occupancy_model()` orchestrates the five stages: `prep_survey_data()`,
  `build_detection_arrays()`, `fit_occupancy_model()`,
  `evaluate_occupancy_model()`, `cleanup_outputs()`.
* `generate_mock_data()` produces a synthetic, NARWC-schema-grounded survey
  CSV (including decoy records the pipeline's own filters should drop), so
  the whole pipeline can be exercised without real survey data.

## Environmental covariates

* `average_covariates()` spatially and temporally averages environmental
  data onto the occupancy grid, for use as covariates on initial occupancy
  (`psi`), persistence (`phi`), and colonization (`gamma`) - each process
  independently, config-driven, intercept-only when none are configured.
* Accepts covariate data from `load_covariate_netcdf()` (local NetCDF
  files), [`datamatch::accessEnvDat()`](https://github.com/chross22/datamatch)
  (live Copernicus fetch), or [`derivoce`](https://github.com/chross22/derivoce)'s
  derived-covariate functions (gradients, distances, lags, ...) run on
  either - all three share the same `sf`-point-with-YEAR/MONTH/DAY shape, so
  they chain with no reshaping. Both packages are optional (`Suggests`).

## Diagnostics

* `evaluate_occupancy_model()` reports a posterior parameter summary,
  Gelman-Rubin Rhat and effective sample size, trace/density plots, and (for
  a fit that tracked `Z`) a naive-vs-modeled occupancy comparison per year.
* `plot_survey_coverage()`, `plot_sightings()`, `plot_occupancy_map()`, and
  `plot_covariate_map()` put the data and outputs on the study-area grid
  spatially, for spotting a coverage gap, a data problem, or a covariate
  that's constant/`NA` before it reaches the model.
