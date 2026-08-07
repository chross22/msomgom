# msomgom

A dynamic (multi-season, colonization/persistence) occupancy model — following
the MacKenzie et al. (2003) formulation, itself an extension of the
single-season detection model of MacKenzie et al. (2002) — for cetacean
vessel-survey sightings, fit in JAGS (Plummer 2003). Originally built around
Bay of Fundy North Atlantic right whale (RIWH) survey data from the [NARWC
Sightings Database](https://www.narwc.org/uploads/1/1/6/6/116623219/sightingsdatabaseusers_guideupdated2021-09-20.pdf)
(Kenney 2021), now generalized so file paths, the study-area polygon, date
range, species, and MCMC settings are all driven by a YAML config rather than
hardcoded.

See [References](#references) at the bottom for full citations.

The model is currently fit **one species per run** (selected via config); the
data-prep/gridding stages already loop over a configurable list of species and
build one detection-history array per species, so extending this to a true
hierarchical multi-species model later doesn't require redoing that part. See
[`docs/refactor_plan.md`](docs/refactor_plan.md) for the full history of how this
pipeline got to its current shape and why.

`msomgom` is a regular R package (`devtools::check()` passes with 0 errors/0
warnings/0 notes). The fastest way to see it work end-to-end is the vignette:

```r
vignette("getting-started", package = "msomgom")
```

**Contents:** [Quick start](#quick-start) · [Setup](#setup) · [Usage](#usage) ·
[Data](#data) · [Repository layout](#repository-layout) · [References](#references)

## Quick start

No real survey data needed — this generates a config, a synthetic survey CSV,
and fits the model against it, all in-memory in a temp directory:

```r
# install.packages("devtools"); devtools::install_github("chross22/msomgom")
library(msomgom)

dir.create("configs")
generate_config("mock_test", data_file = "data/mock_survey_data.csv",
                 n_chains = 2, n_adapt = 100, n_burn = 100, n_iter = 200)
generate_mock_data("configs/mock_test.yaml")

result <- run_occupancy_model("configs/mock_test.yaml")
result$evaluation$parameters # posterior summary: mean, sd, Rhat, effective size, ...
```

This needs `rjags`/`dclone` installed (plus a working JAGS binary) to actually
fit the model — see [Setup](#setup) below for that. If you just want to see the
whole thing run without installing JAGS yourself, `vignette("getting-started",
package = "msomgom")` walks through this exact example already rendered.

## Setup

You need R, JAGS, and a handful of R packages with native dependencies (spatial
libraries for `sf`, JAGS bindings for `rjags`).

### 1. System dependencies (macOS / Homebrew)

```bash
brew install gdal geos proj udunits cmake
```

**JAGS** (Plummer 2003) **needs to be 4.x, not 5.x.** CRAN's `rjags` (Plummer 2025, as of this writing, 4-17) hard-rejects
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

### 2. Install the package

```r
# install.packages("devtools")
devtools::install_github("chross22/msomgom")
```

This pulls in the hard dependencies (`dplyr`, `lubridate`, `parallel`, `readr`,
`sf`, `sfheaders`, `stringr`, `tibble`, `yaml`) automatically. A few packages
are optional (in `Suggests`) and only needed for specific features - installed
separately, and only if you use them:

- `rjags` (Plummer 2025) and `dclone` (Sólymos 2010) - actually fitting the
  model (`fit_occupancy_model()`/`run_occupancy_model()`); also needs a
  working JAGS install (see step 1)
- `coda` (Plummer et al. 2006) - convergence diagnostics (`evaluate_occupancy_model()`)
- `terra` (Hijmans et al. 2026) - reading local NetCDF covariate files (`load_covariate_netcdf()`)
- `mapview`, `tmap`, `webshot` - only if you set `output.make_figs: true` in a config
- `googledrive` - only if you set `paths.google_drive_filename`
- `knitr`, `rmarkdown` - building the vignette

```r
install.packages(c("rjags", "dclone", "coda", "terra"))
```

Spatial gridding uses `sf` (Pebesma 2018; Pebesma & Bivand 2023); config
parsing uses `yaml` (Stephens & Simonov 2025); data cleaning uses `dplyr`
(Wickham et al. 2026a), `readr` (Wickham et al. 2026b), `stringr` (Wickham
2025), `lubridate` (Grolemund & Wickham 2011), and `tibble` (Müller & Wickham
2026). This pipeline is written in R (R Core Team 2026); see
[References](#references) for full citations.

## Usage

### Configure a run

Generate a config programmatically rather than hand-editing YAML:

```r
library(msomgom)
generate_config(
  "my_run",
  data_file = "data/my_survey_data.csv",
  beg_year = 2015, end_year = 2020,
  species_codes = c("RIWH", "HUWH"), active_species = "HUWH"
)
# -> writes configs/my_run.yaml (relative to the current working directory)
```

Two example configs ship with the package under `system.file("extdata/configs", package = "msomgom")`:
`bof_riwh.yaml` reproduces the pipeline's original hardcoded Bay of Fundy / RIWH
settings, and `mock_test.yaml` is a small/fast config for the mock-data smoke
test below. See the comments in `bof_riwh.yaml` for what every field means
(paths, survey vessel/FILEID filters, date range, season boundaries,
study-area polygon, species, JAGS/MCMC settings, evaluation, cleanup).

### Run the pipeline

```r
library(msomgom)
result <- run_occupancy_model("configs/my_run.yaml")
result$fit          # the fitted mcmc.list
result$evaluation    # convergence diagnostics + posterior summary, see below
```

or from the command line, via the CLI wrapper installed with the package:

```r
# run once to find where it lives on your machine:
system.file("scripts/run_pipeline.R", package = "msomgom")
#> "/usr/local/lib/R/site-library/msomgom/scripts/run_pipeline.R"
```

```bash
Rscript /usr/local/lib/R/site-library/msomgom/scripts/run_pipeline.R configs/my_run.yaml
```

`run_occupancy_model()` calls, in order: `prep_survey_data()` (load + clean
the survey CSV) -> `build_detection_arrays()` (build the spatial grid and
detection-history arrays) -> `fit_occupancy_model()` (fit the model) ->
`evaluate_occupancy_model()` (diagnostics, unless disabled in the config) ->
`cleanup_outputs()` (only if `cleanup.run_after_model: true`).

### Try it without real data

The real NARWC survey CSV isn't included in this repo (see Data below). To
exercise the whole pipeline with synthetic data:

```r
library(msomgom)
generate_config("mock_test", data_file = "data/mock_survey_data.csv",
                 output_dir = "output/mock_test",
                 n_chains = 2, n_adapt = 100, n_burn = 100, n_iter = 200)
generate_mock_data("configs/mock_test.yaml")
run_occupancy_model("configs/mock_test.yaml")
```

Mock data is grounded in the NARWC handbook's actual field codes (`PLATFORM`,
`FILEID`, `LEGTYPE`, `LEGSTAGE`, `VISIBLTY`, `BEAUFORT`, `IDREL`, `SPECCODE`),
including some decoy records the pipeline's filters should drop, so it's a real
exercise of the filtering logic, not just a happy-path stub. See
`vignette("getting-started", package = "msomgom")` for this same walkthrough,
fully worked through and rendered.

### Evaluate a saved run

`evaluate_occupancy_model()` also works standalone against a previously saved
result, without re-fitting:

```r
library(msomgom)
config <- load_config("configs/my_run.yaml")
evaluate_occupancy_model("output/RIWH.colext.RData", config = config)
```

It reports a posterior parameter summary table, Gelman-Rubin Rhat and effective
sample size per parameter (with warnings for likely non-convergence or a noisy
posterior), trace/density plots saved to `<output_dir>/mcmc_diagnostics.pdf`, and,
when the model was run with `jags.params: Z`, a naive-vs-modeled occupancy
comparison per year.

### Environmental covariates

`whale.mod` (in `jags.R`) puts environmental covariates on detection
probability (day-of-year, sea state, effort), and optionally on initial
occupancy (`psi`), persistence (`phi`), and colonization (`gamma`) too - each
process independently gets zero or more named covariates, chosen per config.
A process with none configured stays intercept-only, exactly as if this
didn't exist; a config with no `covariates:` section at all behaves
identically to before this feature was added.

The two steps: prep the covariate data (`average_covariates.R`), then pass it
into a run (`covariates.psi/phi/gamma` in the config + the `occ_covariates`
argument).

**1. Prep covariate data.** `average_covariates()` works directly with the
output of [`datamatch::accessEnvDat()`](https://github.com/chross22/datamatch)
(Ross, n.d.) (an `sf` point object per day, tagged with YEAR/MONTH/DAY), which
pulls from the E.U. Copernicus Marine Service (Copernicus Marine Service,
n.d.); or with a folder of local daily NetCDF files via `load_covariate_netcdf()`
if you already have files on disk instead (e.g. from another data source, or
from `datamatch` run separately). Either way, it spatially averages onto this
pipeline's hex grid and temporally averages over whatever windows you give it:

```r
library(msomgom)
config <- load_config("configs/my_run.yaml")

# area_grid_sf must come from build_detection_arrays(), so the covariate grid
# matches the occupancy model's grid exactly, cell-for-cell
prep <- prep_survey_data(config)
arrays <- build_detection_arrays(prep$tmpdat, prep$season_info, config)

# tied to the occupancy model's own season/year structure
windows <- season_windows_from_config(config)
# or arbitrary fixed-interval windows, independent of any occupancy config
# windows <- regular_windows("2018-01-01", "2020-12-31", by = "1 month")

env_dat <- load_covariate_netcdf("data/covariates/sst", var_names = "sst")
sst_avg <- average_covariates(env_dat, arrays$area_grid_sf, windows)
# sst_avg$sst is a [num_cells x num_ssn] matrix, same num_ssn indexing as
# effort3d/jday3d/bft3d
```

**2. Configure and run.** List which covariate names (matching names in
`occ_covariates`, e.g. `sst_avg` above) apply to which process, then pass the
covariate list into `run_occupancy_model()`:

```r
library(msomgom)
generate_config("my_run", covariates_psi = c("sst"), covariates_phi = c("sst"))
# -> configs/my_run.yaml has covariates: { psi: [sst], phi: [sst], gamma: [] }

result <- run_occupancy_model("configs/my_run.yaml", occ_covariates = list(sst = sst_avg$sst))
result$evaluation$parameters # now includes mu.b.cov (psi) and mu.e.cov (phi)
```

Each process can take a different number of covariates (or none), including a
different set of covariate names entirely - `covariates.gamma` above is empty,
so colonization stays intercept-only while occupancy and persistence both get
`sst`. Internally, since JAGS can't compile a covariate loop of length zero,
the model's BUGS code is generated per run (`build_whale_model_code()` in
`jags.R`) rather than being one static model, so each process's covariate
block is included only when that process actually has covariates.

Extending this further - to a true hierarchical multi-species model that fits
all configured species jointly with shared priors - is a deliberately
separate, larger follow-up.

## Data

This pipeline expects a CSV in the [NARWC Sightings
Database](https://www.narwc.org/uploads/1/1/6/6/116623219/sightingsdatabaseusers_guideupdated2021-09-20.pdf)
format (Kenney 2021). `data/` and `output/` are gitignored — real survey data
has its own data-sharing terms and shouldn't be committed here, and model
outputs are regenerable from a run.

## Repository layout

`msomgom` is a standard R package; the layout follows the usual conventions
(`R CMD build`/`devtools::check()` both pass clean):

```
DESCRIPTION, NAMESPACE            # package metadata + generated exports (roxygen2)
R/
  load_config.R                    # load_config(path) -> validated config list
  generate_config.R                # generate_config(name, ...) -> writes <name>.yaml
  generate_mock_data.R             # synthetic survey CSV for testing, no real data needed
  average_covariates.R             # spatial/temporal averaging of covariates onto the grid
  padstr0.R                        # zero-pads GMT time-of-day values
  makeSeasons.R                    # builds the season lookup table from config date ranges
  data_prep.R                      # prep_survey_data(config) -> cleaned survey data
  jagsPrep.R                       # build_detection_arrays(...) -> spatial grid + detection arrays
  jags.R                           # fit_occupancy_model(...) -> fits the JAGS model
  evaluate_model.R                 # evaluate_occupancy_model(...) -> convergence diagnostics
  cleanup.R                        # cleanup_outputs(config) -> removes data file/figs
  main.R                           # run_occupancy_model(config_path) -> orchestrates all of the above
  msomgom-package.R                # package-level doc + centralized @import/@importFrom
man/                               # generated .Rd files (roxygen2, do not edit by hand)
vignettes/getting-started.Rmd      # worked end-to-end walkthrough on mock data
tests/testthat/                    # testthat suite (unit tests + end-to-end pipeline tests)
inst/
  extdata/configs/                 # example configs: bof_riwh.yaml, mock_test.yaml
  scripts/
    run_pipeline.R                 # CLI wrapper: Rscript run_pipeline.R config.yaml
    check_citations.R              # verifies README.md's References section is still current
.github/workflows/check-citations.yml  # runs check_citations.R monthly, opens an issue on drift
legacy/                            # archived pre-refactor scripts (gitignored, kept locally)
docs/refactor_plan.md              # full history of the generalization refactor
```

## References

- Copernicus Marine Service (n.d.). *E.U. Copernicus Marine Service Information (CMEMS), Marine Data Store (MDS).* <https://marine.copernicus.eu/>
- Grolemund, G., & Wickham, H. (2011). Dates and times made easy with lubridate. *Journal of Statistical Software*, 40(3), 1–25. <https://www.jstatsoft.org/v40/i03/>
- Hijmans, R. J., Brown, A., & Barbosa, M. (2026). *terra: Spatial data analysis* [R package]. <https://CRAN.R-project.org/package=terra>
- Kenney, R. D. (2021). *The North Atlantic Right Whale Consortium database: A guide for users and contributors* (Version 7). North Atlantic Right Whale Consortium Reference Document 2021-01. University of Rhode Island Graduate School of Oceanography. <https://www.narwc.org/uploads/1/1/6/6/116623219/sightingsdatabaseusers_guideupdated2021-09-20.pdf>
- MacKenzie, D. I., Nichols, J. D., Lachman, G. B., Droege, S., Royle, J. A., & Langtimm, C. A. (2002). Estimating site occupancy rates when detection probabilities are less than one. *Ecology*, 83(8), 2248–2255.
- MacKenzie, D. I., Nichols, J. D., Hines, J. E., Knutson, M. G., & Franklin, A. B. (2003). Estimating site occupancy, colonization, and local extinction when a species is detected imperfectly. *Ecology*, 84(8), 2200–2207. <https://doi.org/10.1890/02-3090>
- Müller, K., & Wickham, H. (2026). *tibble: Simple data frames* [R package]. <https://CRAN.R-project.org/package=tibble>
- Pebesma, E. (2018). Simple features for R: Standardized support for spatial vector data. *The R Journal*, 10(1), 439–446. <https://doi.org/10.32614/RJ-2018-009>
- Pebesma, E., & Bivand, R. (2023). *Spatial data science: With applications in R*. Chapman and Hall/CRC. <https://doi.org/10.1201/9780429459016>
- Plummer, M. (2003). JAGS: A program for analysis of Bayesian graphical models using Gibbs sampling. In *Proceedings of the 3rd International Workshop on Distributed Statistical Computing (DSC 2003)*, Vienna, Austria. <https://www.r-project.org/conferences/DSC-2003/Proceedings/Plummer.pdf>
- Plummer, M. (2025). *rjags: Bayesian graphical models using MCMC* [R package]. <https://CRAN.R-project.org/package=rjags>
- Plummer, M., Best, N., Cowles, K., & Vines, K. (2006). CODA: Convergence diagnosis and output analysis for MCMC. *R News*, 6(1), 7–11.
- R Core Team (2026). *R: A language and environment for statistical computing*. R Foundation for Statistical Computing. <https://www.R-project.org/>
- Ross, C. (n.d.). *datamatch: Matches environmental data with species occurrence data* [R package]. <https://github.com/chross22/datamatch>
- Sólymos, P. (2010). dclone: Data cloning in R. *The R Journal*, 2(2), 29–37. <https://journal.r-project.org/>
- Stephens, J., & Simonov, K. (2025). *yaml: Methods to convert R data to YAML and back* [R package]. <https://CRAN.R-project.org/package=yaml>
- Wickham, H. (2025). *stringr: Simple, consistent wrappers for common string operations* [R package]. <https://CRAN.R-project.org/package=stringr>
- Wickham, H., François, R., Henry, L., Müller, K., & Vaughan, D. (2026a). *dplyr: A grammar of data manipulation* [R package]. <https://CRAN.R-project.org/package=dplyr>
- Wickham, H., Hester, J., & Bryan, J. (2026b). *readr: Read rectangular text data* [R package]. <https://CRAN.R-project.org/package=readr>

Citations above reflect package versions installed at the time this was written (see [Setup](#setup)); run `citation("pkgname")` in R for the exact citation matching your installed version. [`inst/scripts/check_citations.R`](inst/scripts/check_citations.R) checks this list against current CRAN metadata and that every cited URL still resolves; a [scheduled workflow](.github/workflows/check-citations.yml) runs it monthly and opens an issue if anything needs review.
