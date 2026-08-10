# msomgom (development version)

* `standardize_survey_columns()` now prefers the candidate column that actually
  has data. When more than one column matches a canonical name, they're ranked
  by how many values they carry (ties keep file order) instead of taking
  whichever came first, and the ambiguity warning reports the counts it ranked
  on. A column with the canonical name but no values in it is displaced by a
  populated match under another name, and kept as `<CANONICAL>_empty` rather
  than dropped. Same ranking applies when several columns look like the date
  column.
* `PLATFORM` joined the alias table, so a file calling it `Platform_Code`,
  `Platform_Type`, or `Vessel` no longer has to be renamed by hand. Two fixes
  came with it: a column already carrying a canonical name is now off-limits to
  every other canonical's substring fallback (`PLATFORM` normalizes to
  `platform`, which contains `LATITUDE`'s `lat` alias - so a file with a
  `PLATFORM` column but no exact `LATITUDE` column had its platform renamed to
  `LATITUDE`), and the fallback's "column name inside the alias" direction now
  requires a prefix, since an abbreviation shortens from the end (`event` for
  `eventno`) rather than landing in the middle.
* `survey.platform_code` matches by value rather than by type: a zero-padded
  `"099"` in the data matches a config that says `99`, and an export that names
  its platforms (`"Vessel"`, `"Aerial"`) instead of coding them numerically can
  be matched by name, case-insensitively.

* The survey CSV is now read with every column as text instead of letting
  `readr` guess. Guessing corrupted values this pipeline depends on: a `FILEID`
  column whose values are all `"F"` guesses as logical and arrived as
  `"FALSE"`, and one mixing `"T"`/`"F"` codes became `TRUE`/`FALSE`. Every
  column the pipeline uses was already being coerced to its expected type after
  the column-name standardization step, so nothing else changes - except that a
  zero-padded `PLATFORM` (`"099"`, as NARWC writes it) is now converted before
  being compared against a config that says `99`.
* New `survey.split_surveys_by` (`"none"` by default, or `"date"` /
  `"date_platform"`): derives a per-survey `FILEID` for an export that doesn't
  use `FILEID` as a survey identifier - one where every record carries the same
  value, say. Without it such a file is a single survey covering everything,
  which errors in `build_detection_arrays()` for spanning multiple days, and
  would otherwise leave one replicate column per season - no repeat visits for
  the occupancy model to estimate detection from. The derived ID keeps the
  original `FILEID` as a prefix, and is built after the `FILEID`-prefix filter
  runs, so prefixes still mean what they do in the source file.

* `build_detection_arrays()` now explains the multi-day-`FILEID` error instead
  of printing `">1 jday. STOP!"` and calling a bare `stop()` (which surfaces as
  an error with no message at all). It names the offending `FILEID`, its
  season, and the calendar dates it spans, and says what the constraint is:
  one `FILEID` is one single-day survey, i.e. one replicate column with julian
  day as a per-survey detection covariate.

* `survey.platform_code` and `survey.fileid_prefixes` are now checked rather
  than assumed: an unset one errors saying which is missing, instead of
  silently filtering every record away (`PLATFORM == NULL` matches nothing).
  They stay required - `build_detection_arrays()` assumes a single survey type,
  and the detection model has no platform covariate - but `platform_code` now
  accepts several codes for a deliberately combined analysis. Setting
  `platform_code` for a file with no `PLATFORM` column also errors saying so.
  `diagnose_pipeline()` stops at the survey-data step when zero records survive
  filtering, rather than continuing into `build_detection_arrays()` and
  reporting an internal type error that says nothing about the real cause.
* New `standardize_survey_columns()`, now called automatically at the start
  of `prep_survey_data()`: renames a real-world survey CSV's columns to the
  exact NARWC names this pipeline expects whenever a case-insensitive match
  or a common alias is found (e.g. `Event`/`Event No.` -> `EVENTNO`,
  `Sp. Code` -> `SPECCODE`), so a real export doesn't need manual renaming
  first. `ALT` (altitude) gets a further fallback: if still missing after
  alias matching, every record is given a constant default (750, overridable
  via `alt_default`) with a warning, since this pipeline's own filtering
  doesn't use it. A genuinely required column that can't be matched at all
  still errors clearly, listing what was and wasn't found.
* New `diagnose_pipeline()`: runs `prep_survey_data()`/`build_detection_arrays()`
  (never JAGS) and reports the most common reasons a run fails, hangs, or
  produces meaningless output - a filter that leaves nothing, a study-area
  polygon that misses the survey tracks, a species with zero detections, a
  record outside every configured season, or a covariate matrix with the
  wrong shape - as a plain PASS/WARN/FAIL report. Meant to run before
  `run_occupancy_model()`. `prep_survey_data()` also gained a `verbose`
  argument reporting row counts through each filter step, and now warns
  (rather than silently proceeding) when zero records survive filtering,
  when a record falls in the configured month but outside every configured
  season's day-range, or when zero records end up on-effort.
* `generate_config(overwrite = FALSE)` (the default) now warns and leaves an
  existing config unchanged, instead of erroring.
* Fixed a silent-data-corruption bug: `fit_occupancy_model()` reshaped a
  covariate matrix into its internal array via `array(dim = ..., data = ...)`
  without checking its shape first - a covariate matrix with the wrong
  number of rows/columns for a run's grid would get silently recycled into
  misaligned values (when the element counts happened to divide evenly)
  rather than erroring, and the model would fit "successfully" on wrong
  data. Now validated explicitly before use.
* Added OneDrive as a second option (alongside Google Drive) for
  `prep_survey_data()` to fetch `paths.data_file` automatically when it's
  missing locally: `paths.onedrive_filename` (the path within OneDrive) and
  `paths.onedrive_type` (`"personal"`, the default, or `"business"` for a
  shared/org OneDrive), via the optional `Microsoft365R` package. See the
  README's "Fetching survey data" section.
* `survey.on_effort_legtypes` is now a config field (default `c(5, 6)`, the
  vessel codes), rather than hardcoded - `prep_survey_data()`'s on-effort
  filter previously only recognized NARWC's ship `LEGTYPE` codes, so every
  record from a non-vessel platform (e.g. a POP aerial survey, codes `7`/`9`)
  would have been dropped as off-effort. `platform_code`/`fileid_prefixes`
  were already config-driven; this was the one remaining vessel-only
  assumption. See `?generate_config` for an aerial-survey example.
* Corrected several NARWC handbook section citations in `generate_mock_data()`
  and `generate_config()`'s documentation that were off by one throughout
  (e.g. `LEGTYPE` is really 8.A.21, not 8.A.20 as previously cited).
* A fit with covariates configured can now be plotted with
  [`fancyfx`](https://github.com/chross22/fancyfx) (optional, `Suggests`):
  `fit_occupancy_model()` tags its result as `msomgom_fit` and attaches the
  metadata `effect_estimates.msomgom_fit()` needs to plot a covariate's
  fitted effect - `fancyfx::plotEffects(fit, dat, "sst")` draws the effect
  curve with a rug of the raw data above it, the same way it plots an
  `mgcv::gam`'s partial effects. See the README's "Covariate effect plots"
  section.

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
