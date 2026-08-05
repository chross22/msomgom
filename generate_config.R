# Programmatically writes a config YAML file into configs/, so multiple runs
# (different study areas, species, date ranges, MCMC settings, ...) can be
# kept as separate named files instead of hand-editing one config.yaml.
#
# Defaults reproduce the pipeline's original Bay of Fundy / RIWH settings, so
# generate_config("some_name") with no other arguments is a working config.
#
# library(yaml) is required; load_config.R also depends on it.

generate_config <- function(
  name,
  configs_dir = "configs",
  overwrite = FALSE,

  project_dir = ".",
  data_file = "data/survey_data.csv",
  google_drive_filename = NULL,
  output_dir = "output",

  platform_code = 99,
  fileid_prefixes = c("P", "p"),

  beg_year = 1988,
  end_year = 2020,
  beg_month = 8,
  end_month = 9,

  # list of list(begin = c(month, day), end = c(month, day)), one per season
  seasons = list(
    list(begin = c(8, 1), end = c(8, 31)),
    list(begin = c(9, 1), end = c(9, 30))
  ),

  cell_size = 0.05,
  # list of c(lon, lat) vertices, or an n x 2 matrix/data.frame of lon/lat
  polygon = list(
    c(-66.45, 44.82),
    c(-66.28, 44.78),
    c(-66.28, 44.67),
    c(-66.37, 44.55),
    c(-66.50, 44.48),
    c(-66.62, 44.48),
    c(-66.62, 44.70),
    c(-66.45, 44.82)
  ),

  species_codes = c("RIWH"),
  active_species = species_codes[1],

  # names of covariates (matching names in the occ_covariates list passed to
  # run_occupancy_model()/fit_occupancy_model()) to put on initial occupancy,
  # persistence, and colonization respectively. Empty (the default) means
  # that process stays intercept-only, exactly as before this option existed.
  covariates_psi = character(0),
  covariates_phi = character(0),
  covariates_gamma = character(0),

  make_figs = FALSE,

  n_chains = 3,
  n_adapt = 5000,
  n_burn = 5000,
  n_iter = 20000,
  thin = 1,
  jags_params = "colext",
  save_results = TRUE,

  run_evaluation = TRUE,
  save_evaluation_plots = TRUE,

  cleanup_after_run = FALSE
) {
  if (!requireNamespace("yaml", quietly = TRUE)) {
    stop("The 'yaml' package is required. Install it with install.packages('yaml').")
  }

  if (!(jags_params %in% c("colext", "Z"))) {
    stop("jags_params must be 'colext' or 'Z', got: ", jags_params)
  }
  if (!(active_species %in% species_codes)) {
    stop("active_species ('", active_species, "') must be one of species_codes: ",
         paste(species_codes, collapse = ", "))
  }
  for (s in seasons) {
    if (!all(c("begin", "end") %in% names(s)) || length(s$begin) != 2 || length(s$end) != 2) {
      stop("each element of seasons must be list(begin = c(month, day), end = c(month, day))")
    }
  }

  # normalize polygon input (list of pairs, or matrix/data.frame with 2 columns) to a list of c(lon, lat)
  if (is.matrix(polygon) || is.data.frame(polygon)) {
    polygon <- lapply(seq_len(nrow(polygon)), function(i) as.numeric(polygon[i, 1:2]))
  }
  for (pt in polygon) {
    if (length(pt) != 2) stop("each polygon vertex must be c(lon, lat)")
  }

  config <- list(
    paths = list(
      project_dir = project_dir,
      data_file = data_file,
      google_drive_filename = google_drive_filename,
      output_dir = output_dir
    ),
    survey = list(
      platform_code = as.integer(platform_code),
      fileid_prefixes = as.list(fileid_prefixes)
    ),
    dates = list(
      beg_year = as.integer(beg_year),
      end_year = as.integer(end_year),
      beg_month = as.integer(beg_month),
      end_month = as.integer(end_month)
    ),
    seasons = lapply(seasons, function(s) list(begin = as.list(as.integer(s$begin)), end = as.list(as.integer(s$end)))),
    study_area = list(
      cell_size = cell_size,
      polygon = lapply(polygon, function(pt) as.list(as.numeric(pt)))
    ),
    species = list(
      codes = as.list(species_codes),
      active = active_species
    ),
    covariates = list(
      psi = as.list(covariates_psi),
      phi = as.list(covariates_phi),
      gamma = as.list(covariates_gamma)
    ),
    output = list(
      make_figs = make_figs
    ),
    jags = list(
      n_chains = as.integer(n_chains),
      n_adapt = as.integer(n_adapt),
      n_burn = as.integer(n_burn),
      n_iter = as.integer(n_iter),
      thin = as.integer(thin),
      params = jags_params,
      save_results = save_results
    ),
    evaluation = list(
      run_after_fit = run_evaluation,
      save_plots = save_evaluation_plots
    ),
    cleanup = list(
      run_after_model = cleanup_after_run
    )
  )

  if (!dir.exists(configs_dir)) dir.create(configs_dir, recursive = TRUE)
  out_path <- file.path(configs_dir, paste0(name, ".yaml"))
  if (file.exists(out_path) && !overwrite) {
    stop("Config already exists at '", out_path, "'. Pass overwrite = TRUE to replace it.")
  }

  yaml::write_yaml(config, file = out_path)
  message("Wrote config to ", out_path)
  invisible(out_path)
}
