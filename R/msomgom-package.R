#' msomgom: Multi-Species Occupancy Model of the Gulf of Maine
#'
#' See the package README for a full walkthrough, or
#' `vignette("getting-started", package = "msomgom")`.
#'
#' @keywords internal
#' @import dplyr
#' @import sf
#' @importFrom lubridate ymd_hms with_tz
#' @importFrom stringr str_sub
#' @importFrom readr read_csv cols col_character col_double
#' @importFrom tibble tibble
#' @importFrom stats sd rnorm runif rbinom setNames
#' @importFrom grDevices pdf dev.off
#' @importFrom utils write.csv
"_PACKAGE"

# Column/variable names referenced via dplyr's non-standard evaluation (e.g.
# filter(PLATFORM == ...)) rather than as ordinary R objects - without this,
# R CMD check can't tell them apart from genuinely undefined globals.
utils::globalVariables(c(
  ".data", "PLATFORM", "FILEID", "EVENTNO", "fileid_prefix", "YEAR_ET", "MONTH_ET",
  "BEAUFORT", "LEGTYPE", "LEGSTAGE", "VISIBLTY", "IDREL", "on.off.eff", "season",
  "grid_id", "total_length", "tmpdat_sf_season_survey"
))
