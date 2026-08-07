#' Zero-pad a numeric time-of-day value to a fixed-width string
#'
#' Reproduces a helper originally sourced by master.R (legacy/master.R) that
#' was missing from the repo. Called as `padstr0(dat$GMT, 6)` to zero-pad a
#' numeric HHMMSS time-of-day value (e.g. 800 -> "000800").
#'
#' The call site patched a "02e+05" artifact left over from padding a
#' character conversion of a round number like 200000, which is what you get
#' if the number is converted to character before padding (`as.character(2e5)`
#' is `"2e+05"` in R). Formatting directly as an integer avoids that failure
#' mode entirely.
#'
#' @param x numeric vector to pad (e.g. `dat$GMT`, an HHMMSS time-of-day value)
#' @param width target string width
#' @return character vector, `x` zero-padded to `width` characters
#' @seealso [prep_survey_data()], which calls this on the survey's `GMT` column
#' @family pipeline stages
#' @examples
#' padstr0(800, 6)      # "000800"
#' padstr0(200000, 6)   # "200000", not "02e+05"
padstr0 <- function(x, width) {
  formatC(x, width = width, format = "d", flag = "0")
}
