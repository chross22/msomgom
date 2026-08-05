# Reproduces a helper originally sourced by master.R (legacy/master.R) that was
# missing from the repo. Called as padstr0(dat$GMT, 6) to zero-pad a numeric
# HHMMSS time-of-day value (e.g. 800 -> "000800") to a fixed-width string.
#
# The call site patched a "02e+05" artifact left over from padding a
# character conversion of a round number like 200000, which is what you get
# if the number is converted to character before padding (as.character(2e5)
# is "2e+05" in R). Formatting directly as an integer avoids that failure
# mode entirely.
padstr0 <- function(x, width) {
  formatC(x, width = width, format = "d", flag = "0")
}
