#' Load and clean the vessel survey CSV
#'
#' Ready for spatial gridding in `jagsPrep.R::build_detection_arrays()`.
#' Combines what used to be two separate, drifted implementations
#' (`legacy/master.R` and the pre-refactor `data_prep.R`): master.R's GMT ->
#' US/Eastern datetime conversion (more correct near UTC day boundaries than
#' filtering on the raw YEAR/MONTH/DAY columns) plus data_prep.R's
#' BEHAV*-column drop.
#'
#' @param config a config list, as returned by `load_config()`
#' @return list with:
#'   \item{dat}{the full cleaned dataset}
#'   \item{tmpdat}{a reduced dataset with just the columns needed for gridding}
#'   \item{season_info}{list(season = <season lookup table from `makeSeasons()`>, num_ssn = <int>)}
#' @seealso [load_config()], which produces `config`; [build_detection_arrays()],
#'   the next pipeline stage, which takes this function's `tmpdat`/`season_info`
#' @family pipeline stages
#' @examples
#' \dontrun{
#' config <- load_config("configs/bof_riwh.yaml")
#' prep <- prep_survey_data(config)
#' prep$season_info$num_ssn
#' }
prep_survey_data <- function(config) {
  library(dplyr)
  library(readr)
  library(stringr)
  library(lubridate)

  data_file <- config$paths$data_file
  if (!file.exists(data_file)) {
    if (is.null(config$paths$google_drive_filename)) {
      stop("Data file not found and no google_drive_filename configured: ", data_file)
    }
    if (!requireNamespace("googledrive", quietly = TRUE)) {
      install.packages("googledrive")
    }
    library(googledrive)
    data_dir <- dirname(data_file)
    if (!dir.exists(data_dir)) dir.create(data_dir, recursive = TRUE)
    drive_download(config$paths$google_drive_filename, path = data_file)
  }

  ## 1. import data
  dat <- read_csv(file = data_file,
                  col_types = cols(FILEID = col_character(),
                                   EVENTNO = col_double(),
                                   MONTH = col_double(),
                                   DAY = col_double(),
                                   YEAR = col_double(),
                                   GMT = col_double(),
                                   LATITUDE = col_double(),
                                   LONGITUDE = col_double(),
                                   LEGTYPE = col_double(),
                                   LEGSTAGE = col_double(),
                                   ALT = col_double(),
                                   HEADING = col_double(),
                                   WX = col_character(),
                                   CLOUD = col_double(),
                                   VISIBLTY = col_double(),
                                   BEAUFORT = col_double(),
                                   SPECCODE = col_character(),
                                   IDREL = col_double(),
                                   NUMBER = col_double(),
                                   CONFIDNC = col_double())
  )

  # drop behavior columns (BEHAV1-BEHAV15); not used by this pipeline
  dat <- dat |>
    dplyr::select(-starts_with("BEHAV", ignore.case = FALSE, vars = NULL))

  # restrict to the configured survey vessel
  dat <- dat |>
    filter(PLATFORM == config$survey$platform_code)

  # keep only the configured survey types (FILEID's first character), e.g. "P"/"p" for POP shipboard surveys
  dat <- dat |>
    mutate(fileid_prefix = str_sub(FILEID, start = 1, end = 1)) |>
    filter(fileid_prefix %in% unlist(config$survey$fileid_prefixes)) |>
    dplyr::select(-fileid_prefix)

  # convert the survey's GMT time-of-day (HHMMSS) + date into a real US/Eastern datetime.
  # this matters because a survey event's local calendar date/month can differ from what's
  # in the raw YEAR/MONTH columns for events recorded near a UTC day boundary.
  dat$date_ymd_gmt <- as.Date(with(dat, paste(YEAR, MONTH, DAY, sep = "-")), "%Y-%m-%d")
  GMT_strings <- padstr0(dat$GMT, 6) # pad GMT times so they have 6 digits
  # correct instances where "200000" was stored as "02e+05"
  GMT_strings[which(GMT_strings == "02e+05")] <- "200000"
  GMT_strings <- paste(dat$date_ymd_gmt, GMT_strings) # append ymd to hms
  dat$datetime_GMT <- ymd_hms(GMT_strings, tz = "GMT")
  dat$datetime_ET <- with_tz(dat$datetime_GMT, "US/Eastern")

  # calendar date/day-of-year/year/month based on US/Eastern local time
  dat$date_ymd <- as.Date(dat$datetime_ET)
  dat$date_jday <- format(dat$datetime_ET, "%j")
  dat$YEAR_ET <- as.numeric(format(dat$datetime_ET, "%Y"))
  dat$MONTH_ET <- as.numeric(format(dat$datetime_ET, "%m"))

  # keep only desired years and months (based on US/Eastern local time)
  dat <- dat |>
    filter(YEAR_ET >= config$dates$beg_year & YEAR_ET <= config$dates$end_year)
  dat <- dat |>
    filter(MONTH_ET == config$dates$beg_month | MONTH_ET == config$dates$end_month)

  # create seasons matrix, and assign each record its season (based on US/Eastern local time)
  season <- makeSeasons(config$dates$beg_year, config$dates$end_year, config$ssn_beg, config$ssn_end)
  ssn_beg_date <- as.Date(paste(season[, 1], season[, 2], season[, 3], sep = "-"), "%Y-%m-%d")
  ssn_end_date <- as.Date(paste(season[, 1], season[, 4], season[, 5], sep = "-"), "%Y-%m-%d")
  ssn_no <- season$SSN_NO
  num_ssn <- max(ssn_no)
  ssn_no_grpd <- season$SSN_GRPD_NO
  dat$season <- NA
  dat$season_grpd <- NA
  for (i in seq_along(ssn_beg_date)) {
    I <- which(dat$datetime_ET >= ssn_beg_date[i] & dat$datetime_ET <= ssn_end_date[i])
    dat$season[I] <- ssn_no[i]
    dat$season_grpd[I] <- ssn_no_grpd[i]
  }

  # flag on/off-effort records
  dat <- dat |>
    mutate(on.off.eff = if_else((BEAUFORT <= 6 & # normally require sea state 0-3, but sea state will be covariate on detection in this model
                                   (
                                     (LEGTYPE == 5 & (LEGSTAGE == 1 | LEGSTAGE == 2 | LEGSTAGE == 5)) | # start, continue, end watch while ship not underway
                                       (LEGTYPE == 6 & (LEGSTAGE == 1 | LEGSTAGE == 2 | LEGSTAGE == 5)) # legtype = 6 indicates ship not underway (listening station)
                                   ) &
                                   (VISIBLTY >= 2 | VISIBLTY == -1) & # VISIBLTY >=2 or -1 indicates visibility of at least 2 nautical miles
                                   (IDREL == 3 | is.na(IDREL)) # if there is a sighting, IDREL must = 3. If no sighting, IDREL should be NA
    ),
    1, 0)) |>
    # replace all NA with 0 because those are off-effort
    mutate(on.off.eff = ifelse(is.na(on.off.eff), 0, on.off.eff))

  ## reduce dataset to the columns needed for gridding
  keep.cols <- c("FILEID",
                 "EVENTNO",
                 "YEAR", "MONTH", "DAY",
                 "BEAUFORT",
                 "LEGTYPE", "LEGSTAGE",
                 "LATITUDE", "LONGITUDE",
                 "SPECCODE", "IDREL", "NUMBER",
                 "date_ymd", "date_jday",
                 "on.off.eff",
                 "season", "season_grpd")
  tmpdat <- dat |>
    dplyr::select(all_of(keep.cols))

  list(
    dat = dat,
    tmpdat = tmpdat,
    season_info = list(season = season, num_ssn = num_ssn)
  )
}
