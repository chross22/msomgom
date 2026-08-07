#' Load and validate a pipeline config
#'
#' Reads a config YAML (see `configs/*.yaml`, `generate_config.R`), resolves
#' `paths.data_file`/`paths.output_dir` relative to `paths.project_dir`, and
#' expands `seasons`/`study_area.polygon` into the matrix forms
#' `makeSeasons()`/`st_polygon()` expect.
#'
#' @param path path to a config YAML file
#' @return the parsed config list, with `paths.project_dir`/`paths.data_file`/
#'   `paths.output_dir` resolved to absolute paths, plus two derived fields:
#'   `ssn_beg`/`ssn_end` (matrices for `makeSeasons()`) and
#'   `study_area$polygon_matrix` (a closed-ring `lon`/`lat` matrix for `st_polygon()`)
#' @seealso [generate_config()] to create a config file programmatically;
#'   [run_occupancy_model()], which calls this first
#' @family pipeline stages
#' @examples
#' \dontrun{
#' config <- load_config("configs/bof_riwh.yaml")
#' config$species$active
#' config$study_area$polygon_matrix
#' }
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

#' Check whether a path is absolute
#'
#' @param path a file path string
#' @return logical; `TRUE` if `path` starts with `/`, `~`, or a Windows drive
#'   letter (e.g. `C:\`)
#' @keywords internal
isAbsolutePath <- function(path) {
  grepl("^(/|~|[A-Za-z]:[\\\\/])", path)
}
