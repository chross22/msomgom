# Loads and validates a pipeline config YAML (see configs/*.yaml, generate_config.R),
# resolving paths and expanding seasons/polygon into the matrix forms
# makeSeasons()/st_polygon() expect.

load_config <- function(path) {
  if (!requireNamespace("yaml", quietly = TRUE)) {
    stop("The 'yaml' package is required. Install it with install.packages('yaml').")
  }
  if (!file.exists(path)) {
    stop("Config file not found: ", path)
  }

  config <- yaml::read_yaml(path)

  # resolve paths relative to project_dir
  project_dir <- normalizePath(config$paths$project_dir, mustWork = TRUE)
  config$paths$project_dir <- project_dir
  if (!isAbsolutePath(config$paths$data_file)) {
    config$paths$data_file <- file.path(project_dir, config$paths$data_file)
  }
  if (!isAbsolutePath(config$paths$output_dir)) {
    config$paths$output_dir <- file.path(project_dir, config$paths$output_dir)
  }

  if (!file.exists(config$paths$data_file) && is.null(config$paths$google_drive_filename)) {
    stop("Data file not found at '", config$paths$data_file,
         "', and paths.google_drive_filename is not set to allow downloading it.")
  }

  # seasons: list of list(begin = c(m,d), end = c(m,d)) -> ssn_beg / ssn_end matrices
  config$ssn_beg <- do.call(rbind, lapply(config$seasons, function(s) as.numeric(s$begin)))
  config$ssn_end <- do.call(rbind, lapply(config$seasons, function(s) as.numeric(s$end)))

  # study-area polygon: list of [lon, lat] -> matrix with lon/lat columns, closed ring
  poly_pts <- do.call(rbind, lapply(config$study_area$polygon, function(pt) as.numeric(pt)))
  colnames(poly_pts) <- c("lon", "lat")
  if (!identical(poly_pts[1, ], poly_pts[nrow(poly_pts), ])) {
    poly_pts <- rbind(poly_pts, poly_pts[1, ])
  }
  config$study_area$polygon_matrix <- poly_pts

  if (!(config$species$active %in% unlist(config$species$codes))) {
    stop("species.active ('", config$species$active, "') must be one of species.codes: ",
         paste(unlist(config$species$codes), collapse = ", "))
  }

  config
}

isAbsolutePath <- function(path) {
  grepl("^(/|~|[A-Za-z]:[\\\\/])", path)
}
