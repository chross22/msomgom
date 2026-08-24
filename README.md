# dynocc: Multi-Season Occupancy Model of the Gulf of Maine

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

`dynocc` is a regular R package (`devtools::check()` passes with 0 errors/0
warnings/0 notes). The fastest way to see it work end-to-end is the vignette:

```r
vignette("getting-started", package = "dynocc")
```

(Only found if dynocc was installed with `build_vignettes = TRUE` - see
[Install the package](#2-install-the-package) below; it's not the default.)

**Contents:** [Quick start](#quick-start) · [Setup](#setup) · [Usage](#usage) ·
[Data](#data) · [Repository layout](#repository-layout) · [References](#references)

## Quick start

No real survey data needed — this generates a config, a synthetic survey CSV,
and fits the model against it, all in-memory in a temp directory:

```r
# install.packages("devtools")
# devtools::install_github("chross22/dynocc", build_vignettes = TRUE, dependencies = TRUE)
library(dynocc)

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
package = "dynocc")` walks through this exact example already rendered.

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
devtools::install_github("chross22/dynocc", build_vignettes = TRUE, dependencies = TRUE)
```

**`build_vignettes = TRUE` is not the default** - `devtools`/`remotes` skip
building vignettes unless asked (`remotes::install_github()`'s `build_opts`
actually includes `--no-build-vignettes` by default), so
`vignette("getting-started", package = "dynocc")` will say the vignette
doesn't exist if you install without it. `dependencies = TRUE` pulls in
`knitr`/`rmarkdown`, needed to build it, since they're `Suggests`-only.

If you already installed without either flag, `vignette()` still won't find
it after adding them later - reinstall with both flags rather than trying to
patch an existing install. In the meantime, the same walkthrough is on
GitHub: [`vignettes/getting-started.Rmd`](vignettes/getting-started.Rmd).

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
- `Microsoft365R` - only if you set `paths.onedrive_filename` (see
  [Fetching survey data](#fetching-survey-data-google-drive--onedrive) below)
- `datamatch`, `derivoce` - fetching/deriving environmental covariates (see
  [Diagnostics and covariates](vignettes/diagnostics.Rmd))
- `fancyfx` - plotting a fitted covariate's effect (see
  [Diagnostics and covariates](vignettes/diagnostics.Rmd))
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
library(dynocc)
generate_config(
  "my_run",
  data_file = "data/my_survey_data.csv",
  beg_year = 2015, end_year = 2020,
  species_codes = c("RIWH", "HUWH"), active_species = "HUWH"
)
# -> writes configs/my_run.yaml (relative to the current working directory)
```

Two example configs ship with the package under `system.file("extdata/configs", package = "dynocc")`:
`bof_riwh.yaml` reproduces the pipeline's original hardcoded Bay of Fundy / RIWH
settings, and `mock_test.yaml` is a small/fast config for the mock-data smoke
test below. See `?generate_config` for what every field means (paths,
survey platform/FILEID/on-effort filters, date range, season boundaries,
study-area polygon, species, JAGS/MCMC settings, evaluation, cleanup).

The survey filters (`platform_code`, `fileid_prefixes`, `on_effort_legtypes`)
are all config-driven rather than hardcoded to any one platform, so the
pipeline isn't limited to vessel surveys - an aerial survey in the same NARWC
handbook format works too, with its own platform code, `FILEID` prefix, and
on-effort `LEGTYPE` codes (which differ from a vessel's; check the handbook
for the codes that apply to your platform).

### Run the pipeline

```r
library(dynocc)
result <- run_occupancy_model("configs/my_run.yaml")
result$fit          # the fitted mcmc.list
result$evaluation    # convergence diagnostics + posterior summary, see below
```

or from the command line, via the CLI wrapper installed with the package:

```r
# run once to find where it lives on your machine:
system.file("scripts/run_pipeline.R", package = "dynocc")
#> "/usr/local/lib/R/site-library/dynocc/scripts/run_pipeline.R"
```

```bash
Rscript /usr/local/lib/R/site-library/dynocc/scripts/run_pipeline.R configs/my_run.yaml
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
library(dynocc)
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
`vignette("getting-started", package = "dynocc")` for this same walkthrough,
fully worked through and rendered.

### Going further

Once a run is more than a smoke test, two things come up: working out why a fit
looks wrong, and putting environmental covariates on it.

`diagnose_pipeline()` runs the data-prep and grid-building stages — never JAGS
itself — and reports the most common reasons a run fails, hangs, or "succeeds"
with meaningless output: a filter that leaves nothing, a study-area polygon that
misses the survey tracks, a species with zero detections, a record outside every
configured season, a covariate matrix with the wrong shape:

```r
diagnose_pipeline("configs/my_run.yaml")
```

It prints a PASS/WARN/FAIL report and returns whatever it reached invisibly, so
you can pick up investigating where it stopped. `plot_survey_coverage()`,
`plot_sightings()`, `plot_occupancy_map()` and `plot_covariate_map()` then show
what actually went into the model rather than a rederivation from the raw CSV.

Covariates go on detection probability always, and optionally on initial
occupancy (`psi`), persistence (`phi`) and colonization (`gamma`) — each process
independently, chosen per config. A process with none configured stays
intercept-only, and a config with no `covariates:` section behaves exactly as it
did before the feature existed.

→ [**Diagnostics and covariates**](vignettes/diagnostics.Rmd) covers all of it:
evaluating a saved run without re-fitting, the debugging tools, the four maps,
attaching covariates from local files or live from Copernicus, and effect plots
through fancyfx.

## Data

This pipeline expects a CSV in the [NARWC Sightings
Database](https://www.narwc.org/uploads/1/1/6/6/116623219/sightingsdatabaseusers_guideupdated2021-09-20.pdf)
format (Kenney 2021). `data/` and `output/` are gitignored — real survey data
has its own data-sharing terms and shouldn't be committed here, and model
outputs are regenerable from a run.

A real export's column names rarely match the NARWC schema exactly (`Event`
instead of `EVENTNO`, `Sp. Code` instead of `SPECCODE`, ...).
`prep_survey_data()` runs `standardize_survey_columns()` on the raw CSV
first, which renames columns to their canonical name on a case-insensitive
match or a small list of common aliases, so this usually doesn't need manual
renaming first. `ALT` (altitude) additionally defaults to `750` if it's
missing entirely, since this pipeline's own filtering doesn't use it. A
column it genuinely can't match errors clearly, naming what's missing and
what was actually found - see `?standardize_survey_columns` for the alias
list, or call it directly to check your own file before running the full
pipeline: `standardize_survey_columns(readr::read_csv("data/survey_data.csv"))`.

### Fetching survey data (Google Drive / OneDrive)

If `paths.data_file` doesn't exist locally, `prep_survey_data()` can fetch it
for you first - from Google Drive (`paths.google_drive_filename`, via the
optional `googledrive` package) or OneDrive (`paths.onedrive_filename`, via
the optional `Microsoft365R` package). Set at most one; if both are set,
Google Drive takes priority.

```r
generate_config("my_run", data_file = "data/survey_data.csv",
                 onedrive_filename = "Shared/survey_data.csv", # path *within* OneDrive
                 onedrive_type = "business")                   # "personal" (default) or "business"
```

`onedrive_filename` is the file's path within OneDrive, not a local path -
`Microsoft365R::get_personal_onedrive()`/`get_business_onedrive()` resolve it
via Microsoft Graph, prompting an interactive login on first use. Use
`onedrive_type = "business"` for an organization/shared OneDrive.

**If OneDrive is already synced to this machine** (the usual case with the
OneDrive desktop app), none of this is needed - just point `data_file`
directly at wherever it's synced locally (e.g. `"~/OneDrive - Org/.../survey_data.csv"`),
and skip `onedrive_filename` entirely.

## Repository layout

`dynocc` is a standard R package; the layout follows the usual conventions
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
  effect_estimates.R               # effect_estimates.dynocc_fit() -> fancyfx integration
  evaluate_model.R                 # evaluate_occupancy_model(...) -> convergence diagnostics
  plot_diagnostics.R               # plot_survey_coverage/plot_sightings/plot_occupancy_map/plot_covariate_map
  cleanup.R                        # cleanup_outputs(config) -> removes data file/figs
  main.R                           # run_occupancy_model(config_path) -> orchestrates all of the above
  dynocc-package.R                # package-level doc + centralized @import/@importFrom
man/                               # generated .Rd files (roxygen2, do not edit by hand)
vignettes/getting-started.Rmd      # worked end-to-end walkthrough on mock data
tests/testthat/                    # testthat suite (unit tests + end-to-end pipeline tests)
inst/
  extdata/configs/                 # example configs: bof_riwh.yaml, mock_test.yaml
  scripts/
    run_pipeline.R                 # CLI wrapper: Rscript run_pipeline.R config.yaml
tools/
  citations.csv                    # DOI/URL registry the shared citation engine checks
  citation-hooks.R                 # repo-specific citation checks (e.g. NARWC handbook version)
.github/workflows/check-citations.yaml  # calls chross22/distsamp's shared citation-check engine monthly
legacy/                            # archived pre-refactor scripts (gitignored, kept locally)
docs/refactor_plan.md              # full history of the generalization refactor
```

## Documentation

| | |
|---|---|
| [Getting started](vignettes/getting-started.Rmd) | one complete run on synthetic data, end to end |
| [Diagnostics and covariates](vignettes/diagnostics.Rmd) | why a fit looks wrong, and how to attach environmental covariates |

## Citing dynocc

```r
citation("dynocc")
```

That gives three entries: the package; the dynamic (multi-season,
colonization/persistence) occupancy model of MacKenzie et al. (2003) that it
implements; and the single-season detection model of MacKenzie et al. (2002)
that the 2003 paper extends. Data products a run leans on carry their own
citations separately - see [References](#references) below. A methods
section usually needs all of these.

## References

- Copernicus Marine Service (n.d.). *E.U. Copernicus Marine Service Information (CMEMS), Marine Data Store (MDS).* <https://marine.copernicus.eu/>
- Grolemund, G., & Wickham, H. (2011). Dates and times made easy with lubridate. *Journal of Statistical Software*, 40(3), 1–25. <https://www.jstatsoft.org/v40/i03/>
- Hijmans, R. J., Brown, A., & Barbosa, M. (2026). *terra: Spatial data analysis* [R package]. <https://CRAN.R-project.org/package=terra>
- Kenney, R. D. (2023). *The North Atlantic Right Whale Consortium database: A guide for users and contributors* (Version 8). North Atlantic Right Whale Consortium Reference Document 2023-01. University of Rhode Island Graduate School of Oceanography. <https://www.narwc.org/uploads/1/1/6/6/116623219/narwc_users_guide__v8_.pdf>
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

Citations above reflect package versions installed at the time this was written (see [Setup](#setup)); run `citation("pkgname")` in R for the exact citation matching your installed version. A [scheduled workflow](.github/workflows/check-citations.yaml) runs monthly against the shared citation-check engine in [chross22/distsamp](https://github.com/chross22/distsamp), checking [`tools/citations.csv`](tools/citations.csv)'s registry against current CRAN/DOI metadata and running repo-specific checks from [`tools/citation-hooks.R`](tools/citation-hooks.R) (e.g. whether a newer NARWC handbook has been published); it opens an issue if anything needs review.
