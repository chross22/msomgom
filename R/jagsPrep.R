#' Build the spatial grid and detection-history/covariate arrays
#'
#' Builds a spatial grid over the configured study area, then fills 3D arrays
#' (site x visit x season) of species detection histories and detection
#' covariates (survey effort, day-of-year, Beaufort sea state) for JAGS.
#'
#' Based on the most complete of what used to be three near-duplicate scripts
#' (`legacy/master.R`, `legacy/real_deal_linestring6.R`, and the pre-refactor
#' `jagsPrep.R`): this one already included dropping surveys whose track
#' never enters the grid, and the `make_figs` flag.
#'
#' @param tmpdat the `tmpdat` data.frame from `prep_survey_data()`
#' @param season_info the `season_info` list from `prep_survey_data()`
#' @param config a config list, as returned by `load_config()`
#' @return list with:
#'   \item{species_arrays}{named list of one `<site x visit x season>` array per configured species code}
#'   \item{effort3d}{`<site x visit x season>` array of survey trackline length per grid cell}
#'   \item{jday3d}{`<site x visit x season>` array of day-of-year}
#'   \item{bft3d}{`<site x visit x season>` array of mean Beaufort sea state}
#'   \item{reps}{`<season x site>` matrix of repeat-visit counts}
#'   \item{max_survs}{maximum number of surveys in any one season}
#'   \item{num_cells}{number of grid cells (sites)}
#'   \item{num_ssn}{number of year x season combinations}
#'   \item{area_grid_sf}{the hex grid, as an `sf` polygon object with a `grid_id` column}
#' @seealso [prep_survey_data()], which produces `tmpdat`/`season_info`;
#'   [fit_occupancy_model()], the next pipeline stage, which takes this
#'   function's return value directly as `arrays`
#' @family pipeline stages
#' @examples
#' \dontrun{
#' config <- load_config("configs/bof_riwh.yaml")
#' prep <- prep_survey_data(config)
#' arrays <- build_detection_arrays(prep$tmpdat, prep$season_info, config)
#' arrays$num_cells
#' }
#' @export
build_detection_arrays <- function(tmpdat, season_info, config) {
  make_figs <- isTRUE(config$output$make_figs)
  if (make_figs) {
    # webshot: needed to save maps. on new systems, may have to do: webshot::install_phantomjs()
    for (pkg in c("mapview", "tmap", "webshot")) {
      if (!requireNamespace(pkg, quietly = TRUE)) {
        stop("The '", pkg, "' package is required when output.make_figs is true. ",
             "Install it with install.packages('", pkg, "').")
      }
    }
  }

  num_ssn <- season_info$num_ssn
  cell_size <- config$study_area$cell_size
  spp <- unlist(config$species$codes)
  num_spp <- length(spp)

  ## ADD GEOMETRY TO DATASET AND MAKE INTO SF OBJECT
  locs <- cbind(tmpdat$LONGITUDE, tmpdat$LATITUDE) # raw long/lat points
  locs_pts <- sfheaders::sf_point(obj = locs) # sfg object
  locs_sfc <- st_as_sfc(locs_pts, crs = "EPSG:4326") # sfc object, but CRS doesn't stick
  st_crs(locs_sfc) <- "EPSG:4326" # this sets CRS and it sticks
  tmpdat_sf <- st_sf(tmpdat, geometry = locs_sfc) # sf object
  rm(locs, locs_pts, locs_sfc)

  ## CREATE A GRID WITH SPATIAL INFORMATION AND GRID_IDS
  area_grid <- st_make_grid(tmpdat_sf, c(cell_size, cell_size), what = "polygons", square = FALSE)

  # restrict to the configured study-area polygon
  polygon_sfc <- st_sfc(st_polygon(list(config$study_area$polygon_matrix)))
  st_crs(polygon_sfc) <- "EPSG:4326"
  in_pts <- st_intersects(area_grid, polygon_sfc, sparse = FALSE) # find cells inside of polygon
  area_grid <- area_grid[in_pts] # reduce to list of cells only inside of polygon
  rm(in_pts, polygon_sfc)

  ## remove surveys that did not go into the grid defined above
  union_area_grid <- st_union(area_grid)
  tracks <- tmpdat_sf |>
    group_by(FILEID) |>
    arrange(FILEID, EVENTNO) |>
    summarise(do_union = FALSE) |>
    st_cast("LINESTRING")
  tracks$intersection <- st_intersects(union_area_grid, tracks, sparse = FALSE)[1, ]
  IN_fileids <- tracks$FILEID[tracks$intersection]
  tmpdat_sf <- tmpdat_sf |>
    filter(FILEID %in% IN_fileids)
  rm(tracks, IN_fileids)

  # To sf and add grid ID
  area_grid_sf <- st_sf(area_grid)
  area_grid_sf <- area_grid_sf |>
    mutate(grid_id = 1:length(lengths(area_grid)))
  num_cells <- dim(area_grid_sf)[1]
  print(num_cells)
  rm(area_grid)

  tmpdat_sf$grid_id <- NA
  grid_id_list <- st_intersects(area_grid_sf, tmpdat_sf)
  for (ii in 1:num_cells) {
    tmpdat_sf$grid_id[grid_id_list[[ii]]] <- ii
  }
  rm(ii)

  ## count number of surveys in each season. use maximum as number of columns in final occupancy matrix
  num_survs <- tibble(ssn = 1:num_ssn, num = NA)
  for (i in 1:num_ssn) {
    tmpdat_sf_ssn <- tmpdat_sf |> filter(season == i)
    num_survs[i, 2] <- length(unique(tmpdat_sf_ssn$FILEID))
  }
  rm(tmpdat_sf_ssn, i)
  max_survs <- max(num_survs[, 2])
  print(num_survs)
  print(max_survs)

  ## CREATE ARRAYS TO HOLD SPECIES DETECTION HISTORIES & DETECTION COVARIATE ARRAYS FOR JAGS MODELLING
  print(num_spp)
  spp3d <- array(dim = c(num_cells, max_survs + 1, num_ssn))
  for (j in 1:num_spp) {
    print(spp[j])
    cmd <- paste(spp[j], "3d = spp3d", sep = "")
    eval(parse(text = cmd))
  }

  effort3d <- spp3d # effort from linestrings
  jday3d <- spp3d
  bft3d <- spp3d
  reps <- matrix(data = NA, nrow = num_ssn, ncol = num_cells) # store number visits to each cell
  rm(spp3d)

  ## FILL DETECTION COVARIATE LIST OBJECTS AND 3D ARRAYS
  for (i in 1:num_ssn) {
    tmpdat_sf_season <- tmpdat_sf |> filter(season == i)
    season_ufids <- unique(tmpdat_sf_season$FILEID)
    num_season_ufids <- length(season_ufids)
    print(num_season_ufids)

    effort <- area_grid_sf
    jday <- area_grid_sf
    bft <- area_grid_sf
    effort[, 3:(max_survs + 2)] <- NA
    jday[, 3:(max_survs + 2)] <- NA
    bft[, 3:(max_survs + 2)] <- NA

    for (j in 1:num_season_ufids) {
      cmd <- paste("tmpdat_sf_season_survey = tmpdat_sf_season |> filter(FILEID == '", season_ufids[j], "')", sep = "")
      eval(parse(text = cmd))

      tmpdat_sf_season_survey_grid <- st_intersects(area_grid_sf, tmpdat_sf_season_survey)

      ## calculate effort using linestrings
      nereid_tracks <- tmpdat_sf_season_survey |>
        arrange(FILEID, EVENTNO) |>
        summarise(do_union = FALSE) |>
        st_cast("LINESTRING")

      if (make_figs) {
        figs_dir <- file.path(config$paths$output_dir, "figs")
        if (!dir.exists(figs_dir)) dir.create(figs_dir, recursive = TRUE)
        survey_map <- mapview::mapview(nereid_tracks, color = "red", lwd = 4, alpha = 1, popup = NULL) +
          mapview::mapview(tmpdat_sf_season_survey, color = "blue", cex = 2, alpha = .2, popup = NULL) +
          mapview::mapview(area_grid_sf)
        html_fl <- file.path(figs_dir, paste0(unique(tmpdat_sf_season$YEAR), "_ssn", i, "_surv", j, "_", season_ufids[j], ".html"))
        mapview::mapshot(survey_map, url = html_fl)
      }

      # intersect grid with survey trackline (linestring), calculate and store trackline length in each grid cell.
      # st_length() needs the sf object itself, not a column, so this can't
      # be a single pipe chain the way it could with magrittr's `.` - base
      # R's |> placeholder (_) only works as a direct named argument, not
      # nested inside another call like st_length(_) would be here.
      grid_x_track <- st_intersection(area_grid_sf, nereid_tracks)
      intersection <- grid_x_track |>
        mutate(total_length = st_length(grid_x_track)) |>
        mutate(total_length_km = as.numeric(total_length) * 0.001) |>
        group_by(grid_id)
      rm(grid_x_track)
      effort_joined <- area_grid_sf |>
        left_join(st_drop_geometry(intersection), by = "grid_id")
      effort[, j + 2] <- effort_joined$total_length_km
      rm(effort_joined, intersection, nereid_tracks)

      # fill jday array. jday should be the same for all grid cells within a survey
      if (length(unique(tmpdat_sf_season_survey$date_jday)) == 1) {
        jday[, j + 2] <- as.numeric(unique(tmpdat_sf_season_survey$date_jday))
      } else {
        print(">1 jday. STOP!")
        stop()
      }

      # fill bft array. NA-out grid cells not surveyed (below)
      for (k in 1:num_cells) {
        bft[k, j + 2] <- mean(tmpdat_sf_season_survey$BEAUFORT[tmpdat_sf_season_survey_grid[[k]]], na.rm = TRUE)
      }
      rm(tmpdat_sf_season_survey_grid)
    }

    names(effort)[3:(num_season_ufids + 2)] <- season_ufids
    names(jday)[3:(num_season_ufids + 2)] <- season_ufids
    names(bft)[3:(num_season_ufids + 2)] <- season_ufids

    # NA-out cells with no effort within jday, bft, other matrices
    effort_drop <- st_drop_geometry(effort)
    effort_drop_NA <- which(is.na(effort_drop), arr.ind = TRUE)
    effort_drop_NA[, 2] <- effort_drop_NA[, 2] + 1 # advance the column by one, to correct for the geom column
    jday[effort_drop_NA] <- NA
    bft[effort_drop_NA] <- NA
    rm(effort_drop)

    ## number of repeat visits to each site within the season
    repeatVisits <- st_drop_geometry(effort)
    repeatVisits <- repeatVisits[, -1] # remove first column (grid_id)
    repeatVisits[is.na(repeatVisits)] <- 0
    repeatVisits[repeatVisits > 0] <- 1
    repeatVisits <- rowSums(repeatVisits)
    print(repeatVisits)
    reps[i, ] <- repeatVisits

    effort3d[, , i] <- as.matrix(st_drop_geometry(effort))
    jday3d[, , i] <- as.matrix(st_drop_geometry(jday))
    bft3d[, , i] <- as.matrix(st_drop_geometry(bft))
    rm(effort, jday, bft)

    for (j in 1:num_spp) {
      print(spp[j])

      cmd <- paste(spp[j], "_season = tmpdat_sf_season |> filter(SPECCODE == '", spp[j], "')", sep = "")
      eval(parse(text = cmd))

      cmd <- paste(spp[j], "_ssn", i, "_grid_sf = area_grid_sf", sep = "")
      eval(parse(text = cmd))

      cmd <- paste(spp[j], "_ssn", i, "_grid_sf[,3:(max_survs+2)] = NA", sep = "")
      eval(parse(text = cmd))

      for (k in 1:num_season_ufids) {
        cmd <- paste(spp[j], "_season_survey = ", spp[j], "_season |> filter(FILEID == '", season_ufids[k], "')", sep = "")
        eval(parse(text = cmd))

        # within season[i] and survey[k], for spp[j], count number of sightings (not number of animals) in each grid cell
        cmd <- paste(spp[j], "_ssn", i, "_grid_sf[,k+2]", " = lengths(st_intersects(area_grid_sf,", spp[j], "_season_survey))", sep = "")
        eval(parse(text = cmd))
      }

      cmd <- paste(spp[j], "_ssn", i, "_grid_sf[effort_drop_NA] = NA", sep = "")
      eval(parse(text = cmd))
      spp_ssn_name <- paste(spp[j], "_ssn", i, "_grid_sf", sep = "")

      cmd <- paste("names(", spp[j], "_ssn", i, "_grid_sf)[3:(num_season_ufids+2)] = season_ufids", sep = "")
      eval(parse(text = cmd))

      cmd <- paste(spp[j], "3d[,,", i, "] = as.matrix(st_drop_geometry(", spp[j], "_ssn", i, "_grid_sf))", sep = "")
      eval(parse(text = cmd))

      cmd <- paste("rm(", spp[j], "_season, ", spp_ssn_name, ")", sep = "")
      eval(parse(text = cmd))
    }

    rm(effort_drop_NA, tmpdat_sf_season, num_season_ufids)
  }

  species_arrays <- mget(paste0(spp, "3d"))
  names(species_arrays) <- spp

  list(
    species_arrays = species_arrays,
    effort3d = effort3d,
    jday3d = jday3d,
    bft3d = bft3d,
    reps = reps,
    max_survs = max_survs,
    num_cells = num_cells,
    num_ssn = num_ssn,
    area_grid_sf = area_grid_sf
  )
}
