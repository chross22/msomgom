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
#' @param verbose logical; if `TRUE`, reports how many records survive each
#'   filtering step (platform, `FILEID` prefix, date range) - useful for
#'   diagnosing a run that ends up with suspiciously little data. See also
#'   [diagnose_pipeline()], which calls this with `verbose = TRUE` alongside
#'   other checks.
#' @return list with:
#'   \item{dat}{the full cleaned dataset}
#'   \item{tmpdat}{a reduced dataset with just the columns needed for gridding}
#'   \item{season_info}{list(season = <season lookup table from `makeSeasons()`>, num_ssn = <int>)}
#' @seealso [load_config()], which produces `config`; [build_detection_arrays()],
#'   the next pipeline stage, which takes this function's `tmpdat`/`season_info`;
#'   [diagnose_pipeline()], for a friendlier pre-flight check than reading this
#'   function's warnings after the fact
#' @family pipeline stages
#' @examples
#' \dontrun{
#' config <- load_config("configs/bof_riwh.yaml")
#' prep <- prep_survey_data(config)
#' prep$season_info$num_ssn
#'
#' # see how many records each filter step drops
#' prep <- prep_survey_data(config, verbose = TRUE)
#' }
#' @export
prep_survey_data <- function(config, verbose = FALSE) {
  say <- function(...) if (verbose) message(...)
  data_file <- config$paths$data_file
  if (!file.exists(data_file)) {
    have_gdrive <- !is.null(config$paths$google_drive_filename)
    have_onedrive <- !is.null(config$paths$onedrive_filename)
    if (!have_gdrive && !have_onedrive) {
      stop("Data file not found and neither google_drive_filename nor onedrive_filename ",
           "is configured: ", data_file)
    }
    data_dir <- dirname(data_file)
    if (!dir.exists(data_dir)) dir.create(data_dir, recursive = TRUE)

    if (have_gdrive) {
      if (!requireNamespace("googledrive", quietly = TRUE)) {
        stop("The 'googledrive' package is required to download data from paths.google_drive_filename. ",
             "Install it with install.packages('googledrive').")
      }
      googledrive::drive_download(config$paths$google_drive_filename, path = data_file)
    } else {
      if (!requireNamespace("Microsoft365R", quietly = TRUE)) {
        stop("The 'Microsoft365R' package is required to download data from paths.onedrive_filename. ",
             "Install it with install.packages('Microsoft365R').")
      }
      onedrive_type <- config$paths$onedrive_type
      if (is.null(onedrive_type)) onedrive_type <- "personal"
      if (!(onedrive_type %in% c("personal", "business"))) {
        stop("paths.onedrive_type must be \"personal\" or \"business\", got: \"", onedrive_type, "\"")
      }
      od <- if (onedrive_type == "business") {
        Microsoft365R::get_business_onedrive()
      } else {
        Microsoft365R::get_personal_onedrive()
      }
      od$download_file(src = config$paths$onedrive_filename, dest = data_file, overwrite = TRUE)
    }
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

  say(nrow(dat), " records read from ", data_file)

  # drop behavior columns (BEHAV1-BEHAV15); not used by this pipeline
  dat <- dat |>
    dplyr::select(-starts_with("BEHAV", ignore.case = FALSE, vars = NULL))

  # restrict to the configured survey vessel
  dat <- dat |>
    filter(PLATFORM == config$survey$platform_code)
  say(nrow(dat), " remain after filtering to PLATFORM == ", config$survey$platform_code)

  # keep only the configured survey types (FILEID's first character), e.g. "P"/"p" for POP shipboard surveys
  dat <- dat |>
    mutate(fileid_prefix = str_sub(FILEID, start = 1, end = 1)) |>
    filter(fileid_prefix %in% unlist(config$survey$fileid_prefixes)) |>
    dplyr::select(-fileid_prefix)
  say(nrow(dat), " remain after filtering FILEID to prefix(es) ",
      paste(unlist(config$survey$fileid_prefixes), collapse = "/"))

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
  say(nrow(dat), " remain after filtering to years ", config$dates$beg_year, "-", config$dates$end_year)
  dat <- dat |>
    filter(MONTH_ET == config$dates$beg_month | MONTH_ET == config$dates$end_month)
  say(nrow(dat), " remain after filtering to months ", config$dates$beg_month, "/", config$dates$end_month)

  if (nrow(dat) == 0) {
    warning("No records remain after the platform/FILEID/date filters. Check ",
            "survey.platform_code, survey.fileid_prefixes, and dates.* against ",
            "what's actually in the data file - run prep_survey_data(config, verbose = TRUE) ",
            "to see which filter dropped everything, or diagnose_pipeline(config).", call. = FALSE)
  }

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
  n_unassigned <- sum(is.na(dat$season))
  if (n_unassigned > 0) {
    # A record can pass the platform/FILEID/date filters above (which only
    # check YEAR_ET/MONTH_ET) and still fall on a calendar day none of the
    # configured `seasons` day-ranges cover - e.g. dates.beg_month/end_month
    # keeps the whole month, but a narrower season window (say the 5th-20th)
    # leaves days outside it with season = NA. Those records are silently
    # dropped from every downstream array (build_detection_arrays() filters
    # by `season == i` per iteration, so an NA season never gets picked up
    # in any of them) rather than erring loudly, so this is worth saying now.
    warning(n_unassigned, " record(s) fell within the configured year/month range but ",
            "outside every configured season's day-range, so they were assigned no season ",
            "and will be silently dropped from every detection array. Check that `seasons` ",
            "in the config covers every day in dates.beg_month/end_month, not just the month.",
            call. = FALSE)
  }
  say(nrow(dat) - n_unassigned, " of ", nrow(dat), " records assigned to a season")

  # flag on/off-effort records. LEGTYPE codes on effort are config-driven
  # (survey.on_effort_legtypes) rather than hardcoded, since different survey
  # platforms use different codes - e.g. NARWC 8.A.21's 5/6 (the default
  # below) are POP ship underway / not underway; a POP aerial survey's
  # on-effort legs are 7/9 instead. LEGSTAGE (begin/continue/end watch) is
  # recorded independently of LEGTYPE for POP surveys of either platform
  # (8.A.20), so it isn't platform-specific and stays fixed.
  on_effort_legtypes <- unlist(config$survey$on_effort_legtypes)
  if (is.null(on_effort_legtypes)) on_effort_legtypes <- c(5, 6)

  dat <- dat |>
    mutate(on.off.eff = if_else((BEAUFORT <= 6 & # normally require sea state 0-3, but sea state will be covariate on detection in this model
                                   (LEGTYPE %in% on_effort_legtypes & (LEGSTAGE == 1 | LEGSTAGE == 2 | LEGSTAGE == 5)) & # start, continue, end watch
                                   (VISIBLTY >= 2 | VISIBLTY == -1) & # VISIBLTY >=2 or -1 indicates visibility of at least 2 nautical miles
                                   (IDREL == 3 | is.na(IDREL)) # if there is a sighting, IDREL must = 3. If no sighting, IDREL should be NA
    ),
    1, 0)) |>
    # replace all NA with 0 because those are off-effort
    mutate(on.off.eff = ifelse(is.na(on.off.eff), 0, on.off.eff))

  n_on_effort <- sum(dat$on.off.eff == 1)
  say(n_on_effort, " of ", nrow(dat), " records are on-effort")
  if (nrow(dat) > 0 && n_on_effort == 0) {
    warning("No on-effort records after the LEGTYPE/LEGSTAGE/VISIBLTY/IDREL/BEAUFORT ",
            "filter - the model has no detection opportunities to fit on. Check ",
            "survey.on_effort_legtypes against what's actually in the data (see ",
            "?generate_config), especially if this is a non-vessel survey platform.",
            call. = FALSE)
  }

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
