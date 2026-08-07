#' Generate a synthetic survey CSV for testing
#'
#' Generates a synthetic survey CSV matching the schema `data_prep.R` expects,
#' so the pipeline can be exercised end-to-end without the real NARWC
#' dataset.
#'
#' Column codes and value ranges are grounded in the NARWC Sightings Database
#' User's Guide (2021 update) rather than guessed, matching what the existing
#' filters in `data_prep.R` already assume:
#' \itemize{
#'   \item PLATFORM 099 = R/V Nereid (8.A.26)
#'   \item FILEID starting P/p = POP shipboard survey (8.A.11); p1 = NEAQ Fundy survey
#'   \item LEGTYPE 5 = ship underway, 6 = ship not underway (8.A.20)
#'   \item LEGSTAGE 1/2/5 = begin/continue/end watch (8.A.19)
#'   \item VISIBLTY >= 2 (n.mi.) or -1 (legacy "clear, >=2nm" flag) (8.A.37)
#'   \item BEAUFORT sea state 0-9, "7" meaning "7 or greater" (8.A.3)
#'   \item IDREL 3 = definite species ID, 9 = not a sighting (8.A.15)
#'   \item CONFIDNC 00-11 confidence-in-count code (8.A.7)
#'   \item SPECCODE RIWH/HUWH/FIWH/MIWH/HAPO = right/humpback/fin/minke whale, harbor porpoise (8.A.28)
#'   \item TIME/GMT is HHMMSS, 24-hour, now archived in GMT (8.A.36)
#' }
#'
#' Builds a handful of synthetic vessel tracks per season/year within the
#' configured study-area polygon, with a mix of on-track position events and
#' interspersed sightings (including some decoy records that should be
#' filtered out: other platforms, non-POP-shipboard FILEIDs) so the
#' pipeline's filters are actually exercised, not just its happy path.
#'
#' @param config_path path to a config YAML file (see `load_config()`); used
#'   for the study-area polygon, date range, and species codes
#' @param out_path where to write the CSV; defaults to `config$paths$data_file`
#' @param surveys_per_season number of synthetic vessel surveys per season/year
#' @param points_per_survey number of position fixes per survey (~5-minute intervals)
#' @param sighting_probability probability of a sighting record after each position fix
#' @param decoy_fraction fraction of records duplicated as decoys (wrong
#'   platform or non-POP-shipboard FILEID) that the pipeline's filters should drop
#' @param seed random seed, for reproducible mock data
#' @return the path the CSV was written to, invisibly
#' @seealso [generate_config()] to create `config_path` first;
#'   [run_occupancy_model()], run against the resulting CSV in the README's
#'   "Try it without real data" walkthrough
#' @family testing helpers
#' @examples
#' \dontrun{
#' generate_config("mock_test", data_file = "data/mock_survey_data.csv",
#'                  n_chains = 2, n_adapt = 100, n_burn = 100, n_iter = 200)
#' generate_mock_data("configs/mock_test.yaml")
#' run_occupancy_model("configs/mock_test.yaml")
#' }
#' @export
generate_mock_data <- function(config_path, out_path = NULL,
                                surveys_per_season = 3,
                                points_per_survey = 14,
                                sighting_probability = 0.3,
                                decoy_fraction = 0.08,
                                seed = 1) {
  if (!requireNamespace("yaml", quietly = TRUE)) {
    stop("The 'yaml' package is required. Install it with install.packages('yaml').")
  }
  set.seed(seed)

  raw <- yaml::read_yaml(config_path)
  project_dir <- normalizePath(raw$paths$project_dir, mustWork = TRUE)
  if (is.null(out_path)) {
    out_path <- raw$paths$data_file
    if (!grepl("^(/|~)", out_path)) out_path <- file.path(project_dir, out_path)
  }

  poly <- do.call(rbind, lapply(raw$study_area$polygon, function(pt) as.numeric(pt)))
  lon_range <- range(poly[, 1])
  lat_range <- range(poly[, 2])

  years <- raw$dates$beg_year:raw$dates$end_year
  months <- unique(c(raw$dates$beg_month, raw$dates$end_month))
  target_species <- unlist(raw$species$codes)
  decoy_species_pool <- setdiff(c("HUWH", "FIWH", "MIWH", "HAPO"), target_species)
  if (length(decoy_species_pool) == 0) decoy_species_pool <- "HAPO"

  wx_codes <- c("C", "H", "G", "L", "P")
  rows <- list()
  fileid_seq <- 0

  for (yr in years) {
    yy <- sprintf("%02d", yr %% 100)
    prefix_letter <- if (yr >= 2000) "p" else "P" # NARWC convention: lower-case FILEID prefix from year 2000 on

    for (mo in months) {
      for (s in seq_len(surveys_per_season)) {
        fileid_seq <- fileid_seq + 1
        start_day <- sample(5:25, 1) # avoid month boundaries so GMT->ET conversion can't shift the calendar month
        start_hour <- sample(12:18, 1) # daytime GMT so the US/Eastern date matches the GMT date
        t0 <- as.POSIXct(sprintf("%04d-%02d-%02d %02d:%02d:00", yr, mo, start_day, start_hour, sample(0:59, 1)), tz = "GMT")
        jday <- as.numeric(format(t0, "%j"))
        fileid <- sprintf("%s1%s%03d%s", prefix_letter, yy, jday, letters[((fileid_seq - 1) %% 26) + 1])

        # a simple survey line across the study area, with small perturbation per point
        lon0 <- runif(1, lon_range[1], lon_range[2])
        lat0 <- runif(1, lat_range[1], lat_range[2])
        dlon <- runif(1, -1, 1) * 0.01
        dlat <- runif(1, -1, 1) * 0.01
        legtype <- sample(c(5, 6), 1) # ship underway vs. not underway (listening station)

        for (pt in seq_len(points_per_survey)) {
          t <- t0 + (pt - 1) * 300 # ~5-minute fixes, matches the handbook's shipboard recording interval
          lon <- min(max(lon0 + dlon * pt + rnorm(1, 0, 0.002), lon_range[1]), lon_range[2])
          lat <- min(max(lat0 + dlat * pt + rnorm(1, 0, 0.002), lat_range[1]), lat_range[2])
          legstage <- if (pt == 1) 1 else if (pt == points_per_survey) 5 else 2

          rows[[length(rows) + 1]] <- data.frame(
            FILEID = fileid, EVENTNO = pt * 10, PLATFORM = 99,
            MONTH = as.numeric(format(t, "%m")), DAY = as.numeric(format(t, "%d")), YEAR = as.numeric(format(t, "%Y")),
            GMT = as.numeric(format(t, "%H%M%S")),
            LATITUDE = lat, LONGITUDE = lon,
            LEGTYPE = legtype, LEGSTAGE = legstage,
            ALT = NA, HEADING = sample(0:359, 1),
            WX = sample(wx_codes, 1), CLOUD = sample(1:4, 1),
            VISIBLTY = sample(c(2, 3, 4, 5, -1), 1), BEAUFORT = sample(0:6, 1),
            SPECCODE = NA, IDREL = NA, NUMBER = NA, CONFIDNC = NA,
            BEHAV1 = NA, BEHAV2 = NA,
            stringsAsFactors = FALSE
          )

          if (runif(1) < sighting_probability) {
            spp <- sample(c(target_species, decoy_species_pool), 1,
                           prob = c(rep(2, length(target_species)), rep(1, length(decoy_species_pool))))
            rows[[length(rows) + 1]] <- data.frame(
              FILEID = fileid, EVENTNO = pt * 10 + 5, PLATFORM = 99,
              MONTH = as.numeric(format(t, "%m")), DAY = as.numeric(format(t, "%d")), YEAR = as.numeric(format(t, "%Y")),
              GMT = as.numeric(format(t + 20, "%H%M%S")),
              LATITUDE = lat + rnorm(1, 0, 0.001), LONGITUDE = lon + rnorm(1, 0, 0.001),
              LEGTYPE = legtype, LEGSTAGE = 2,
              ALT = NA, HEADING = sample(0:359, 1),
              WX = sample(wx_codes, 1), CLOUD = sample(1:4, 1),
              VISIBLTY = sample(c(2, 3, 4, 5, -1), 1), BEAUFORT = sample(0:6, 1),
              SPECCODE = spp, IDREL = 3, NUMBER = sample(1:3, 1), CONFIDNC = sample(c(0, 1, 2, 4), 1),
              BEHAV1 = NA, BEHAV2 = NA,
              stringsAsFactors = FALSE
            )
          }
        }
      }
    }
  }

  dat <- do.call(rbind, rows)

  # sprinkle in decoy records that the pipeline's filters should drop: wrong
  # platform (not the Nereid) and non-POP-shipboard FILEIDs (opportunistic "O")
  n_decoy <- floor(nrow(dat) * decoy_fraction)
  if (n_decoy > 0) {
    decoy_idx <- sample(seq_len(nrow(dat)), n_decoy)
    decoys <- dat[decoy_idx, ]
    make_wrong_platform <- decoy_idx %% 2 == 0
    decoys$PLATFORM[make_wrong_platform] <- 107 # Silver (WCNE), a different whale-watch vessel
    decoys$FILEID[!make_wrong_platform] <- sub("^[Pp]", "O", decoys$FILEID[!make_wrong_platform])
    dat <- rbind(dat, decoys)
  }

  dat <- dat[order(dat$FILEID, dat$EVENTNO), ]

  out_dir <- dirname(out_path)
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
  write.csv(dat, out_path, row.names = FALSE, na = "")
  message("Wrote ", nrow(dat), " mock survey records to ", out_path)
  invisible(out_path)
}
