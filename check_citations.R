#' Check that README.md's References section is still current
#'
#' README.md cites R packages two different ways, and they need different
#' checks:
#' \itemize{
#'   \item Packages cited as "PackageName: Title [R package]" (the CRAN
#'     auto-generated style) embed a specific version/year, so a newer CRAN
#'     release means the citation should be bumped.
#'   \item Packages cited via a fixed academic paper (e.g. `sf`'s Pebesma
#'     2018 R Journal article, `coda`'s Plummer et al. 2006 R News piece)
#'     don't go stale just because the package released a new version - what
#'     matters is that the package (and its DOI/URL) still exists.
#' }
#' Also checks that every external URL cited in the README (NARWC handbook,
#' Copernicus Marine Service, `datamatch`, the JAGS paper) still resolves.
#'
#' Prints a PASS/FAIL report and exits non-zero if anything needs review, so
#' this can run as a scheduled CI check (see
#' `.github/workflows/check-citations.yml`) rather than relying on someone
#' remembering to look. Deliberately doesn't require the cited packages to be
#' installed - it reads each package's current CRAN metadata via
#' `tools::CRAN_package_db()`, so the check works even in an environment that
#' doesn't have this pipeline's own dependencies.
#'
#' @return invisibly, `TRUE` if everything is current, `FALSE` otherwise (also printed)
check_citations <- function() {
  # packages cited in the CRAN auto-generated "package version X (year)"
  # style: package -> year currently recorded in README.md. A newer CRAN
  # release means this citation should be bumped to match.
  versioned_packages <- c(
    dplyr = 2026, R2jags = 2024, readr = 2026, rjags = 2025,
    stringr = 2025, terra = 2026, tibble = 2026, yaml = 2025
  )

  # packages cited via a fixed academic paper, which doesn't change just
  # because the package released a new version - only worth flagging if the
  # package has been archived/removed from CRAN entirely.
  paper_cited_packages <- c("coda", "dclone", "lubridate", "sf")

  cited_urls <- c(
    "NARWC handbook" = "https://www.narwc.org/uploads/1/1/6/6/116623219/sightingsdatabaseusers_guideupdated2021-09-20.pdf",
    "Copernicus Marine Service" = "https://marine.copernicus.eu/",
    "datamatch" = "https://github.com/chross22/datamatch",
    "JAGS DSC 2003 paper" = "https://www.r-project.org/conferences/DSC-2003/Proceedings/Plummer.pdf"
  )

  ok <- TRUE
  url_reachable <- function(url) {
    tryCatch({
      con <- url(url, method = "libcurl")
      on.exit(try(close(con), silent = TRUE))
      suppressWarnings(readLines(con, n = 1))
      TRUE
    }, error = function(e) FALSE)
  }

  cran_db <- tryCatch(as.data.frame(tools::CRAN_package_db()), error = function(e) NULL)
  if (is.null(cran_db)) {
    cat("Could not reach CRAN's package database; skipping package checks.\n")
    ok <- FALSE
  } else {
    cat("=== Versioned package citations (bump if a newer release exists) ===\n")
    for (pkg in names(versioned_packages)) {
      row <- cran_db[cran_db$Package == pkg, , drop = FALSE]
      if (nrow(row) == 0) {
        cat(sprintf("  %-10s NOT FOUND on CRAN (removed/renamed?)\n", pkg))
        ok <- FALSE
        next
      }
      current_year <- as.integer(format(as.Date(row$`Date/Publication`[1]), "%Y"))
      recorded_year <- versioned_packages[[pkg]]
      status <- if (is.na(current_year) || current_year <= recorded_year) "PASS" else "STALE"
      if (status == "STALE") ok <- FALSE
      cat(sprintf("  %-10s recorded=%s current=%s [%s]\n", pkg, recorded_year, current_year, status))
    }

    cat("\n=== Paper-cited packages (only flagged if removed from CRAN) ===\n")
    for (pkg in paper_cited_packages) {
      on_cran <- nrow(cran_db[cran_db$Package == pkg, , drop = FALSE]) > 0
      if (!on_cran) ok <- FALSE
      cat(sprintf("  %-10s [%s]\n", pkg, if (on_cran) "PASS" else "REMOVED FROM CRAN"))
    }
  }

  cat("\n=== External URLs ===\n")
  for (name in names(cited_urls)) {
    reachable <- url_reachable(cited_urls[[name]])
    if (!reachable) ok <- FALSE
    cat(sprintf("  %-28s %s [%s]\n", name, cited_urls[[name]], if (reachable) "PASS" else "UNREACHABLE"))
  }

  cat("\n", if (ok) "All citations current." else "Some citations need review - see STALE/REMOVED/UNREACHABLE above.", "\n", sep = "")
  invisible(ok)
}

if (sys.nframe() == 0L) {
  ok <- check_citations()
  quit(status = if (isTRUE(ok)) 0L else 1L)
}
