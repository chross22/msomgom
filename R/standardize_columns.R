# dynocc does not keep its own copy of the NARWC vocabulary. narwcr
# (chross22/narwcr) is the data-preparation layer for this archive, and
# `standardize_survey_columns()` runs `narwcr::standardize_narwc_columns()`
# first: the alias table, the `Trk*` GPS-track preferred sources, the alias
# priorities and the feet-to-metres conversions all come from there. Four rule
# changes crossed over by hand in two days before this became a dependency -
# one of them (a `TIME` that carries a clock, read as `NA` without a word) was
# a silent corruption that the hand sync only caught because it was looked for.
#
# What stays here is what narwcr deliberately does not do:
#
#  * A substring fallback. narwcr refuses to guess - `Sighting_Event_Num` is
#    not in its alias table and stays unrecognised. This pipeline is willing
#    to guess and warn, because a column it fails to match is a hard stop.
#  * Preferring the column that has data. narwcr will not displace a populated
#    column, but it also won't rescue a canonical column that came through
#    empty when a populated one is sitting beside it under another name.
#  * PLATFORM aliases (below), which narwcr's vocabulary doesn't carry.
#  * The ALT default, and deriving YEAR/MONTH/DAY/TIME from a date column.

# The one part of the vocabulary narwcr doesn't have. Canonical name ->
# aliases, matched case-insensitively and ignoring non-alphanumerics, same as
# narwcr's own table. Anything added here is a candidate to send upstream.
survey_extra_aliases <- list(
  # NOT "aerial"/"vessel"-as-a-value: those are PLATFORM *values* in exports
  # that name their platforms instead of using NARWC's numeric codes (see
  # prep_survey_data(), which matches either). "vessel" is here as a column
  # name, since a file that records one boat per row commonly calls the column
  # that.
  PLATFORM = c("platform", "platformcode", "platformid", "platformno",
               "platformtype", "surveyplatform", "vessel"),
  # narwcr carries TIME_UTC, TIME_GMT and GMT, but not a column named just
  # "UTC" - which is how at least one export in this archive spells it.
  TIME = c("utc", "utctime")
)

# Mirrors narwcr's `narwc_unit_factors()`, which is internal there. Only
# reached for a column narwcr didn't recognise at all and this package's
# substring fallback did - anything narwcr matched has already been converted
# by the time that fallback runs. ALT is metres (handbook 8.A.1).
survey_unit_factors <- list(
  ALT = c(trkaltitude_ft = 0.3048, altft = 0.3048, altitudeft = 0.3048)
)

# The full vocabulary: narwcr's, plus the extras above. Built per call rather
# than stored, so it tracks whatever narwcr is installed.
survey_column_aliases <- function() {
  narwcr_aliases <- narwcr::narwc_schema()$aliases
  by_canonical <- split(unname(names(narwcr_aliases)), unname(narwcr_aliases))
  # Extras first, and the order matters: the substring fallback tries each
  # canonical in turn, and a three-letter alias like LATITUDE's "lat" sits
  # inside "Platform_Code". PLATFORM has to get its say before LATITUDE starts
  # guessing, the same way narwcr's own table puts PLATFORM near the top.
  canonical <- union(names(survey_extra_aliases), names(by_canonical))
  stats::setNames(lapply(canonical, function(nm) {
    unique(tolower(c(by_canonical[[nm]], survey_extra_aliases[[nm]])))
  }), canonical)
}

#' Standardize survey CSV column names to what this pipeline expects
#'
#' Real survey exports rarely use the exact NARWC column names
#' (`prep_survey_data()`'s import step expects `EVENTNO`, `LATITUDE`, etc.
#' literally) - a column might be `Event`, `event_no`, or `Event No.` instead.
#'
#' [narwcr::standardize_narwc_columns()] does the resolving: the shared NARWC
#' vocabulary, the `Trk*` GPS-track preferred sources, the alias priorities and
#' the feet-to-metres conversions all live there, and every rename and
#' conversion it makes is reported. This function adds what narwcr
#' deliberately doesn't do:
#' \enumerate{
#'   \item A generic fallback for anything narwcr left unrecognised: a column
#'     whose name contains a canonical name or known alias as a substring, or
#'     is a prefix of one - `"Survey_Alt_ft"` for `ALT`, `"Event_ID"` for
#'     `EVENTNO`. narwcr refuses to guess; this pipeline is willing to guess
#'     and warn, because a column it can't match is a hard stop. The cost is a
#'     higher chance of matching an unrelated column that happens to share the
#'     substring, so every match here goes through the ambiguity warning below
#'     rather than being applied silently.
#'   \item Preferring the column that has data. Where several candidates
#'     qualify, the one carrying the most values wins (ties keep file order),
#'     and a canonical column that came through empty is displaced by a
#'     populated one found under another name - kept as `<CANONICAL>_empty`,
#'     with a warning. narwcr won't overwrite a canonical column, so without
#'     this an empty placeholder silently beats the real data beside it.
#'   \item `PLATFORM` aliases, which narwcr's vocabulary doesn't carry.
#' }
#' Matching ignores case, spaces, underscores, and punctuation throughout, so
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
#' by 0.3048 on the way in (narwcr's conversion, reported as it happens).
#'
#' See [narwcr::standardize_narwc_columns()] for the rules this defers to,
#' notably the `Trk*` preferred sources: a GPS track column displaces a
#' `LATITUDE`/`LONGITUDE`/`ALT`/`TIME`/`LEGTYPE` column already present under
#' its own name, keeping the displaced one as `<CANONICAL>_ORIGINAL`.
#' `prefer_source` is passed straight through.
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
#' @param prefer_source passed to [narwcr::standardize_narwc_columns()]:
#'   whether a preferred source (a `Trk*` GPS track column, or `LEGTYPE_BK`)
#'   displaces the column already present under the canonical name (default
#'   `TRUE`). `FALSE` keeps the column that's already there.
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
standardize_survey_columns <- function(dat, alt_default = 229, prefer_source = TRUE) {
  norm <- function(x) gsub("[^a-z0-9]", "", tolower(x))

  # narwcr first: the shared vocabulary, the Trk* preferred sources, the alias
  # priorities and the unit conversions. Everything below is this package's own
  # additions, applied to whatever narwcr left unrecognised.
  # quiet = FALSE deliberately: it controls the rename report *and* the
  # unit-conversion notice, so quietening the noise would also make an
  # altitude silently rescaled from feet to metres - the exact failure this
  # pipeline keeps being bitten by.
  dat <- narwcr::standardize_narwc_columns(dat, quiet = FALSE, prefer_source = prefer_source)
  aliases <- survey_column_aliases()

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
  claimed <- current_names %in% names(aliases) |
    # a column narwcr set aside as the displaced half of a preferred-source
    # swap is not a candidate for anything
    grepl("_ORIGINAL$", current_names)

  renamed_from <- character(0) # canonical -> the column name it came from

  for (canonical in names(aliases)) {
    canon_idx <- which(current_names == canonical)

    # A canonical column that's present and populated settles it. Preferred
    # sources (a Trk* GPS column outranking the plain column beside it) have
    # already been applied by narwcr above; what's left for this pass is the
    # case narwcr doesn't cover - a canonical column that came through empty,
    # with a populated one sitting beside it under a name narwcr didn't match.
    if (length(canon_idx) > 0 && n_values(dat[[canon_idx[1]]]) > 0) next

    candidates_norm <- norm(c(canonical, aliases[[canonical]]))
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
    # (Columns narwcr recognised are already resolved by its own priority
    # order, so what reaches here is only ever the leftovers.)
    hit_values <- vapply(hits, function(i) n_values(dat[[i]]), integer(1))
    ord <- order(-hit_values, hits)
    hits <- hits[ord]
    hit_values <- hit_values[ord]

    if (length(hits) > 1) {
      warning("Multiple columns look like '", canonical, "': ",
              paste0(current_names[hits], " (", hit_values, " value(s))", collapse = ", "),
              " - using '", current_names[hits[1]], "'. Rename the others if this is wrong.",
              call. = FALSE)
    }

    if (length(canon_idx) > 0) {
      # the column named `canonical` is empty (checked above); nothing to do
      # unless what we found is actually populated
      if (hit_values[1] == 0) next
      warning("Column '", canonical, "' has no values; using '", current_names[hits[1]],
              "' (", hit_values[1], " value(s)) instead. The empty column was kept as '",
              canonical, "_empty'.", call. = FALSE)
      names(dat)[canon_idx[1]] <- paste0(canonical, "_empty")
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
