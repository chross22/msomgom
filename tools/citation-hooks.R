# Project-specific citation checks for dynocc.
#
# The generic engine is fetched from chross22/distsamp at run time. Anything
# that knows something about *this* repository lives here.

# The NARWC handbook edition this package's documentation is written against.
# Bump only after checking the new version's variable definitions: section
# numbers shift whenever a variable is added.
cited_handbook_version <- 8L

#' Has the NARWC published a newer handbook?
check_narwc_version <- function(registry, ctx) {
  page <- tryCatch(
    paste(readLines("https://www.narwc.org/sightings-database.html", warn = FALSE),
          collapse = " "),
    error = function(e) NULL
  )
  if (is.null(page)) {
    return(cc_result(notes = "Could not reach narwc.org to check the handbook version."))
  }
  pats <- c("[Vv]ersion\\s*([0-9]+)", "users_guide[^\"']*?v([0-9]+)")
  nums <- integer(0)
  for (p in pats) {
    hits <- regmatches(page, gregexpr(p, page))[[1]]
    nums <- c(nums, suppressWarnings(as.integer(gsub("\\D", "", hits))))
  }
  nums <- nums[!is.na(nums) & nums > 0 & nums < 100]
  newest <- if (length(nums)) max(nums) else NA_integer_

  if (is.na(newest)) {
    return(cc_result(notes = paste0(
      "No version string found on the NARWC page; the layout may have changed.")))
  }
  if (newest > cited_handbook_version) {
    return(cc_result(failures = paste0(
      "NARWC handbook Version ", newest, " is available; the README cites ",
      "Version ", cited_handbook_version, ". Check the variable definitions ",
      "before bumping it - section numbers shift when variables are added.")))
  }
  cc_say("  ok  NARWC handbook still at Version ", cited_handbook_version)
  cc_result()
}

citation_hooks <- function() {
  list("6. NARWC handbook version" = check_narwc_version)
}
