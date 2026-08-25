# --- drawing the maps -------------------------------------------------------
#
# These diagnostics started as sf's default `plot()`, which draws the geometry
# and little else: no land, no projection, no scale a reader can judge a value
# against. `fancymaps` exists for exactly the quantities this pipeline emits -
# a bounded probability (occupancy, persistence, colonization), a skewed
# positive surface (effort, counts), and the uncertainty that belongs beside
# any of them - so the maps are drawn with it when it is installed.
#
# It stays a Suggests. Without it every map still draws, in base graphics, the
# way it always did; the figure is plainer, not absent.

fancymaps_available <- function() requireNamespace("fancymaps", quietly = TRUE)

#' Draw one grid column, with fancymaps if it is installed
#'
#' @param grid an `sf` polygon grid carrying the column to draw
#' @param column name of the column
#' @param kind `"probability"` for a 0-1 quantity, `"surface"` for a positive
#'   one - which scale a reader should be given
#' @param main plot title
#' @param label legend label; defaults to `column`
#' @param ... passed to the underlying plot call
#' @return the `ggplot` from fancymaps, or `NULL` when base graphics drew it
#' @keywords internal
draw_grid_map <- function(grid, column, kind = c("surface", "probability"),
                          main = NULL, label = NULL, ...) {
  kind <- match.arg(kind)
  label <- label %||% column

  if (!fancymaps_available()) {
    plot(grid[column], main = main, ...)
    return(invisible(NULL))
  }

  # A cell that was never surveyed is not a zero, and a map that draws it as
  # one invents effort. fancymaps leaves NA cells unfilled.
  fig <- if (kind == "probability") {
    fancymaps::map_probability(grid, value = column, label = label, title = main)
  } else {
    fancymaps::map_surface(grid, value = column, label = label, title = main)
  }
  print(fig)
  invisible(fig)
}

#' Attach a figure to the data it was drawn from
#'
#' Every diagnostic here returns its underlying data invisibly, so a figure
#' can be checked numerically rather than by eye - that contract predates
#' fancymaps and the tests depend on it. The `ggplot` rides along as an
#' attribute, so it can still be themed, faceted or `ggsave()`d.
#'
#' @param data the data to return
#' @param fig the figure, or `NULL`
#' @return `data`, with `fig` attached as the `"plot"` attribute
#' @keywords internal
with_plot <- function(data, fig) {
  attr(data, "plot") <- fig
  invisible(data)
}
