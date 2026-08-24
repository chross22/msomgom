# --- config-driven covariate building --------------------------------------
#
# The covariate stage, from a config block to the matrices
# fit_occupancy_model() takes. Every function that actually fetches or derives
# anything lives in datamatch or derivoce; what lives here is the dispatch -
# reading a recipe out of the config, calling the named function with the
# arguments the config gave it plus the ones the config already implies
# (study area, years, months), and averaging the result onto the model's grid.
#
# Deliberately not a fixed menu of "kinds": datamatch exports eight access
# functions and derivoce forty derived-covariate functions, and both grow.
# Naming the function in the config means a covariate the packages gained
# yesterday is usable today without a change here.

# Only these packages' exports can be named in a config. A config file is
# data, not code, and `fn: system` should never be a way to run something.
covariate_packages <- c("datamatch", "derivoce", "dynocc")

#' Resolve a covariate function named in a config
#'
#' @param fn function name, as written in the config
#' @param what `"source"` or `"derive"`, for the error message
#' @return the function itself
#' @keywords internal
resolve_covariate_fn <- function(fn, what = "source") {
  if (!is.character(fn) || length(fn) != 1) {
    stop("A covariate ", what, "'s `fn` must be a single function name, ",
         "written as a string.", call. = FALSE)
  }
  for (pkg in covariate_packages) {
    if (!requireNamespace(pkg, quietly = TRUE)) next
    if (fn %in% getNamespaceExports(pkg)) {
      return(getExportedValue(pkg, fn))
    }
  }
  installed <- covariate_packages[vapply(covariate_packages, requireNamespace,
                                          logical(1), quietly = TRUE)]
  missing_pkgs <- setdiff(covariate_packages, installed)
  stop("'", fn, "' is not an exported function of ",
       paste(installed, collapse = ", "),
       if (length(missing_pkgs)) {
         paste0(" (and ", paste(missing_pkgs, collapse = ", "),
                " is not installed, so its functions can't be reached)")
       } else "",
       ".\n  A covariate `fn` must name a function from one of these ",
       "packages - datamatch's access functions fetch fields ",
       "(accessCopernicus, accessHYCOM, accessERDDAP, ...), derivoce's derive ",
       "from them (horizontal_gradient, distance_to_shore, eke, ...).",
       call. = FALSE)
}

#' Fill in the arguments a config already implies
#'
#' A source function that takes `years`/`months`/`bounding_box` gets them from
#' the config's date range and study-area polygon unless the recipe set them
#' explicitly. Anything the function doesn't have a formal for is left out, so
#' this works across access functions with different signatures.
#'
#' @param fn the resolved function
#' @param args the recipe's own `args`, which always win
#' @param config a config list, as returned by `load_config()`
#' @return the full argument list to call `fn` with
#' @seealso [build_covariates()], which calls this for both source and derive
#'   steps; `datamatch::fetch_bathymetry()`, the source of an implied `bathy`
#' @keywords internal
fill_covariate_args <- function(fn, args, config) {
  args <- args %||% list()
  formals_names <- names(formals(fn))

  # Each entry is a thunk, so nothing is computed unless the function being
  # called actually takes it - `bathy` costs a download.
  implied <- list(
    years = function() config$dates$beg_year:config$dates$end_year,
    months = function() config$dates$beg_month:config$dates$end_month,
    bounding_box = function() study_area_bbox(config),
    # A bathymetry raster is not something a YAML file can hold, so a step
    # that needs one - attach_bathymetry(), which is how DEPTH and SLOPE get
    # into a covariate table - has it fetched for the study area. Same
    # principle as bounding_box: the config already says which bathymetry.
    bathy = function() datamatch::fetch_bathymetry(study_area_bbox(config))
  )
  for (nm in names(implied)) {
    if (nm %in% formals_names && is.null(args[[nm]])) args[[nm]] <- implied[[nm]]()
  }

  unknown <- setdiff(names(args), formals_names)
  if (length(unknown) && !("..." %in% formals_names)) {
    stop("argument(s) ", paste(unknown, collapse = ", "), " were given to a ",
         "covariate function that has no such argument. It takes: ",
         paste(setdiff(formals_names, "..."), collapse = ", "), ".",
         call. = FALSE)
  }
  args
}

#' The study area's bounding box, as datamatch expects it
#'
#' @param config a config list, as returned by `load_config()`
#' @return `list(xmin, xmax, ymin, ymax)`
#' @keywords internal
study_area_bbox <- function(config) {
  poly <- config$study_area$polygon_matrix
  if (is.null(poly)) {
    poly <- do.call(rbind, lapply(config$study_area$polygon, function(pt) as.numeric(pt)))
  }
  list(xmin = min(poly[, 1]), xmax = max(poly[, 1]),
       ymin = min(poly[, 2]), ymax = max(poly[, 2]))
}

#' Run one covariate recipe: fetch a field, then derive from it
#'
#' @param recipe one entry of `config$covariates$sources`
#' @param config a config list, as returned by `load_config()`
#' @param name the recipe's name, for error messages
#' @return an `sf` POINT object in the shape [average_covariates()] consumes
#' @keywords internal
run_covariate_recipe <- function(recipe, config, name = "<unnamed>") {
  if (is.null(recipe$fn)) {
    stop("covariate source '", name, "' has no `fn`. Name the function that ",
         "fetches it - e.g. `fn: accessCopernicus` for Copernicus, or ",
         "`fn: load_covariate_netcdf` for local files.", call. = FALSE)
  }
  source_fn <- resolve_covariate_fn(recipe$fn, "source")
  env_dat <- do.call(source_fn, fill_covariate_args(source_fn, recipe$args, config))

  # `derive` is a list of steps, applied in order, each taking the env_dat the
  # last one produced. A single step may be written unwrapped.
  steps <- recipe$derive
  if (is.null(steps)) return(env_dat)
  if (!is.null(steps$fn)) steps <- list(steps)

  for (i in seq_along(steps)) {
    step <- steps[[i]]
    if (is.character(step) && length(step) == 1) step <- list(fn = step)
    if (is.null(step$fn)) {
      stop("derive step ", i, " of covariate source '", name, "' has no `fn`.",
           call. = FALSE)
    }
    derive_fn <- resolve_covariate_fn(step$fn, "derive")
    # Same filling and same typo-checking as a source function: a derive step
    # that takes `bathy` gets one fetched for the study area, and a misspelled
    # argument is refused rather than silently ignored.
    args <- fill_covariate_args(derive_fn, step$args, config)
    env_dat <- do.call(derive_fn, c(list(env_dat), args))
  }
  env_dat
}

#' Build every configured covariate, from the config alone
#'
#' The whole covariate stage in one call: run each recipe under
#' `config$covariates$sources` (fetch with a `datamatch` access function,
#' derive with any number of `derivoce` functions), average every resulting
#' column onto the occupancy grid and season windows, and return the named
#' list of `[num_cells x num_ssn]` matrices that [fit_occupancy_model()] takes
#' as `occ_covariates`.
#'
#' Any covariate either package can produce is usable, because a recipe names
#' the function rather than choosing from a fixed menu here:
#'
#' ```yaml
#' covariates:
#'   psi: [SST, shore_dist]        # names of columns, not of recipes
#'   phi: [SST_grad]
#'   gamma: []
#'   sources:
#'     ocean:
#'       fn: accessCopernicus      # any datamatch access function
#'       args:
#'         vars: [SST, UO, VO]     # years/months/bounding_box are implied
#'       derive:                   # any number of derive functions, in order
#'         - fn: horizontal_gradient
#'           args: {vars: SST}     # adds SST_grad
#'         - fn: eke               # adds EKE from UO/VO
#'         - fn: distance_to_shore # adds shore_dist
#'         - fn: attach_bathymetry # adds DEPTH; the raster is fetched for
#'           args: {vars: DEPTH}   #   the study area, not named in the config
#' ```
#'
#' A recipe is a *pipeline*, not a single covariate: one recipe can produce
#' many columns, and `psi`/`phi`/`gamma` name the columns they want from
#' everything produced. Names are checked against what was actually built, so
#' a covariate that was configured on a process but never produced is an error
#' naming both sides rather than a model fit without it.
#'
#' @param config a config list, as returned by [load_config()]
#' @param area_grid_sf the `sf` polygon grid to average onto, with a `grid_id`
#'   column - `arrays$area_grid_sf` from [build_detection_arrays()], so the
#'   covariate grid matches the model's exactly
#' @param windows data.frame of covariate windows; defaults to
#'   [season_windows_from_config()], so column `t` lines up with season `t`
#' @return a named list of `[num_cells x num_ssn]` matrices, one per built
#'   covariate column, ready to pass to [fit_occupancy_model()] as
#'   `occ_covariates`. `NULL` when no process has any covariates configured
#' @seealso [average_covariates()], which does the averaging;
#'   [fit_occupancy_model()], which consumes the result;
#'   [plot_covariate_map()] for checking one before fitting;
#'   `datamatch::accessCopernicus()` and `derivoce::horizontal_gradient()` for
#'   the two kinds of function a recipe names
#' @family covariates
#' @examples
#' \dontrun{
#' config <- load_config("configs/bof_riwh.yaml")
#' prep <- prep_survey_data(config)
#' arrays <- build_detection_arrays(prep$tmpdat, prep$season_info, config)
#'
#' occ_covariates <- build_covariates(config, arrays$area_grid_sf)
#' fit <- fit_occupancy_model(arrays, config, occ_covariates = occ_covariates)
#' }
#' @export
build_covariates <- function(config, area_grid_sf, windows = NULL) {
  wanted <- unique(unlist(config$covariates[c("psi", "phi", "gamma")]))
  if (is.null(wanted) || length(wanted) == 0) return(NULL)

  sources <- config$covariates$sources
  if (is.null(sources) || length(sources) == 0) {
    stop("covariates are configured on a process (", paste(wanted, collapse = ", "),
         ") but covariates.sources is empty, so there is no recipe saying where ",
         "any of them comes from. See ?build_covariates for the shape of a ",
         "source entry.", call. = FALSE)
  }
  if (is.null(windows)) windows <- season_windows_from_config(config)

  built <- list()
  for (nm in names(sources)) {
    env_dat <- run_covariate_recipe(sources[[nm]], config, name = nm)
    averaged <- average_covariates(env_dat, area_grid_sf, windows)
    duplicated_cols <- intersect(names(averaged), names(built))
    if (length(duplicated_cols)) {
      stop("covariate source '", nm, "' produced column(s) ",
           paste(duplicated_cols, collapse = ", "),
           " that another source already produced. Two sources can't both ",
           "define the same covariate - rename one, or drop it from one ",
           "recipe's `vars`.", call. = FALSE)
    }
    built <- c(built, averaged)
  }

  missing_cols <- setdiff(wanted, names(built))
  if (length(missing_cols)) {
    stop("covariate(s) ", paste(missing_cols, collapse = ", "),
         " are configured on a process but no source produced them.\n  Built: ",
         paste(names(built), collapse = ", "),
         ".\n  A process names a column, not a recipe - check the column names ",
         "the recipes actually produce (a derive step usually adds a suffix, ",
         "e.g. horizontal_gradient() adds '_grad').", call. = FALSE)
  }

  built[wanted]
}
