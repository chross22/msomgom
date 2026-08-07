# The package's own citation.
#
# Offline and cheap, so it belongs here rather than in the scheduled citation
# check: it wants to run on every push, not quarterly.
#
# Three failure modes, all silent:
#   * no inst/CITATION, so citation("msomgom") falls back to an auto-generated
#     entry with no author and no URL;
#   * a version hard-coded in inst/CITATION, which goes stale the moment
#     DESCRIPTION is bumped and then disagrees between machines;
#   * a README that never tells anyone how to cite the package.

pkg_root <- function() {
  for (p in c(".", "..", "../..", "../../..")) {
    if (file.exists(file.path(p, "DESCRIPTION"))) return(p)
  }
  NA_character_
}

test_that("inst/CITATION exists and parses", {
  root <- pkg_root()
  skip_if(is.na(root), "package root not found")

  cit <- file.path(root, "inst", "CITATION")
  expect_true(file.exists(cit))

  ver <- read.dcf(file.path(root, "DESCRIPTION"), fields = "Version")[1, 1]
  parsed <- utils::readCitationFile(
    cit, meta = list(Package = "msomgom", Version = ver)
  )
  expect_gte(length(parsed), 1)
})

test_that("inst/CITATION does not hard-code a version", {
  root <- pkg_root()
  skip_if(is.na(root), "package root not found")
  cit <- file.path(root, "inst", "CITATION")
  skip_if_not(file.exists(cit))

  ver <- read.dcf(file.path(root, "DESCRIPTION"), fields = "Version")[1, 1]
  txt <- paste(readLines(cit, warn = FALSE), collapse = " ")
  hard <- unique(unlist(regmatches(
    txt, gregexpr("[0-9]+[.][0-9]+[.][0-9]+([.][0-9]+)?", txt)
  )))
  # meta$Version is the only acceptable source, so nothing but the current
  # version should ever appear literally.
  expect_setequal(setdiff(hard, ver), character(0))
})

test_that("the README says how to cite the package", {
  root <- pkg_root()
  skip_if(is.na(root), "package root not found")
  rd <- file.path(root, "README.md")
  skip_if_not(file.exists(rd))

  txt <- paste(readLines(rd, warn = FALSE), collapse = "\n")
  expect_match(txt, "(?im)^#+\\s*(how to )?cit(e|ing|ation)", perl = TRUE, all = FALSE)
  expect_match(txt, "msomgom", fixed = TRUE)
})
