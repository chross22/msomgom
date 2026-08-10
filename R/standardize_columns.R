# Canonical NARWC column name -> accepted alias patterns, matched
# case-insensitively and ignoring non-alphanumeric characters (so "Event No.",
# "event_no", and "EventNo" all match "EVENTNO"). Real survey exports vary in
# exactly this way, and requiring an exact match meant every real dataset
# needed manual renaming before this pipeline would even read it.
# Kept in step with distsamp::narwc_schema()$aliases, which is the same
# vocabulary for the same archive. The two are NOT linked automatically -
# distsamp exports standardize_narwc_columns(), but delegating to it would
# rename this package's GMT column to TIME, which the rest of the pipeline
# reads (data_prep.R, padstr0.R). So the table is synced by hand, and the
# entries below marked "from distsamp" came across on 2026-08-10.
survey_column_aliases <- list(
  FILEID = c("fileid", "file", "filename"),
  EVENTNO = c("eventno", "event", "eventnum", "eventnumber", "evno", "eventid"),
  MONTH = c("month", "mon", "mo"),
  DAY = c("day", "dy"),
  YEAR = c("year", "yr"),
  # from distsamp: files that record the zone in the column name. UTC and GMT
  # are the same clock; a local column is accepted but ranks last, so a file
  # carrying both lands on UTC.
  GMT = c("gmt", "time", "timegmt", "gmttime", "utctime", "utc",
          "timeutc", "time_utc", "timeloc", "time_loc", "time_local"),
  # from distsamp: LAT_DD/LONG_DD are the handbook's own canonical spelling
  # (8.A.18, 8.A.22), so an unprocessed NARWC extract uses them.
  LATITUDE = c("latitude", "lat", "latdd", "lat_dd", "latitude_dd"),
  LONGITUDE = c("longitude", "lon", "long", "lng",
                "longdd", "long_dd", "lon_dd", "longitude_dd"),
  # from distsamp: LEGTYPE_BK is Kenney's leg type, which some processed files
  # carry alongside a different LEGTYPE.
  LEGTYPE = c("legtype", "leg", "legtype_bk"),
  LEGSTAGE = c("legstage", "stage"),
  ALT = c("alt", "altitude", "altft", "altitudeft", "height"),
  HEADING = c("heading", "hdg", "course"),
  WX = c("wx", "weather"),
  CLOUD = c("cloud", "cloudcover", "clouds"),
  # from distsamp: "visiblity" is a misspelling common enough in the archive
  # to be worth matching.
  VISIBLTY = c("visiblty", "visibility", "visiblity", "vis", "visnm"),
  BEAUFORT = c("beaufort", "bft", "seastate", "beaufortscale"),
  SPECCODE = c("speccode", "species", "specode", "sppcode", "spp", "spcode"),
  IDREL = c("idrel", "idreliability", "reliability"),
  NUMBER = c("number", "num", "count", "numanimals", "groupsize"),
  CONFIDNC = c("confidnc", "confidence", "conf")
)

#' Standardize survey CSV column names to what this pipeline expects
#'
#' Real survey exports rarely use the exact NARWC column names
#' (`prep_survey_data()`'s import step expects `EVENTNO`, `LATITUDE`, etc.
#' literally) - a column might be `Event`, `event_no`, or `Event No.`
#' instead. This renames columns to their canonical NARWC name whenever an
#' exact case-insensitive match, or one of a small list of common aliases
#' (also matched case-insensitively, ignoring punctuation/spaces/underscores)
#' is found, so a real-world export doesn't need manual renaming first.
#'
#' `ALT` (altitude - only meaningful for aerial surveys) gets one more
#' fallback beyond alias matching: if still missing afterward, every record
#' is given a constant default (see `alt_default`) with a warning, rather
#' than erroring, since `ALT` isn't otherwise used by this pipeline's
#' filtering/gridding logic.
#'
#' Every other expected column (see [prep_survey_data()]) is required - if
#' one still can't be matched after this, `prep_survey_data()` errors
#' listing exactly which, and what columns were actually found, rather than
#' failing later with a confusing "column not found" error from deep inside
#' `dplyr`.
#'
#' @param dat a data.frame/tibble, as read from the raw survey CSV
#' @param alt_default numeric altitude to fill in for every record when the
#'   `ALT` column can't be found at all (default `750`, a typical NARWC
#'   aerial survey altitude in feet - only used as a last resort, and only
#'   matters for aerial-survey analyses that actually use `ALT`, which this
#'   pipeline's own filtering does not)
#' @return `dat` with columns renamed to their canonical NARWC names where a
#'   match was found, and `ALT` added if it was missing entirely
#' @seealso [prep_survey_data()], which calls this on the raw CSV before
#'   anything else
#' @family pipeline stages
#' @examples
#' dat <- data.frame(Event = 1, Lat = 2, Long = 3, check.names = FALSE)
#' # renames Event/Lat/Long, and warns + fills in ALT (missing entirely here):
#' names(standardize_survey_columns(dat)) # "EVENTNO" "LATITUDE" "LONGITUDE" "ALT"
#' @export
standardize_survey_columns <- function(dat, alt_default = 750) {
  norm <- function(x) gsub("[^a-z0-9]", "", tolower(x))
  current_names <- names(dat)
  current_norm <- norm(current_names)

  for (canonical in names(survey_column_aliases)) {
    if (canonical %in% current_names) next # exact match already present

    candidates_norm <- norm(c(canonical, survey_column_aliases[[canonical]]))
    hits <- which(current_norm %in% candidates_norm)
    if (length(hits) == 0) next
    if (length(hits) > 1) {
      warning("Multiple columns look like '", canonical, "': ",
              paste(current_names[hits], collapse = ", "),
              " - using '", current_names[hits[1]], "'. Rename the others if this is wrong.",
              call. = FALSE)
    }
    names(dat)[hits[1]] <- canonical
    current_names <- names(dat)
    current_norm <- norm(current_names)
  }

  if (!("ALT" %in% names(dat))) {
    warning("ALT column not found (even after alias matching); defaulting to ", alt_default,
            " for every record. This pipeline's own filtering doesn't use ALT, so this only ",
            "matters if you're using it for something else - pass alt_default to override.",
            call. = FALSE)
    dat$ALT <- alt_default
  }

  dat
}
