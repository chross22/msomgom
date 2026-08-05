# Generalizing the BoF occupancy-model pipeline

## Context

This repo runs a dynamic (multi-season) occupancy model in JAGS on North Atlantic
right whale (RIWH) sightings from vessel survey data in the Bay of Fundy. Before this
refactor, the pipeline only ran interactively in RStudio: it hardcoded a data file path, a
study-area polygon, a species code, and MCMC settings across several scripts, and relied
on `rstudioapi::getSourceEditorContext()$path` to find its own directory. It was adapted
from someone else's project, so the goal of this work was to generalize it — point it at
different data/paths/species via a config file, and run it through one entry point —
without changing what the model actually computes.

## Decisions made along the way

- **`master.R` and `real_deal_linestring6.R` were archived to `legacy/`**, unmodified, rather
  than deleted or left in the active pipeline. Both duplicated logic already present in
  `data_prep.R` + `jagsPrep.R`.
- **The consolidated data-prep step is based on `master.R`'s data-cleaning logic**, not
  `data_prep.R`'s. Comparing the two: `data_prep.R` filtered by raw `YEAR`/`MONTH`/`DAY`
  and computed season from date only, while `master.R` additionally parsed the survey's
  GMT time-of-day (`GMT` column, via a `padstr0` helper) into a real `datetime_GMT` →
  `datetime_ET` (US/Eastern), and filtered/assigned seasons from that local datetime
  instead of the bare date — more correct for events near a UTC day boundary.
  `data_prep.R`'s `BEHAV*`-column drop was kept since it's a strict improvement with no
  conflict.
- **`master.R` sourced a `padstr0.R` that didn't exist in the repo.** Its behavior (zero-pad a
  numeric GMT value, e.g. `800` → `"000800"`) was inferred from its call site and from the
  downstream patch for a `"02e+05"` value, which indicates the original implementation's
  character conversion produced scientific notation for round numbers. The reproduced
  version uses integer formatting (`formatC(..., format = "d")`) so that bug can't recur.
- **The grid-building step is based on `jagsPrep.R`**, not `real_deal_linestring6.R`, since
  `jagsPrep.R` already includes the "drop surveys whose track never enters the grid" step
  and the `make_figs` flag that `real_deal_linestring6.R` lacks.
- **The model stays single-species-per-run** (species selectable via config), not a true
  hierarchical multi-species occupancy model. A true MSOM (shared/hierarchical priors
  across species, a species dimension in the JAGS model itself) is a deliberate, larger
  follow-up — the data-prep/grid-building scaffolding already loops over a configurable
  list of species and builds one detection-history array per species, so that follow-up
  doesn't require redoing this stage.
- **The study-area polygon and grid cell size became config fields** rather than hardcoded
  constants, so the pipeline isn't tied to the Bay of Fundy.
- **Mock survey data was generated** (`generate_mock_data.R`) to actually exercise the
  pipeline end-to-end, since the real survey CSV wasn't available in this environment. Its
  column codes and value ranges (`PLATFORM`, `FILEID`, `LEGTYPE`, `LEGSTAGE`,
  `VISIBLTY`, `BEAUFORT`, `IDREL`, `SPECCODE`, etc.) were grounded in the NARWC
  Sightings Database User's Guide (2021 update) rather than guessed, to match what the
  existing filters in the code already assume (e.g. `PLATFORM == 99` is the R/V *Nereid*,
  `FILEID` starting with `P`/`p` is a POP shipboard survey, `LEGTYPE` 5/6 = ship
  underway/not-underway, `LEGSTAGE` 1/2/5 = begin/continue/end watch, `IDREL == 3` =
  definite species ID).

## Target structure

```
configs/                        # one YAML file per run configuration
  bof_riwh.yaml                  # reproduces the original hardcoded BoF/RIWH settings
  mock_test.yaml                 # small/fast settings for the mock-data smoke test
generate_config.R                # generate_config(name, ...) -> writes configs/<name>.yaml
load_config.R                    # load_config(path) -> validated config list
generate_mock_data.R             # generate_mock_data(config_path) -> synthetic survey CSV, grounded in the NARWC handbook
padstr0.R                        # reproduced helper, zero-pads GMT time-of-day values
makeSeasons.R                    # unchanged
Mode.R                           # unchanged (currently unused, left as-is)
data_prep.R                      # prep_survey_data(config) -> list(dat, tmpdat, season_info)
jagsPrep.R                       # build_detection_arrays(tmpdat, season_info, config) -> arrays
jags.R                           # fit_occupancy_model(arrays, config) -> jags.parfit result (mcmc.list)
evaluate_model.R                 # evaluate_occupancy_model(fit, arrays, config) -> convergence diagnostics + summary
cleanup.R                        # cleanup_outputs(config)
main.R                           # run_occupancy_model(config_path) -> list(fit, evaluation); sources + calls the above in order
legacy/
  master.R                       # archived, unmodified
  real_deal_linestring6.R        # archived, unmodified
  param_specification.R          # archived, unmodified - fully superseded by configs/*.yaml + load_config.R
```

Configs live in their own `configs/` folder (rather than a single `config.yaml`) so multiple
run variants can be kept side by side and diffed/versioned independently.
`generate_config.R` writes new ones programmatically (defaults reproduce the original
Bay of Fundy / RIWH settings), so a new variant is one function call rather than
hand-editing YAML:

```r
source("generate_config.R")
generate_config("my_run", beg_year = 2015, end_year = 2020, species_codes = c("RIWH", "HUWH"), active_species = "HUWH")
```

## Model evaluation

`evaluate_model.R` was added since fitting a JAGS model isn't the same as having
evaluated it. `run_occupancy_model()` calls it automatically after fitting (config
section `evaluation:`, on by default) and it also works standalone against a
previously saved `.RData` result. It reports, using `coda` (already a dependency via
`rjags`):

- a posterior parameter summary table (mean/SD/2.5%/50%/97.5% for every tracked parameter)
- Gelman-Rubin Rhat and effective sample size per parameter, with warnings for
  Rhat >= 1.1 (not converged) or effective size < 100 (noisy posterior)
- trace/density plots saved to `<output_dir>/mcmc_diagnostics.pdf`
- when the model was run with `jags.params: Z` (tracking occupancy states directly
  rather than just the community-level hyperparameters), a naive-vs-modeled occupancy
  comparison per year, reusing the same naive-occupancy calculation `jags.R` already
  used internally for its `Z` initial values, so the two numbers are directly comparable

A real posterior-predictive goodness-of-fit check (e.g. a Bayesian p-value comparing
observed vs. model-simulated detection histories) would need derived nodes added to
`whale.mod` itself, which is a model-design change rather than an evaluation one, so
it's out of scope here.

## Behavior preserved as-is (no scope creep)

- The JAGS model itself (`whale.mod`, covariates on detection = jday/bft/effort,
  colonization/persistence dynamics) is unchanged — only MCMC settings became
  config-driven.
- The month filter stays `MONTH == begMONTH | MONTH == endMONTH` (matches begin/end
  month only, not a range) — existing behavior from both `master.R` and `data_prep.R`, not
  something we were asked to fix.
- The array-building code's `eval(parse(text=...))` pattern for dynamically creating
  per-species variables (e.g. `RIWH3d`) was preserved; the refactor just collects the
  resulting variables (via `mget()`) into a returned list at the end of the function instead
  of leaving them as globals.

## Getting a real end-to-end run working in this sandbox

None of the pipeline's R packages were installed here initially, and getting a real run
working surfaced two unrelated, genuine blockers on this machine (not something the
pipeline code itself could route around):

1. **Broken Xcode Command Line Tools.** The system's C++ standard library headers
   (`cmath` and friends, under `/Library/Developer/CommandLineTools/usr/include/c++/v1/`)
   were missing, so anything needing local C++ compilation failed - `Rcpp` and everything
   downstream of it (`sf`, `dplyr`, `stringr`, `lubridate`, `sfheaders`). This needed an
   admin-authenticated CLT reinstall, which only the machine's owner could do.
2. **`rjags`/JAGS version mismatch.** CRAN's `rjags` (4-17) hard-rejects any JAGS version
   that isn't 4.x, but Homebrew's `jags` formula had moved on to 5.0.0. Fixed by pulling
   the last formula revision that built JAGS 4.3.2 from Homebrew-core's git history and
   installing it from a local tap (a prebuilt `arm64_tahoe` bottle existed, so no source
   build was needed) - see the commit at `cafb141891` in `Homebrew/homebrew-core` if this
   needs to be reproduced elsewhere.

With both fixed, every required package installed cleanly: `yaml`, `sf`, `sfheaders`,
`dplyr`, `readr`, `stringr`, `lubridate`, `tibble`, `rjags`, `dclone`, `R2jags`
(plus `udunits` and `cmake` via Homebrew, needed by `units`/`RcppParallel` respectively).

**The full pipeline was run end-to-end** against `generate_mock_data.R`'s synthetic
data (`configs/mock_test.yaml`, small MCMC settings for speed): data prep, spatial
gridding, JAGS fitting (both `colext` and `Z` parameter-tracking modes), and evaluation
all completed successfully and produced a real fitted `mcmc.list`, saved `.RData`
results, and a diagnostics PDF. With the tiny test MCMC settings the evaluation step
correctly reported most parameters as not converged (Rhat >= 1.1) - expected given
100 adapt / 100 burn-in / 200 iterations on a handful of mock sites, and a good sign
that the convergence check itself is actually discriminating, not just always passing.

Anyone re-running this on the real survey data should use `configs/bof_riwh.yaml`
(or a config generated for their own study area/species) with real MCMC settings,
not the fast mock-data settings in `configs/mock_test.yaml`.

## Full plan

See the original approved plan for the complete config schema and verification steps:
`~/.claude/plans/flickering-mapping-octopus.md` (local to the machine this was written on;
copied here for reference since it isn't part of this repo).
