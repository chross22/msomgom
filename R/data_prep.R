#' Load and clean the vessel survey CSV
#'
#' Ready for spatial gridding in `jagsPrep.R::build_detection_arrays()`.
#' Combines what used to be two separate, drifted implementations
#' (`legacy/master.R` and the pre-refactor `data_prep.R`): master.R's GMT ->
#' US/Eastern datetime conversion (more correct near UTC day boundaries than
#' filtering on the raw YEAR/MONTH/DAY columns) plus data_prep.R's
#' BEHAV*-column drop.
#'
#' `survey.platform_code` and `survey.fileid_prefixes` are both required, and
#' an unset one errors rather than being treated as "keep everything":
#' `build_detection_arrays()` assumes a single survey type (one `FILEID` = one
#' single-day survey = one replicate column), and the detection model has no
#' platform covariate, so gridding several platforms together produces a fit
#' that doesn't mean what it looks like. `platform_code` accepts more than one
#' code for a genuinely combined analysis, but that's a deliberate choice.
#'
#' `FILEID` is taken as the survey identifier - one `FILEID` is one survey, one
#' replicate visit. For an export that doesn't use it that way (one where every
#' record carries the same `FILEID`, say), set `survey.split_surveys_by` to
#' `"date"` or `"date_platform"` and the identifier is derived per calendar day
#' (US/Eastern), or per day per `PLATFORM`, keeping the original `FILEID` as a
#' prefix. Without it, such a file is a single survey covering everything:
#' `build_detection_arrays()` errors on its multi-day span, and even if it
#' didn't, one replicate column per season leaves the occupancy model nothing
#' to estimate detection from.
#'
#' @param config a config list, as returned by `load_config()`
#' @param verbose logical; if `TRUE`, reports how many records survive each
#'   filtering step (platform, `FILEID` prefix, date range), and which of those
#'   filters were skipped as unset - useful for diagnosing a run that ends up
#'   with suspiciously little data. See also [diagnose_pipeline()], which calls
#'   this with `verbose = TRUE` alongside other checks.
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

  ## 1. import data. Every column is read as text rather than with a fixed
  ## col_types spec keyed on exact NARWC names (a real export's column names
  ## commonly differ, and standardize_survey_columns() can't rename what it
  ## hasn't read yet) - and rather than letting readr guess, because guessing
  ## corrupts values this pipeline depends on. A FILEID column whose values
  ## are all "F" guesses as logical and arrives as "FALSE"; one mixing "T" and
  ## "F" survey codes becomes TRUE/FALSE. Text is lossless, and every column
  ## this pipeline actually uses is coerced to its expected type below anyway.
  dat <- read_csv(file = data_file, show_col_types = FALSE,
                  col_types = readr::cols(.default = readr::col_character()))
  dat <- standardize_survey_columns(dat)

  numeric_cols <- c("EVENTNO", "MONTH", "DAY", "YEAR", "TIME", "LATITUDE", "LONGITUDE",
                     "LEGTYPE", "LEGSTAGE", "ALT", "HEADING", "CLOUD", "VISIBLTY",
                     "BEAUFORT", "IDREL", "NUMBER", "CONFIDNC")
  character_cols <- c("FILEID", "WX", "SPECCODE")
  still_missing <- setdiff(c(numeric_cols, character_cols), names(dat))
  if (length(still_missing) > 0) {
    stop("Required column(s) not found, even after case-insensitive/alias matching: ",
         paste(still_missing, collapse = ", "), ". Columns found in the file: ",
         paste(names(dat), collapse = ", "), ". See ?standardize_survey_columns for ",
         "the aliases it recognizes, or rename the column(s) in the source file.")
  }
  # TIME first, and not with as.numeric(): see parse_survey_time()
  dat$TIME <- parse_survey_time(dat$TIME)

  values_before <- vapply(dat[numeric_cols], n_values, integer(1))
  dat <- dat |>
    mutate(across(all_of(numeric_cols), as.numeric)) |>
    mutate(across(all_of(character_cols), as.character))
  # from narwcr: a column that had values going in and is entirely NA coming
  # out was emptied by the coercion, not by the data. Every downstream symptom
  # of that (no records after filtering, no on-effort rows, NA datetimes) points
  # somewhere else, so it has to be said here.
  emptied <- numeric_cols[values_before > 0 &
                            vapply(dat[numeric_cols], n_values, integer(1)) == 0]
  if (length(emptied) > 0) {
    warning("Column(s) ", paste(emptied, collapse = ", "), " had values in the file but ",
            "are entirely NA after being read as numbers - the values aren't in a form ",
            "as.numeric() reads. Check how they're written in the source file.",
            call. = FALSE)
  }

  say(nrow(dat), " records read from ", data_file)

  # drop behavior columns (BEHAV1-BEHAV15); not used by this pipeline
  dat <- dat |>
    dplyr::select(-starts_with("BEHAV", ignore.case = FALSE, vars = NULL))

  # restrict to the configured survey vessel. Both this and the FILEID-prefix
  # filter below are required, not optional: downstream stages assume a single
  # survey type (build_detection_arrays() treats one FILEID as one single-day
  # survey and sizes its arrays by the per-season FILEID count, and the
  # detection model has no platform covariate to absorb the difference between
  # a ship km and an aerial km of effort). An unset field is a config mistake
  # rather than a request to grid everything, so say so instead of proceeding.
  platform_code <- unlist(config$survey$platform_code)
  if (length(platform_code) == 0) {
    stop("survey.platform_code is not set. Set it to the PLATFORM code(s) this ",
         "analysis covers - filtering to one survey platform is required, since ",
         "downstream stages assume a single survey type. See ?generate_config.")
  }
  if (!("PLATFORM" %in% names(dat))) {
    stop("survey.platform_code is set to ", paste(platform_code, collapse = "/"),
         " but the data file has no PLATFORM column. Columns found: ",
         paste(names(dat), collapse = ", "),
         ". See ?standardize_survey_columns for the aliases it recognizes.")
  }
  # Match PLATFORM by value, not by type. Everything is read as text, and a
  # platform can be written more than one way: NARWC's numeric codes are
  # zero-padded ("099" has to match a config that says 99), while an export
  # that names its platforms instead of coding them carries "Vessel"/"Aerial",
  # which must not be coerced to numeric - that would turn every record into
  # NA and drop the lot. So numbers compare as numbers and text compares as
  # case-insensitive text.
  platform_key <- function(x) {
    x_chr <- trimws(as.character(x))
    x_num <- suppressWarnings(as.numeric(x_chr))
    ifelse(is.na(x_num), tolower(x_chr), as.character(x_num))
  }
  dat <- dat |>
    filter(platform_key(PLATFORM) %in% platform_key(platform_code))
  say(nrow(dat), " remain after filtering to PLATFORM in ",
      paste(platform_code, collapse = "/"))

  # keep only the configured survey types (FILEID's first character), e.g. "P"/"p" for POP shipboard surveys
  fileid_prefixes <- unlist(config$survey$fileid_prefixes)
  if (length(fileid_prefixes) == 0) {
    stop("survey.fileid_prefixes is not set. Set it to the FILEID first-letter ",
         "code(s) this analysis covers (e.g. \"P\"/\"p\" for POP shipboard ",
         "surveys) - filtering to one survey type is required. See ?generate_config.")
  }
  dat <- dat |>
    mutate(fileid_prefix = str_sub(FILEID, start = 1, end = 1)) |>
    filter(fileid_prefix %in% fileid_prefixes) |>
    dplyr::select(-fileid_prefix)
  say(nrow(dat), " remain after filtering FILEID to prefix(es) ",
      paste(fileid_prefixes, collapse = "/"))

  # convert the survey's time-of-day (HHMMSS, archived in GMT) + date into a
  # real US/Eastern datetime.
  # this matters because a survey event's local calendar date/month can differ from what's
  # in the raw YEAR/MONTH columns for events recorded near a UTC day boundary.
  # A supplied date column wins over rebuilding the date from YEAR/MONTH/DAY.
  # The parts are on whatever clock the programme recorded them on, while TIME
  # may have come from the GPS track log in UTC (see
  # standardize_survey_columns()); pairing the two puts the date and the time
  # on different clocks, and every record within the offset of midnight gets
  # the wrong date - silently, since the result is still a valid date.
  if ("DATE" %in% names(dat)) {
    dat$date_ymd_gmt <- as.Date(dat$DATE)
  } else {
    dat$date_ymd_gmt <- as.Date(with(dat, paste(YEAR, MONTH, DAY, sep = "-")), "%Y-%m-%d")
  }
  GMT_strings <- padstr0(dat$TIME, 6) # pad the times so they have 6 digits
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

  # Optionally rewrite FILEID into a per-survey identifier, for data that
  # doesn't use FILEID as a survey identifier at all - an export where every
  # record shares one FILEID is one survey as far as everything downstream is
  # concerned, which means a file spanning many days (an error in
  # build_detection_arrays()) and, worse, a single replicate column per season,
  # leaving the occupancy model no repeat visits to separate detection from
  # occupancy. This is a modeling choice, not cleanup - whatever it splits on
  # becomes the replicate unit, and jday/effort/BEAUFORT get summarized per
  # unit - so it's off unless the config asks for it, and the derived ID keeps
  # the original FILEID as its prefix (the FILEID-prefix filter above has
  # already run against the original value, so prefixes still mean what they
  # did in the source file).
  split_surveys_by <- config$survey$split_surveys_by
  if (is.null(split_surveys_by)) split_surveys_by <- "none"
  if (!(split_surveys_by %in% c("none", "date", "date_platform"))) {
    stop("survey.split_surveys_by must be \"none\", \"date\", or \"date_platform\", got: \"",
         split_surveys_by, "\"")
  }
  if (split_surveys_by != "none" && nrow(dat) > 0) {
    n_before <- length(unique(dat$FILEID))
    dat$FILEID <- if (split_surveys_by == "date_platform") {
      paste(dat$FILEID, format(dat$date_ymd, "%Y%m%d"), dat$PLATFORM, sep = "_")
    } else {
      paste(dat$FILEID, format(dat$date_ymd, "%Y%m%d"), sep = "_")
    }
    say(n_before, " source FILEID(s) split into ", length(unique(dat$FILEID)),
        " survey(s) by ", split_surveys_by)
  }

  if (nrow(dat) == 0) {
    warning("No records remain after the platform/FILEID/date filters. Check ",
            "survey.platform_code, survey.fileid_prefixes, and dates.* against ",
            "what's actually in the data file - run prep_survey_data(config, verbose = TRUE) ",
            "to see which filter dropped everything, or diagnose_pipeline(config).",
            call. = FALSE)
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
  say(describe_legtypes(dat$LEGTYPE, on_effort_legtypes))

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
            "filter - the model has no detection opportunities to fit on.\n",
            describe_legtypes(dat$LEGTYPE, on_effort_legtypes),
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

#' How many real values a column carries
#'
#' Blanks count as missing: a CSV's empty cell arrives as either `NA` or `""`
#' depending on how it was read.
#'
#' @param x a vector
#' @return integer count of values that are neither `NA` nor blank
#' @keywords internal
n_values <- function(x) sum(!is.na(x) & trimws(as.character(x)) != "")

#' Read a survey TIME column, whatever clock format it's written in
#'
#' `TIME` is `hhmmss` in 24-hour form (NARWC handbook 8.A.37), and that's what
#' this pipeline stores. Real files also write `"12:34:56"`, `"12:34"`, and
#' whole timestamps like `"2024-04-01T12:34:56Z"` - and `as.numeric()` turns
#' every one of those into `NA` without a word, so a file with a perfectly good
#' clock arrives with no times at all. Preferring `TrkTime_UTC` (see
#' [standardize_survey_columns()]) makes that more likely, since a GPS track
#' log is exactly where a clock-formatted time comes from, but it was always
#' possible for `Time_UTC`.
#'
#' The first clock-looking piece of the string is taken, so a bare time and a
#' full timestamp both work (an ISO date separates with `-`, so it can't be
#' mistaken for one). Seconds are optional and default to zero. A column that's
#' already numeric is returned untouched.
#'
#' @param x the raw `TIME` column
#' @return numeric `hhmmss`
#' @keywords internal
parse_survey_time <- function(x) {
  if (is.numeric(x)) return(x)

  s <- trimws(as.character(x))
  s[!nzchar(s)] <- NA_character_
  out <- suppressWarnings(as.numeric(s))

  clock <- is.na(out) & !is.na(s) & grepl("[0-9]{1,2}:[0-9]{2}", s)
  if (any(clock)) {
    hit <- regmatches(s[clock], regexpr("[0-9]{1,2}:[0-9]{2}(:[0-9]{2})?", s[clock]))
    parts <- strsplit(hit, ":", fixed = TRUE)
    out[clock] <- vapply(parts, function(p) {
      p <- suppressWarnings(as.numeric(p))
      p[1] * 10000 + p[2] * 100 + if (length(p) > 2 && !is.na(p[3])) p[3] else 0
    }, numeric(1))
  }
  out
}

#' Say what the LEGTYPE codes in the data mean, and what was asked for
#'
#' `survey.on_effort_legtypes` is a set of NARWC codes, and getting it wrong
#' empties the data with nothing on screen to say which codes were there
#' instead. The vocabulary is narwcr's (Handbook 8.A.21), so this reports the
#' codes actually present with their meanings rather than making the reader
#' look them up - the default `c(5, 6)` is POP *ship*, and a line-transect
#' aerial survey uses 0-4, of which only 2 is the survey line.
#'
#' @param legtype the data's `LEGTYPE` column
#' @param wanted the configured on-effort codes
#' @return a single string, ready to pass to `say()` or a warning
#' @seealso [prep_survey_data()], which calls this; `narwcr::narwc_codes()`,
#'   which owns the code book
#' @keywords internal
describe_legtypes <- function(legtype, wanted) {
  present <- sort(unique(stats::na.omit(legtype)))
  if (!length(present)) return("LEGTYPE is empty, so no record can be on-effort.")

  book <- tryCatch(narwcr::narwc_codes("LEGTYPE"), error = function(e) NULL)
  label <- function(code) {
    # `book` is a named character vector, and x[["absent"]] on one is an
    # error rather than NULL - a code the handbook does not list would
    # otherwise take down the very message meant to explain it.
    key <- as.character(code)
    meaning <- if (!is.null(book) && key %in% names(book)) book[[key]] else NULL
    counts <- sum(legtype == code, na.rm = TRUE)
    paste0("    ", code, if (code %in% wanted) " *" else "  ", "  ",
           format(counts, big.mark = ","), "  ",
           if (is.null(meaning)) "(not a NARWC LEGTYPE code)" else meaning)
  }

  matched <- sum(legtype %in% wanted, na.rm = TRUE)
  paste0(
    "  LEGTYPE codes in the data (* = configured as on-effort; ",
    format(matched, big.mark = ","), " record(s) matched):\n",
    paste(vapply(present, label, character(1)), collapse = "\n"),
    if (!matched) paste0(
      "\n  Nothing matched survey.on_effort_legtypes = ",
      paste(wanted, collapse = ", "),
      ". Codes 0-4 are line-transect aerial and only 2 is the survey line;",
      "\n  5/6 are POP ship, 7/9 POP aerial. See narwcr::narwc_codes(\"LEGTYPE\")."
    ) else ""
  )
}
