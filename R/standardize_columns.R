# Canonical NARWC column name -> accepted alias patterns, matched
# case-insensitively and ignoring non-alphanumeric characters (so "Event No.",
# "event_no", and "EventNo" all match "EVENTNO"). Real survey exports vary in
# exactly this way, and requiring an exact match meant every real dataset
# needed manual renaming before this pipeline would even read it.
# Canonical NARWC column name -> accepted alias patterns.
#
# narwcr (chross22/narwcr, where distsamp's NARWC data-preparation layer was
# extracted to) maintains the same vocabulary for the same archive, and the two
# are kept in step by hand rather than by a dependency: these are separate
# packages with different missions, and msomgom should not need a segmentation
# or data-prep package to read a CSV. Entries marked "from distsamp" came
# across on 2026-08-10; roughly thirty went the other way at the same time.
# The `Trk*` family, the alias priorities, the preferred-source rule and the
# feet-to-metres conversion below came across from narwcr on 2026-08-11 -
# `narwc_column_mapping()`, `narwc_alias_priority`, `narwc_preferred_source`
# and `narwc_unit_factors()` are the sources to diff against next time.
#
# The column names match: both call the time column TIME, both call the
# position LATITUDE/LONGITUDE. That is what makes a hand sync cheap and lets
# data move between the two without translation.
survey_column_aliases <- list(
  FILEID = c("fileid", "file", "filename"),
  # NOT "aerial"/"vessel"-as-a-value: those are PLATFORM *values* in exports
  # that name their platforms instead of using NARWC's numeric codes (see
  # prep_survey_data(), which matches either). "vessel" is here as a column
  # name, since a file that records one boat per row commonly calls the column
  # that.
  PLATFORM = c("platform", "platformcode", "platformid", "platformno",
               "platformtype", "surveyplatform", "vessel"),
  EVENTNO = c("eventno", "event", "eventnum", "eventnumber", "evno", "eventid"),
  MONTH = c("month", "mon", "mo"),
  DAY = c("day", "dy"),
  YEAR = c("year", "yr"),
  # from distsamp: files that record the zone in the column name. UTC and GMT
  # are the same clock; a local column is accepted but ranks last, so a file
  # carrying both lands on UTC.
  # from narwcr: the Trk* family is the platform's own GPS track log.
  TIME = c("time", "gmt", "timegmt", "gmttime", "utctime", "utc",
           "timeutc", "time_utc", "trktime_utc",
           "timeloc", "time_loc", "time_local", "trktime_local"),
  # from distsamp: LAT_DD/LONG_DD are the handbook's own canonical spelling
  # (8.A.18, 8.A.22), so an unprocessed NARWC extract uses them.
  LATITUDE = c("latitude", "lat", "latdd", "lat_dd", "latitude_dd",
               "trklatitude", "trklat"),
  LONGITUDE = c("longitude", "lon", "long", "lng",
                "longdd", "long_dd", "lon_dd", "longitude_dd",
                "trklongitude", "trklon", "trklong"),
  # from distsamp: LEGTYPE_BK is Kenney's leg type, which some processed files
  # carry alongside a different LEGTYPE.
  LEGTYPE = c("legtype", "leg", "legtype_bk"),
  LEGSTAGE = c("legstage", "stage"),
  # NOT "height" - too generic, and real survey files commonly carry
  # unrelated height fields (Swell_Height, Wave_Height, Cloud_Height) that
  # would false-positive-match ALT via the substring fallback below.
  ALT = c("alt", "altitude", "altft", "altitudeft", "aircraftalt",
          "trkaltitude", "trkaltitude_m", "trkaltitude_ft"),
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

# from narwcr (`narwc_alias_priority`): when several columns claim the same
# canonical name and more than one of them has data, this is the order they're
# preferred in. Anything not named here ranks after everything that is.
survey_alias_priority <- list(
  # GMT and UTC are the same clock, so they rank together, ahead of local. The
  # GPS clock wins, but not across zones: a UTC column is still taken before a
  # local one, because landing a dataset on two clocks is a worse failure than
  # taking the observer's UTC time over the receiver's.
  TIME = c("trktime_utc", "time_utc", "timeutc", "gmt", "time_gmt", "gmt_time",
           "trktime_local", "time_loc", "timeloc", "time_local"),
  # A file carrying both TrkAltitude_m and TrkAltitude_ft is not ambiguous:
  # take the metres one and skip a conversion that can only lose precision.
  ALT = c("trkaltitude_m", "trkaltitude", "trkaltitude_ft", "altitude",
          "aircraftalt", "altft", "altitudeft")
)

# from narwcr (`narwc_preferred_source`): sources that outrank a canonical
# column *already present under its own name*. The one exception to "the real
# one always wins", and it exists because the exception is the honest reading
# of the data: a Trk* column is the GPS track log, and a plain LATITUDE
# alongside it is the position recorded for the platform, which on a file
# covering both a vessel and an aircraft is not the same place. Taking the
# plain column would silently survey the wrong track. The displaced column is
# kept as <CANONICAL>_ORIGINAL, never dropped, and the swap warns.
survey_preferred_source <- list(
  LATITUDE = c("trklatitude", "trklat"),
  LONGITUDE = c("trklongitude", "trklon", "trklong"),
  ALT = c("trkaltitude_m", "trkaltitude", "trkaltitude_ft"),
  # Only the UTC track clock displaces a plain TIME. TrkTime_Local would move
  # the whole dataset onto another zone to gain the same seconds, which isn't a
  # trade to make without being asked.
  TIME = "trktime_utc"
)

# from narwcr (`narwc_unit_factors()`): multipliers onto the canonical unit,
# keyed by canonical target and then by the column it came from. ALT is metres
# (handbook 8.A.1), so a column whose name declares feet has to be converted -
# read as metres it overstates an altitude by 3.28.
survey_unit_factors <- list(
  ALT = c(trkaltitude_ft = 0.3048, altft = 0.3048, altitudeft = 0.3048)
)

#' Standardize survey CSV column names to what this pipeline expects
#'
#' Real survey exports rarely use the exact NARWC column names
#' (`prep_survey_data()`'s import step expects `EVENTNO`, `LATITUDE`, etc.
#' literally) - a column might be `Event`, `event_no`, or `Event No.`
#' instead. This renames columns to their canonical NARWC name in three
#' passes, most specific first:
#' \enumerate{
#'   \item An exact case-insensitive match against the canonical name itself.
#'   \item A match against a curated list of common aliases per column
#'     (`survey_column_aliases`), e.g. `"seastate"` for `BEAUFORT`.
#'   \item A generic fallback: any column whose name contains the canonical
#'     name (or a known alias) as a substring, or is contained by one - e.g.
#'     `"Survey_Alt_ft"` for `ALT`, `"Event_ID"` for `EVENTNO`. This is what
#'     catches a variant nobody thought to enumerate in the alias list, at
#'     the cost of a higher chance of matching an unrelated column that
#'     happens to share the substring - every match found this way still
#'     goes through the same ambiguity warning as the other two passes,
#'     rather than being applied silently.
#' }
#' All three passes ignore case, spaces, underscores, and punctuation, so
#' `"Event No."`, `"event_no"`, and `"EventNo"` are equivalent.
#'
#' If `YEAR`/`MONTH`/`DAY`/`TIME` are still missing after that (individually,
#' any subset), they're derived from a single combined date(time) column if
#' one can be found (matched the same three-pass way, e.g. `"Date"`,
#' `"Survey_Date"`, or a column merely containing `"date"`) - a file that
#' records `"2024-08-15"` or `"2024-08-15 14:30:00"` in one column instead of
#' separate `YEAR`/`MONTH`/`DAY`/`TIME` columns doesn't need them split out by
#' hand first. A value that can't be parsed as a date becomes `NA`, with a
#' warning naming how many.
#'
#' `ALT` (altitude - only meaningful for aerial surveys) gets one more
#' fallback beyond all of the above: if still missing afterward, every
#' record is given a constant default (see `alt_default`) with a warning,
#' rather than erroring, since `ALT` isn't otherwise used by this pipeline's
#' filtering/gridding logic. `ALT` is metres (NARWC handbook 8.A.1), so a
#' column whose name declares feet (`Alt_ft`, `TrkAltitude_ft`) is multiplied
#' by 0.3048 on the way in, with a warning saying so.
#'
#' Two rules decide between columns that claim the same canonical name. A
#' column that carries data beats one that doesn't; among those that do, a
#' documented priority applies - `TrkTime_UTC` over a plain UTC spelling, UTC
#' over local, `TrkAltitude_m` over `TrkAltitude_ft`. Separately, a `Trk*`
#' column (the platform's own GPS track log) displaces a `LATITUDE`,
#' `LONGITUDE`, `ALT`, or `TIME` column already present under its own name:
#' on a file covering both a vessel and an aircraft, the position recorded for
#' the platform and the track log are not the same place, and taking the plain
#' column would silently survey the wrong track. The displaced column is kept
#' as `<CANONICAL>_ORIGINAL` rather than dropped, the swap warns, and
#' `prefer_track = FALSE` turns it off. `TrkTime_Local` deliberately displaces
#' nothing: it would move the whole dataset onto another zone to gain the
#' receiver's seconds.
#'
#' Every other expected column (see [prep_survey_data()]) is required - if
#' one still can't be matched after all of this, `prep_survey_data()` errors
#' listing exactly which, and what columns were actually found, rather than
#' failing later with a confusing "column not found" error from deep inside
#' `dplyr`.
#'
#' @param dat a data.frame/tibble, as read from the raw survey CSV
#' @param alt_default numeric altitude to fill in for every record when the
#'   `ALT` column can't be found at all, **in metres** (handbook 8.A.1) - the
#'   default `229` is a typical NARWC aerial survey altitude of 750 ft. Only
#'   used as a last resort, and only matters for aerial-survey analyses that
#'   actually use `ALT`, which this pipeline's own filtering does not.
#' @param prefer_track whether a `Trk*` GPS track column displaces a
#'   `LATITUDE`/`LONGITUDE`/`ALT`/`TIME` column already present under its own
#'   name (default `TRUE`; see above). `FALSE` keeps the column that's already
#'   there, and the track log is left under its own name.
#' @return `dat` with columns renamed to their canonical NARWC names where a
#'   match was found, `YEAR`/`MONTH`/`DAY`/`TIME` derived from a date(time)
#'   column where applicable, and `ALT` added if it was missing entirely
#' @seealso [prep_survey_data()], which calls this on the raw CSV before
#'   anything else
#' @family pipeline stages
#' @examples
#' dat <- data.frame(Event = 1, Lat = 2, Long = 3, check.names = FALSE)
#' # renames Event/Lat/Long, and warns + fills in ALT (missing entirely here):
#' names(standardize_survey_columns(dat)) # "EVENTNO" "LATITUDE" "LONGITUDE" "ALT"
#'
#' # a combined date column instead of separate YEAR/MONTH/DAY:
#' dat2 <- data.frame(EVENTNO = 1, Date = "2024-08-15", ALT = 750)
#' out <- standardize_survey_columns(dat2)
#' out$YEAR # 2024
#' @export
standardize_survey_columns <- function(dat, alt_default = 229, prefer_track = TRUE) {
  norm <- function(x) gsub("[^a-z0-9]", "", tolower(x))
  # how many real values a column carries - blanks count as missing, since a
  # CSV's empty cell can arrive as either NA or "" depending on how it was read
  n_values <- function(x) sum(!is.na(x) & trimws(as.character(x)) != "")

  current_names <- names(dat)
  current_norm <- norm(current_names)

  # Reserve any column that looks like a combined date/datetime column
  # before the per-canonical-name matching below runs. Without this, a
  # compound name like "SurveyDateTime" gets claimed by TIME's "time"
  # alias (since "datetime" contains "time" as a substring) before the
  # derivation step below ever sees it - a genuine standalone time column
  # is normally named with "time" but not "date", so this only holds back
  # columns that are actually date/datetime-shaped.
  date_aliases_norm <- norm(c("date", "surveydate", "eventdate", "obsdate", "sightingdate", "gmtdate", "utcdate"))
  reserved <- current_norm %in% date_aliases_norm | grepl("date", current_norm, fixed = TRUE)

  # A column that already carries a canonical name, or that gets renamed to one
  # below, is off-limits to every other canonical's substring fallback. Without
  # this, PLATFORM normalizes to "platform", which *contains* LATITUDE's "lat"
  # alias - so a file with a PLATFORM column but no exact LATITUDE column had
  # its platform renamed to LATITUDE. Any two canonicals whose aliases nest
  # like that would collide the same way.
  claimed <- current_names %in% names(survey_column_aliases)

  renamed_from <- character(0) # canonical -> the column name it came from

  for (canonical in names(survey_column_aliases)) {
    canon_idx <- which(current_names == canonical)
    canon_has_data <- length(canon_idx) > 0 && n_values(dat[[canon_idx[1]]]) > 0

    # A GPS track column outranks a canonical column already present under its
    # own name (see survey_preferred_source) - but only if it has data of its
    # own, since displacing a real column with an empty one is exactly the
    # failure the value-ranking below exists to prevent.
    preferred_norm <- if (prefer_track) norm(survey_preferred_source[[canonical]]) else character(0)
    has_preferred <- length(preferred_norm) > 0 &&
      any(vapply(which(current_norm %in% preferred_norm & !claimed),
                 function(i) n_values(dat[[i]]) > 0, logical(1)))

    # an exact match already present settles it - unless it's empty, in which
    # case keep looking (a file can carry both a placeholder column with the
    # canonical name and a populated one under a different name), or unless a
    # preferred source is sitting alongside it.
    if (canon_has_data && !has_preferred) next

    candidates_norm <- norm(c(canonical, survey_column_aliases[[canonical]]))
    search_idx <- setdiff(which(!reserved & !claimed), canon_idx)

    # 1. exact match against the canonical name or a known alias
    hits <- search_idx[current_norm[search_idx] %in% candidates_norm]

    # 2. generic fallback: any column whose normalized name contains the
    # canonical name (or a known alias) as a substring, or is contained by
    # one - e.g. "Event" or "Event_ID" for EVENTNO, "Survey_Alt_ft" for
    # ALT. Broader than the curated list above, so a variant nobody
    # enumerated still matches. The trade-off is a higher chance of
    # matching an unrelated column that happens to share the substring,
    # which is why every match here still goes through the same ambiguity
    # warning below rather than being applied silently.
    if (length(hits) == 0) {
      hits <- search_idx[vapply(search_idx, function(i) {
        x <- current_norm[i]
        nchar(x) > 0 && any(vapply(candidates_norm, function(cand) {
          # alias inside the column name, anywhere: "Survey_Alt_ft" for "alt".
          # Column name inside the alias only as a *prefix*: an abbreviation
          # shortens from the end ("event" for "eventno", "long" for
          # "longitude"), so requiring a prefix keeps that while rejecting
          # coincidental interior hits - "lat" sits inside "platform", which
          # otherwise made a LATITUDE column match PLATFORM.
          grepl(cand, x, fixed = TRUE) || startsWith(cand, x)
        }, logical(1)))
      }, logical(1))]
    }

    if (length(hits) == 0) next

    # Rank the matches by how many values they actually carry, most first
    # (ties keep file order). Real exports carry columns that exist but were
    # never filled - an unused duplicate, a field the recorder skipped - and
    # picking by position alone hands the pipeline a column of NA while the
    # populated one sits next to it under a name nobody enumerated.
    # Among the columns that do have data, the documented priority order
    # decides (survey_alias_priority): TrkTime_UTC over a plain UTC spelling,
    # UTC over local, TrkAltitude_m over TrkAltitude_ft. Having data comes
    # first regardless - an empty TrkAltitude_m doesn't outrank a populated
    # TrkAltitude_ft just for being the preferred spelling.
    hit_values <- vapply(hits, function(i) n_values(dat[[i]]), integer(1))
    priority_of <- function(i) {
      order_for <- norm(survey_alias_priority[[canonical]])
      if (length(order_for) == 0) return(1L)
      m <- match(current_norm[i], order_for)
      if (is.na(m)) length(order_for) + 1L else m
    }
    hit_priority <- vapply(hits, priority_of, integer(1))
    ord <- order(-as.integer(hit_values > 0), hit_priority, -hit_values, hits)
    hits <- hits[ord]
    hit_values <- hit_values[ord]

    if (length(hits) > 1) {
      warning("Multiple columns look like '", canonical, "': ",
              paste0(current_names[hits], " (", hit_values, " value(s))", collapse = ", "),
              " - using '", current_names[hits[1]], "'. Rename the others if this is wrong.",
              call. = FALSE)
    }

    if (length(canon_idx) > 0) {
      # nothing populated to put in its place
      if (hit_values[1] == 0) next
      if (canon_has_data) {
        # the column named `canonical` has data, so only a preferred source
        # displaces it - and only if the preferred source is what won above
        if (!(current_norm[hits[1]] %in% preferred_norm)) next
        warning("'", current_names[hits[1]], "' is the platform's own GPS track log, ",
                "so it replaces the '", canonical, "' column recorded alongside it ",
                "(those are not the same position on a file covering more than one ",
                "platform). The displaced column was kept as '", canonical,
                "_ORIGINAL'. Pass prefer_track = FALSE to keep '", canonical,
                "' as it was.", call. = FALSE)
        names(dat)[canon_idx[1]] <- paste0(canonical, "_ORIGINAL")
      } else {
        warning("Column '", canonical, "' has no values; using '", current_names[hits[1]],
                "' (", hit_values[1], " value(s)) instead. The empty column was kept as '",
                canonical, "_empty'.", call. = FALSE)
        names(dat)[canon_idx[1]] <- paste0(canonical, "_empty")
      }
    }

    renamed_from[canonical] <- current_names[hits[1]]
    names(dat)[hits[1]] <- canonical
    claimed[hits[1]] <- TRUE
    current_names <- names(dat)
    current_norm <- norm(current_names)
  }

  # Convert any column whose name declares a unit onto the canonical one. ALT
  # is metres (handbook 8.A.1), so an altitude that arrived in feet is
  # multiplied by 0.3048 - read as metres it would overstate the altitude by
  # 3.28. The conversion is reported, since a silently rescaled column is worse
  # than one that was never converted.
  for (target in names(survey_unit_factors)) {
    src <- renamed_from[target]
    if (is.na(src)) next
    factors <- survey_unit_factors[[target]]
    m <- match(norm(src), norm(names(factors)))
    if (is.na(m)) next
    dat[[target]] <- suppressWarnings(as.numeric(dat[[target]])) * factors[[m]]
    warning("'", src, "' is named in feet; multiplied by ", factors[[m]],
            " to give ", target, " in metres (handbook 8.A.1).", call. = FALSE)
  }

  # derive YEAR/MONTH/DAY/TIME from a combined date(time) column, for a file
  # that has e.g. "Date" ("2024-08-15" or "2024-08-15 14:30:00") instead of
  # separate columns - whichever of the four are still missing after the
  # matching above get filled in from it; the others are left untouched.
  missing_date_parts <- setdiff(c("YEAR", "MONTH", "DAY", "TIME"), names(dat))
  date_hits <- which(reserved)
  # same value-first ranking as the per-column matching above
  date_values <- vapply(date_hits, function(i) n_values(dat[[i]]), integer(1))
  date_ord <- order(-date_values, date_hits)
  date_hits <- date_hits[date_ord]
  date_values <- date_values[date_ord]

  if (length(date_hits) >= 1) {
    if (length(date_hits) > 1) {
      warning("Multiple columns look like a date column: ",
              paste0(current_names[date_hits], " (", date_values, " value(s))", collapse = ", "),
              " - using '", current_names[date_hits[1]], "'.", call. = FALSE)
    }
    src_col <- current_names[date_hits[1]]
    src_chr <- as.character(dat[[src_col]])
    parsed <- suppressWarnings(lubridate::parse_date_time(
      src_chr, orders = c("Ymd HMS", "Ymd HM", "Ymd", "mdY HMS", "mdY", "dmY", "Y/m/d", "m/d/Y")
    ))
    blank <- is.na(src_chr) | trimws(src_chr) == ""
    n_failed <- sum(is.na(parsed) & !blank)
    if (n_failed > 0) {
      warning(n_failed, " value(s) in '", src_col, "' couldn't be parsed as a date and became NA.",
              call. = FALSE)
    }

    # from narwcr: keep the supplied date as DATE rather than only mining it
    # for parts. YEAR/MONTH/DAY are on whatever clock the programme recorded
    # them on, and TIME may now come from the GPS track log (UTC) - rebuilding
    # the date from the parts puts the date and the time on different clocks,
    # and every record within the offset of midnight gets the wrong date.
    # prep_survey_data() uses DATE when it's there, and the parts when it isn't.
    # DATE is the parsed value, never the raw text: a column already named DATE
    # can hold "8/15/2024", which as.Date() reads as the year 8 rather than
    # rejecting, so leaving it as written just moves the failure downstream.
    if ("DATE" %in% names(dat) && !identical(src_col, "DATE")) {
      warning("'", src_col, "' (", date_values[1], " value(s)) is used as DATE ahead of the ",
              "column already named 'DATE'; that one was kept as 'DATE_ORIGINAL'.",
              call. = FALSE)
      names(dat)[which(names(dat) == "DATE")[1]] <- "DATE_ORIGINAL"
    }
    dat$DATE <- as.Date(parsed)

    if (length(missing_date_parts) > 0) {
      message("Derived ", paste(missing_date_parts, collapse = "/"), " from '", src_col, "'")
      if ("YEAR" %in% missing_date_parts) dat$YEAR <- lubridate::year(parsed)
      if ("MONTH" %in% missing_date_parts) dat$MONTH <- lubridate::month(parsed)
      if ("DAY" %in% missing_date_parts) dat$DAY <- lubridate::day(parsed)
      if ("TIME" %in% missing_date_parts) {
        dat$TIME <- as.numeric(format(parsed, "%H%M%S"))
      }
    }
  }

  if (!("ALT" %in% names(dat))) {
    warning("ALT column not found (even after alias matching); defaulting to ", alt_default, " m",
            " for every record. This pipeline's own filtering doesn't use ALT, so this only ",
            "matters if you're using it for something else - pass alt_default to override.",
            call. = FALSE)
    dat$ALT <- alt_default
  }

  dat
}
