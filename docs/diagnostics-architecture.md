# The occupancy analysis's diagnostic pipeline

*Written 2026-08-21, updated 2026-08-24. The design for the analysis layer
above this package, mimicking the workflow `dsmfit` settled for the
density-surface work. The `dynoccfit` repository described here now exists and
runs end to end on the fixture.*

## The precedent

The distance-sampling side of this family is a three-layer split, argued out in
[`distsamp/docs/07-fitting-architecture.md`](https://github.com/chross22/distsamp/blob/main/docs/07-fitting-architecture.md):

| layer | holds | form |
|---|---|---|
| `distsamp` | NARWC ingest, effort, segmentation, distances | package |
| `dsfit` | the detection-function model set, the sweep | package |
| `dsmfit` | **which years, which truncation, which covariates, the report** | **`targets` + `renv`** |

The load-bearing rule: anything that is a *choice* lives in the analysis
repository's `config/analysis.yml`; anything that would be true of anyone's
survey lives upstream in a package. And the diagnostic figures live in the
analysis repository as **gut-check `targets` with `format = "file"`** - "what
you look at when a number says something is wrong and you want to see where" -
drawn by reusable plot functions that live upstream wherever they describe any
survey, and in the analysis repo's `R/` only where they describe this one.

## The occupancy analog

| layer | holds | form |
|---|---|---|
| `narwcr` | NARWC vocabulary, reading, column standardization | package |
| `datamatch` / `derivoce` / `fancyfx` | covariate access, derived covariates, effect figures | packages |
| `dynocc` | cleaning, gridding, arrays, the JAGS model, evaluation, **the per-stage plots** | package |
| `dynoccfit` (proposed name) | which species, years, grid size, seasons, priors, MCMC settings, the report | `targets` + `renv` |

`dynoccfit` mirrors `dsmfit` piece for piece:

- **`config/analysis.yml`** - the choices, tracked as a file target so editing
  a value invalidates exactly the targets downstream of it. dynocc's
  `generate_config()`/`load_config()` already speak YAML; the analysis config
  points at (or inlines) the dynocc config rather than replacing it.
- **`config/versions.yml`** - the five upstream packages pinned **by commit
  sha**, because their DESCRIPTION versions do not move when their behaviour
  does. `check_pinned()` stops the pipeline against wrong code; the shas feed
  the `config` target as a *value* so a moved pin rebuilds everything (the
  lesson dsmfit's `_targets.R` records: an installed package is not something
  `targets` hashes).
- **`run.R`** - `setup` / the pipeline / on-demand figure commands.
- **`reports/report.qmd`** - the rendered endpoint.
- **`data/` gitignored, fixture by default** - no NARWC records are committed;
  until pointed at a real extract the pipeline runs end-to-end on
  `dynocc::generate_mock_data()` (`source: fixture`), so the wiring is
  testable with nothing sensitive on disk. Same posture as `dsmfit`
  (`distsamp`'s synthetic fixture) and the taupatch work.

## The pipeline, with its gut checks

Stages, which layer owns each, and the figure target at each seam:

```
config      dynoccfit             config/analysis.yml
survey      narwcr + dynocc    standardize_survey_columns() -> prep_survey_data()
  check_survey     dynocc::plot from prep: what the effort filters kept   [file]
arrays      dynocc             build_detection_arrays()
  check_coverage   dynocc::plot_survey_coverage(), per season and summed  [file]
  check_sightings  dynocc::plot_sightings()                               [file]
  check_history    dynocc::plot_detection_history()  <- the likelihood,
                   tile by tile, before any fitting                        [file]
covars      datamatch/derivoce  any access fn -> any number of derive fns,
            + dynocc            named by config and run by build_covariates()
  check_covars     dynocc::plot_covariate_map(), one per covariate        [file]
fit         dynocc + JAGS      fit_occupancy_model()
  check_converge   dynocc::plot_convergence()                             [file]
  check_process    dynocc::plot_process_map(), psi/phi/gamma, mean and sd
                   - the fitted surfaces a colext fit implies but does
                     not store                                            [file]
evaluate    dynocc             evaluate_occupancy_model(): Rhat/ESS table,
                                naive-vs-modeled occupancy
  check_occupancy  dynocc::plot_occupancy_map(), per year (a "Z" fit only) [file]
effects     fancyfx             plotEffects() via dynocc's effect_estimates method
report      dynoccfit             reports/report.qmd
```

The division of labour for figures follows dsmfit exactly:

- **In dynocc** (they describe *any* occupancy survey): the seven
  `@family diagnostic plots` functions - `plot_survey_coverage()`,
  `plot_sightings()`, `plot_detection_history()`, `plot_covariate_map()`,
  `plot_occupancy_map()`, `plot_process_map()`, `plot_convergence()`. All base
  graphics, all built from the same arrays the model fits on (never a
  rederivation), all returning their underlying data invisibly so a figure can
  be tested numerically. `plot_process_map()` draws `predict.dynocc_fit()`,
  which is what makes a coefficient-level fit spatial at all.
- **In dynoccfit `R/`** (they describe *this* analysis): the multi-panel
  compositions and anything wired to `analysis.yml` - e.g. a
  season-by-season panel (`coverage | sightings | covariate` for one season),
  the analog of dsmfit's per-day survey panels, exposed on demand as
  `Rscript run.R season <n>` the way `run.R day` draws one survey day.

## What is not built yet

1. **A filter-accounting figure for the prep stage.**
   `prep_survey_data()` warns when the on-effort filter empties the data, but
   there is no figure showing what each filter
   (LEGTYPE/LEGSTAGE/VISIBLTY/IDREL/BEAUFORT) dropped. It needs
   `prep_survey_data()` to return per-filter counts before a plot can exist -
   an upstream change, so it is dynocc work, not dynoccfit work. It is the one
   seam in the table above with no figure guarding it.
2. **`renv`.** The pins in `config/versions.yml` cover the layer packages,
   which is where the behaviour moves; CRAN versions are recorded as minimums.
   Full reproducibility is `renv`'s job and can wait until the analysis
   settles.
