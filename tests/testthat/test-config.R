make_temp_project <- function() {
  project_dir <- withr::local_tempdir(.local_envir = parent.frame())
  data_dir <- file.path(project_dir, "data")
  dir.create(data_dir, recursive = TRUE)
  writeLines("dummy", file.path(data_dir, "survey_data.csv"))
  project_dir
}

test_that("generate_config writes a YAML file and errors on overwrite without permission", {
  configs_dir <- withr::local_tempdir(.local_envir = parent.frame())
  project_dir <- make_temp_project()

  path <- generate_config("test_run", configs_dir = configs_dir, project_dir = project_dir)
  expect_true(file.exists(path))
  expect_equal(path, file.path(configs_dir, "test_run.yaml"))

  expect_error(
    generate_config("test_run", configs_dir = configs_dir, project_dir = project_dir),
    "already exists"
  )
  expect_no_error(
    generate_config("test_run", configs_dir = configs_dir, project_dir = project_dir, overwrite = TRUE)
  )
})

test_that("generate_config() -> load_config() round-trips the fields that matter", {
  configs_dir <- withr::local_tempdir(.local_envir = parent.frame())
  project_dir <- make_temp_project()

  path <- generate_config(
    "test_run", configs_dir = configs_dir, project_dir = project_dir,
    beg_year = 2015, end_year = 2018, species_codes = c("RIWH", "HUWH"), active_species = "HUWH",
    covariates_psi = c("sst"), n_chains = 4
  )
  config <- load_config(path)

  expect_equal(config$dates$beg_year, 2015)
  expect_equal(config$dates$end_year, 2018)
  expect_equal(unlist(config$species$codes), c("RIWH", "HUWH"))
  expect_equal(config$species$active, "HUWH")
  expect_equal(unlist(config$covariates$psi), "sst")
  expect_equal(config$jags$n_chains, 4)
})

test_that("load_config expands seasons into ssn_beg/ssn_end matrices", {
  configs_dir <- withr::local_tempdir(.local_envir = parent.frame())
  project_dir <- make_temp_project()
  path <- generate_config("test_run", configs_dir = configs_dir, project_dir = project_dir)
  config <- load_config(path)

  expect_equal(config$ssn_beg, rbind(c(8, 1), c(9, 1)))
  expect_equal(config$ssn_end, rbind(c(8, 31), c(9, 30)))
})

test_that("load_config expands the study-area polygon into a closed-ring lon/lat matrix", {
  configs_dir <- withr::local_tempdir(.local_envir = parent.frame())
  project_dir <- make_temp_project()
  path <- generate_config("test_run", configs_dir = configs_dir, project_dir = project_dir)
  config <- load_config(path)

  poly <- config$study_area$polygon_matrix
  expect_equal(colnames(poly), c("lon", "lat"))
  expect_equal(poly[1, ], poly[nrow(poly), ]) # closed ring
})

test_that("load_config resolves data_file/output_dir relative to project_dir", {
  configs_dir <- withr::local_tempdir(.local_envir = parent.frame())
  project_dir <- make_temp_project()
  path <- generate_config("test_run", configs_dir = configs_dir, project_dir = project_dir,
                           data_file = "data/survey_data.csv", output_dir = "output")
  config <- load_config(path)

  expect_equal(config$paths$data_file, file.path(normalizePath(project_dir), "data", "survey_data.csv"))
  expect_true(startsWith(config$paths$output_dir, normalizePath(project_dir)))
})

test_that("load_config errors clearly when the data file is missing and no google_drive_filename is set", {
  configs_dir <- withr::local_tempdir(.local_envir = parent.frame())
  project_dir <- withr::local_tempdir(.local_envir = parent.frame()) # no data/ subfolder created
  path <- generate_config("test_run", configs_dir = configs_dir, project_dir = project_dir,
                           data_file = "data/does_not_exist.csv")

  expect_error(load_config(path), "Data file not found")
})

test_that("load_config errors when species.active isn't one of species.codes", {
  configs_dir <- withr::local_tempdir(.local_envir = parent.frame())
  project_dir <- make_temp_project()
  path <- generate_config("test_run", configs_dir = configs_dir, project_dir = project_dir,
                           species_codes = c("RIWH"), active_species = "RIWH")

  # hand-corrupt the config to reference a species not in codes
  raw <- yaml::read_yaml(path)
  raw$species$active <- "HUWH"
  yaml::write_yaml(raw, path)

  expect_error(load_config(path), "must be one of species.codes")
})

test_that("a process with no covariates configured yields an empty (not NULL-crashing) covariates section", {
  configs_dir <- withr::local_tempdir(.local_envir = parent.frame())
  project_dir <- make_temp_project()
  path <- generate_config("test_run", configs_dir = configs_dir, project_dir = project_dir)
  config <- load_config(path)

  expect_equal(length(unlist(config$covariates$psi)), 0)
  expect_equal(length(unlist(config$covariates$phi)), 0)
  expect_equal(length(unlist(config$covariates$gamma)), 0)
})
