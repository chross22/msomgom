# dynocc (development version)

* A covariate recipe's derive steps are now filled and typo-checked exactly
  like its source function, which makes bathymetry reachable from a config:
  a step taking `bathy` - `datamatch::attach_bathymetry()`, the way `DEPTH`
  and `SLOPE` become covariates - has one fetched for the study area, since a
  bathymetry raster is not something a YAML file can hold. Filling is lazy,
  so a recipe that never asks for bathymetry never downloads any.

* A flat process map now says on the figure why it is flat. With no
  covariate on a process, `plot_process_map()` draws the intercept in every
  cell - correctly, since there is no spatial term - and a one-colour hex
  grid reads as a rendering fault rather than as the answer. The title now
  carries "intercept only: no covariate on <process>, so every cell is
  identical", and `predict.dynocc_fit()` records the covariates behind a
  surface in a `"covariates"` attribute, so a caller can tell an
  intercept-only surface from one whose covariate happens to be constant.

* **The colonization/persistence dynamics now actually engage.** The
  season/year structure was hardcoded to one season per "year", so the model
  treated every season as an independent year, the transition loop
  (`l in 2:n.season`) never executed, and `mu.e.0`/`mu.g.0` came back as
  exactly their `dnorm(0, 0.1)` priors - sd 3.16, ESS = every draw - on every
  fit this package has ever produced. The 4-D `[site, visit, season, year]`
  machinery was built for the real structure and had simply never been fed
  it: seasons-per-year now comes from `config$seasons`, initial occupancy is
  estimated at each year's first season, transitions run between consecutive
  within-year seasons, and years are exchangeable draws around the
  hyper-means. On a fixture fit the phi/gamma posteriors now visibly tighten
  away from the prior. Anything fit before this change was a set of
  independent single-season occupancy models sharing hyper-priors, whatever
  the parameter names said - refit.

* With real within-year seasons, `Z` is indexed `[site, season, year]`, so
  `plot_occupancy_map()` and `compare_naive_vs_modeled_occupancy()` now speak
  the absolute season index used everywhere else (the arrays' 3rd dimension,
  `plot_detection_history()`'s columns, `season_windows_from_config()`'s
  rows). `plot_occupancy_map()`'s argument is `season`; `year` still works as
  a deprecated alias, since it always meant that same index. The
  naive-vs-modeled table gains a `season` column and reports one row per
  season rather than per year.

* **The month filter is a range, and it can wrap the year.** It used to be
  equality against the two endpoints - indistinguishable from a range when
  they are adjacent, which the original Aug/Sep analysis's were, and silently
  wrong otherwise: `beg_month: 1, end_month: 12` kept January and December
  and discarded the other ten months. It now keeps every month from
  `beg_month` through `end_month`, and `beg_month > end_month` wraps around
  the new year (11/2 means Nov-Feb). `generate_mock_data()` had the same
  endpoint-only habit and now places surveys in every configured season
  instead, so a fixture season the config declares is no longer invisibly
  empty.

* **A season nothing surveyed builds as unobserved instead of crashing.**
  `build_detection_arrays()` ran its survey loop as `1:0` when a season had
  zero surveys, and the NA FILEID that indexed out surfaced as a baffling
  "FILEID 'NA' spans 0 calendar days" error. A zero-survey season now gets a
  zero `reps` row and NA arrays - unobserved, which is what it is - and the
  per-season survey counts are reported as messages. The leftover debug
  `print()` calls that dumped whole vectors to the console went in the same
  pass.

* **Any datamatch or derivoce covariate can now go into the model.**
  `build_covariates()` runs the whole covariate stage from the config alone:
  each entry under `covariates.sources` is a pipeline that names a datamatch
  access function and then any number of derivoce derive steps, and the result
  is averaged onto the model's own grid and seasons. Because a recipe *names*
  the function rather than picking from a fixed menu, all seven datamatch
  access functions (Copernicus, HYCOM, ERDDAP, FVCOM, CCMP, CEFI, OB.DAAC) and
  every derivoce function are reachable, including ones either package gains
  later. `years`/`months`/`bounding_box` are filled in from the config's date
  range and study-area polygon, so a recipe only states what they don't imply.
  Only exports of datamatch, derivoce and dynocc can be named - a config file
  is data, not code. A process names *columns*, not recipes, and a column
  configured on a process that no recipe produced is an error naming both
  sides rather than a fit quietly missing a covariate.

* **A `colext` fit can now be mapped.** `predict()` on a `dynocc_fit` returns
  the per-cell posterior of initial occupancy (`psi`), persistence (`phi`) or
  colonization (`gamma`), and `plot_process_map()` draws it. Each posterior
  draw's coefficients are pushed through that draw's inverse logit at every
  cell, so the summaries are posterior summaries of the surface rather than
  transformations of coefficient summaries, and the fit's own standardization
  of each covariate is replayed from the metadata stored at fitting time.
  This is the spatial view a coefficient-level fit implies but never stores -
  `plot_occupancy_map()` still needs `jags_params = "Z"` for realized
  occupancy. Two limits are documented rather than papered over: only the
  hyper-mean intercepts are tracked, so a map is the population-level surface
  and `season` moves it through covariate values alone; and a process with no
  covariates is flat by construction, which is said out loud rather than
  drawn as if it meant something.

* `plot_occupancy_map()` and `plot_process_map()` both take `stat = "sd"` for
  the posterior-uncertainty map. A striking mean surface over cells the
  posterior barely constrains is a prior in a costume, and the two maps are
  meant to be read together.

* **The package is now called `dynocc`** (was `msomgom`). It was never
  Gulf-of-Maine-specific once study area, species, and seasons went
  config-driven, and the model it fits - single-species, multi-season with
  colonization/persistence - is exactly what the literature calls a dynamic
  occupancy model. The fitted-model class follows: `msomgom_fit` is now
  `dynocc_fit`, so a fit saved by an older version won't dispatch to
  `effect_estimates()` until refit (the underlying `mcmc.list` methods are
  unaffected). The GitHub repository redirects from the old name.

* `average_covariates()` keeps up with what datamatch (>= 0.2.0) now sends
  along with the values: the `<var>_source`/`<var>_depth` provenance columns,
  `.datamatch_source`, and an `HOUR` column on hourly data are excluded from
  the default `vars` instead of being averaged - a character `SST_source`
  column used to become a covariate of `NA`s behind a `mean()` warning. A
  provenance suffix only counts when its base variable is present, so a real
  covariate that merely ends in `_depth` (`mixed_layer_depth`, say) is
  untouched; any other non-numeric column is skipped with a message. Naming a
  missing or non-numeric column in `vars` explicitly is now a clear error
  instead of a quiet `NA` matrix.

* `effect_estimates.dynocc_fit()` accepts the `data` argument
  `fancyfx::effect_estimates()` (>= 0.11.0) added to its signature - accepted
  and ignored, since a dynocc fit keeps the covariate data it was fit on and
  the evaluation range always comes from there.

* Two new diagnostic plots, in the same look-before-you-fit spirit as the
  existing four: `plot_detection_history()` draws the site x season
  detection/effort tiles that are the occupancy likelihood's entire
  information content, and `plot_convergence()` draws Rhat against effective
  sample size for every tracked parameter, labeling the ones outside the
  thresholds `evaluate_occupancy_model()` warns about.

* `docs/diagnostics-architecture.md` records the plan for the analysis layer:
  a `dynoccfit` repository mimicking `dsmfit`'s targets-and-renv workflow, with
  gut-check figure targets at each pipeline seam.

* dynocc now depends on **narwcr** (chross22/narwcr) instead of keeping its
  own copy of the NARWC vocabulary. `standardize_survey_columns()` runs
  `narwcr::standardize_narwc_columns()` first, so the alias table, the `Trk*`
  GPS-track preferred sources, the alias priorities and the feet-to-metres
  conversions are all narwcr's, and its rename and conversion reports are
  shown. What stays here is what narwcr deliberately doesn't do: the substring
  fallback for a column nobody enumerated, preferring the candidate that has
  data (including rescuing a canonical column that came through empty),
  `PLATFORM` aliases, the `ALT` default, and deriving `YEAR`/`MONTH`/`DAY`/
  `TIME` from a date column. Behaviour is otherwise unchanged; the warning text
  for a preferred-source swap is now narwcr's wording.

* `TIME` is parsed rather than coerced with `as.numeric()`. The handbook's form
  is `hhmmss` (8.A.37) and that's still what's stored, but real files write
  `"12:34:56"`, `"12:34"`, and whole timestamps like `"2024-04-01T12:34:56Z"` -
  and `as.numeric()` turns every one of those into `NA` without a word, so a
  file with a perfectly good clock arrived with no times at all. Preferring
  `TrkTime_UTC` makes that more likely, since a GPS track log is exactly where
  a clock-formatted time comes from.
* The general form of that failure now warns: a numeric column that had values
  in the file and is entirely `NA` after being read as numbers was emptied by
  the coercion, not by the data, and `prep_survey_data()` says so instead of
  handing back a column of `NA`.
* `LEGTYPE_BK` joins the preferred-source rule - where a file carries both, it
  is the leg type to believe, and the plain `LEGTYPE` is kept as
  `LEGTYPE_ORIGINAL`. `standardize_survey_columns()`'s `prefer_track` argument
  is renamed `prefer_source` accordingly, since `LEGTYPE_BK` has nothing to do
  with a GPS track.
* Synced with the rules narwcr (chross22/narwcr) added on 2026-08-11, since the
  two packages read the same archive and keep the same vocabulary by hand:
  * The `Trk*` GPS track family is recognised (`TrkLatitude`, `TrkLongitude`,
    `TrkAltitude_m`/`_ft`, `TrkTime_UTC`/`_Local`) and, where one exists, it
    displaces a `LATITUDE`/`LONGITUDE`/`ALT`/`TIME` column already present
    under its own name: those are the platform's own track log versus the
    position recorded for the platform, which on a file covering both a vessel
    and an aircraft is not the same place. The displaced column is kept as
    `<CANONICAL>_ORIGINAL`, the swap warns, and `prefer_track = FALSE` turns it
    off. `TrkTime_Local` displaces nothing - it would move the dataset onto
    another zone to gain the receiver's seconds.
  * `ALT` is metres (handbook 8.A.1). A column whose name declares feet
    (`Alt_ft`, `TrkAltitude_ft`) is multiplied by 0.3048 with a warning, and a
    file carrying both `TrkAltitude_m` and `TrkAltitude_ft` takes the metres
    one. **`alt_default` is now 229 (750 ft in metres), not 750** - that
    default only applies to files with no altitude column at all, and this
    pipeline's own filtering doesn't use `ALT`.
  * Documented priority now breaks ties between columns that both have data:
    `TrkTime_UTC` over a plain UTC spelling, UTC over local, `TrkAltitude_m`
    over `TrkAltitude_ft`. Having data still comes first.
  * A supplied date column is kept as `DATE` (parsed, never left as raw text)
    instead of only being mined for `YEAR`/`MONTH`/`DAY`, and
    `prep_survey_data()` dates a record from `DATE` when it's there. Rebuilding
    the date from the parts pairs a date on the recording programme's clock
    with a `TIME` that may now come from the GPS track log in UTC, which puts
    every record within the offset of midnight on the wrong day - silently,
    since the result is still a valid date.

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
  `fit_occupancy_model()` tags its result as `dynocc_fit` and attaches the
  metadata `effect_estimates.dynocc_fit()` needs to plot a covariate's
  fitted effect - `fancyfx::plotEffects(fit, dat, "sst")` draws the effect
  curve with a rug of the raw data above it, the same way it plots an
  `mgcv::gam`'s partial effects. See the README's "Covariate effect plots"
  section.

# dynocc 0.1.0

First tagged release. `dynocc` fits a dynamic (multi-season,
colonization/persistence) occupancy model, following MacKenzie et al.
(2003), to cetacean vessel-survey sightings via JAGS. Everything below is
config-driven; nothing is hardcoded to the Bay of Fundy/right-whale case it
was originally built around.

## Package

* Converted from a collection of `source()`d scripts into a standard,
  installable R package (`DESCRIPTION`/`NAMESPACE`, `R/`, `man/`, `inst/`,
  `vignettes/`, `tests/testthat/`). `devtools::check()` passes 0 errors/0
  warnings/0 notes.
* `vignette("getting-started", package = "dynocc")` walks through the whole
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
