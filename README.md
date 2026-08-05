# msomgom

A dynamic (multi-season, colonization/persistence) occupancy model for cetacean
vessel-survey sightings, fit in JAGS. Originally built around Bay of Fundy North
Atlantic right whale (RIWH) survey data from the [NARWC Sightings
Database](https://www.narwc.org/uploads/1/1/6/6/116623219/sightingsdatabaseusers_guideupdated2021-09-20.pdf),
now generalized so file paths, the study-area polygon, date range, species, and
MCMC settings are all driven by a YAML config rather than hardcoded.

The model is currently fit **one species per run** (selected via config); the
data-prep/gridding stages already loop over a configurable list of species and
build one detection-history array per species, so extending this to a true
hierarchical multi-species model later doesn't require redoing that part. See
[`docs/refactor_plan.md`](docs/refactor_plan.md) for the full history of how this
pipeline got to its current shape and why.

## Setup

You need R, JAGS, and a handful of R packages with native dependencies (spatial
libraries for `sf`, JAGS bindings for `rjags`).

### 1. System dependencies (macOS / Homebrew)

```bash
brew install gdal geos proj udunits cmake
```

**JAGS needs to be 4.x, not 5.x.** CRAN's `rjags` (as of this writing, 4-17) hard-rejects
any JAGS version other than 4.x, but Homebrew's `jags` formula has moved on to 5.0.0.
Install JAGS 4.3.2 from the last formula revision that built it, via a local tap:

```bash
brew tap-new local/jags4
curl -s "https://raw.githubusercontent.com/Homebrew/homebrew-core/cafb141891/Formula/j/jags.rb" \
  -o "$(brew --repository)/Library/Taps/local/homebrew-jags4/Formula/jags.rb"
sed -i '' '/no_autobump!/d' "$(brew --repository)/Library/Taps/local/homebrew-jags4/Formula/jags.rb"
brew install local/jags4/jags
```

If you hit `fatal error: 'cmath' file not found` while installing R packages below,
your Xcode Command Line Tools are broken/incomplete. Fix with:

```bash
sudo rm -rf /Library/Developer/CommandLineTools
xcode-select --install
```

### 2. R packages

```r
install.packages(c(
  "yaml", "sf", "sfheaders", "dplyr", "readr", "stringr", "lubridate", "tibble",
  "rjags", "dclone", "R2jags"
))
```

`mapview`, `tmap`, and `webshot` are only needed if you set `output.make_figs: true`
in a config; `googledrive` is only needed if you set `paths.google_drive_filename`.
Neither is required for a normal run.

## Usage

### Configure a run

Configs live in `configs/`, one YAML file per run. `configs/bof_riwh.yaml`
reproduces the pipeline's original hardcoded Bay of Fundy / RIWH settings as a
working example; `configs/mock_test.yaml` is a small/fast config for the
mock-data smoke test below.

Generate a new config programmatically rather than hand-editing YAML:

```r
source("generate_config.R")
generate_config(
  "my_run",
  data_file = "data/my_survey_data.csv",
  beg_year = 2015, end_year = 2020,
  species_codes = c("RIWH", "HUWH"), active_species = "HUWH"
)
# -> writes configs/my_run.yaml
```

See the comments in `configs/bof_riwh.yaml` for what every field means (paths,
survey vessel/FILEID filters, date range, season boundaries, study-area polygon,
species, JAGS/MCMC settings, evaluation, cleanup).

### Run the pipeline

```r
source("main.R")
result <- run_occupancy_model("configs/bof_riwh.yaml")
result$fit          # the fitted mcmc.list
result$evaluation    # convergence diagnostics + posterior summary, see below
```

or from the command line:

```bash
Rscript main.R configs/bof_riwh.yaml
```

This runs, in order: `data_prep.R` (load + clean the survey CSV) ->
`jagsPrep.R` (build the spatial grid and detection-history arrays) -> `jags.R`
(fit the model) -> `evaluate_model.R` (diagnostics, unless disabled in the
config) -> `cleanup.R` (only if `cleanup.run_after_model: true`).

### Try it without real data

The real NARWC survey CSV isn't included in this repo (see Data below). To
exercise the whole pipeline with synthetic data:

```r
source("generate_config.R")
source("generate_mock_data.R")
generate_config("mock_test", data_file = "data/mock_survey_data.csv",
                 output_dir = "output/mock_test",
                 n_chains = 2, n_adapt = 100, n_burn = 100, n_iter = 200)
generate_mock_data("configs/mock_test.yaml")

source("main.R")
run_occupancy_model("configs/mock_test.yaml")
```

Mock data is grounded in the NARWC handbook's actual field codes (`PLATFORM`,
`FILEID`, `LEGTYPE`, `LEGSTAGE`, `VISIBLTY`, `BEAUFORT`, `IDREL`, `SPECCODE`),
including some decoy records the pipeline's filters should drop, so it's a real
exercise of the filtering logic, not just a happy-path stub.

### Evaluate a saved run

`evaluate_occupancy_model()` also works standalone against a previously saved
result, without re-fitting:

```r
source("load_config.R"); source("evaluate_model.R")
config <- load_config("configs/bof_riwh.yaml")
evaluate_occupancy_model("output/RIWH.colext.RData", config = config)
```

It reports a posterior parameter summary table, Gelman-Rubin Rhat and effective
sample size per parameter (with warnings for likely non-convergence or a noisy
posterior), trace/density plots saved to `<output_dir>/mcmc_diagnostics.pdf`, and,
when the model was run with `jags.params: Z`, a naive-vs-modeled occupancy
comparison per year.

## Data

This pipeline expects a CSV in the [NARWC Sightings
Database](https://www.narwc.org/uploads/1/1/6/6/116623219/sightingsdatabaseusers_guideupdated2021-09-20.pdf)
format. `data/` and `output/` are gitignored — real survey data has its own
data-sharing terms and shouldn't be committed here, and model outputs are
regenerable from a run.

## Repository layout

```
configs/                 # one YAML config per run (see generate_config.R)
load_config.R             # load_config(path) -> validated config list
generate_config.R         # generate_config(name, ...) -> writes configs/<name>.yaml
generate_mock_data.R      # synthetic survey CSV for testing, no real data needed
padstr0.R                 # zero-pads GMT time-of-day values
makeSeasons.R             # builds the season lookup table from config date ranges
data_prep.R               # prep_survey_data(config) -> cleaned survey data
jagsPrep.R                 # build_detection_arrays(...) -> spatial grid + detection arrays
jags.R                      # fit_occupancy_model(...) -> fits the JAGS model
evaluate_model.R            # evaluate_occupancy_model(...) -> convergence diagnostics
cleanup.R                    # cleanup_outputs(config) -> removes data file/figs
main.R                        # run_occupancy_model(config_path) -> orchestrates all of the above
legacy/                        # archived pre-refactor scripts (gitignored, kept locally)
docs/refactor_plan.md           # full history of the generalization refactor
```
