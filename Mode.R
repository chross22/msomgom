#' Compute the statistical mode of a vector
#'
#' Source: <http://stackoverflow.com/questions/2547402/is-there-a-built-in-function-for-finding-the-mode>.
#' Not currently called anywhere in this pipeline; kept as-is from the
#' pre-refactor codebase.
#'
#' @param x vector to find the mode of
#' @param na.rm logical; if `TRUE`, `NA` values are dropped before computing the mode
#' @return the most frequent value in `x`
Mode <- function(x, na.rm = FALSE) {
#http://stackoverflow.com/questions/2547402/is-there-a-built-in-function-for-finding-the-mode
  if(na.rm){
    x = x[!is.na(x)]
  }

  ux <- unique(x)
  return(ux[which.max(tabulate(match(x, ux)))])
}
