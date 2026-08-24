#!/usr/bin/env Rscript
# Command-line entry point for the occupancy-model pipeline, once dynocc is
# installed. Usage:
#   Rscript path/to/dynocc/inst/scripts/run_pipeline.R configs/bof_riwh.yaml
#
# Does not support occ_covariates (environmental covariates on
# occupancy/persistence/colonization) - for that, call run_occupancy_model()
# directly from an R session so you can pass in the covariate list.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) {
  stop("Usage: Rscript run_pipeline.R <path/to/config.yaml>", call. = FALSE)
}

library(dynocc)
run_occupancy_model(args[1])
