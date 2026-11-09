# Write-by-read probe: every writer writes `volcano` (87 x 61 float64) to a
# local Zarr store, and every reader reads it back. One script, no harness.
#
#   Rscript probe/probe.R            # writes probe/results.csv and probe/sessioninfo.txt
#
# A cell is:
#   exact       values and R orientation match volcano
#   t, flip ... values match after that transpose/flip of the result: a
#               reader's orientation convention, not a bug
#   WRONG: C/F order   right values, laid out in the other memory order
#   WRONG: shuffled    right values, in no simple arrangement
#   WRONG       read succeeded, values differ
#   ERR: msg    the reader raised an error
#   -           not attempted (e.g. package not installed)
#
# Fixtures are local only: remote stores, Kerchunk refs and Icechunk repos are
# covered in the prose, not here.

suppressPackageStartupMessages({
  ok <- function(p) requireNamespace(p, quietly = TRUE)
})

here <- normalizePath(if (file.exists("probe/probe.R")) "probe" else ".")
fx <- file.path(here, "fixtures")
unlink(fx, recursive = TRUE)
dir.create(fx)

src <- volcano
storage.mode(src) <- "double"

## ---- writers -------------------------------------------------------------
## Each returns the path of the *array* inside the store, relative to the store.

tif <- file.path(fx, "volcano.tif")
local({
  # GDAL raster with 61 columns, 87 rows: row i of the image is volcano[i, ]
  ds <- gdalraster::create("GTiff", tif, ncol(src), nrow(src), 1, "Float64",
                           return_obj = TRUE)
  ds$setGeoTransform(c(0, 1, 0, nrow(src), 0, -1))
  ds$write(1, 0, 0, ncol(src), nrow(src), as.vector(t(src)))
  ds$close()
})

gdal_tr <- function(dst, ...) {
  out <- file.path(fx, dst)
  st <- system2("gdal_translate", c("-q", "-of", "ZARR", c(...), tif, out),
                stdout = TRUE, stderr = TRUE)
  if (!dir.exists(out)) stop(paste(st, collapse = " "))
  sub("[.]zarr$", "", dst) # GDAL names the array after the store
}

writers <- list(
  "gdal v2 none"    = function() gdal_tr("gdal-v2-none.zarr", "-co", "FORMAT=ZARR_V2", "-co", "COMPRESS=NONE"),
  "gdal v2 blosc"   = function() gdal_tr("gdal-v2-blosc.zarr", "-co", "FORMAT=ZARR_V2", "-co", "COMPRESS=BLOSC"),
  "gdal v2 zlib"    = function() gdal_tr("gdal-v2-zlib.zarr", "-co", "FORMAT=ZARR_V2", "-co", "COMPRESS=ZLIB"),
  "gdal v3 zstd"    = function() gdal_tr("gdal-v3-zstd.zarr", "-co", "FORMAT=ZARR_V3", "-co", "COMPRESS=ZSTD"),
  "gdal v3 sharded" = function() gdal_tr("gdal-v3-shard.zarr", "-co", "FORMAT=ZARR_V3", "-co", "COMPRESS=GZIP",
                                         "-co", "BLOCKSIZE=32,32", "-co", "SHARD_CHUNK_SHAPE=16,16"),
  "zarr v3 default" = function() {
    zarr::as_zarr(src, name = "volcano", location = file.path(fx, "rcf-v3.zarr"))
    "volcano"
  },
  "pizzarr v2 default" = function() {
    store <- pizzarr::DirectoryStore$new(file.path(fx, "pizzarr-v2.zarr"))
    pizzarr::zarr_create_group(store, zarr_format = 2L)
    pizzarr::zarr_create_array(data = src, store = store, path = "volcano", shape = dim(src),
                               dtype = "<f8", zarr_format = 2L)
    "volcano"
  },
  "pizzarr v3 default" = function() {
    store <- pizzarr::DirectoryStore$new(file.path(fx, "pizzarr-v3.zarr"))
    pizzarr::zarr_create_group(store, zarr_format = 3L)
    pizzarr::zarr_create_array(data = src, store = store, path = "volcano", shape = dim(src),
                               dtype = "<f8", zarr_format = 3L)
    "volcano"
  },
  "Rarr v2 zlib" = function() {
    p <- file.path(fx, "rarr-v2.zarr")
    dir.create(p)
    writeLines('{"zarr_format": 2}', file.path(p, ".zgroup"))
    Rarr::write_zarr_array(src, file.path(p, "volcano"), chunk_dim = c(32, 32),
                           compressor = Rarr::use_zlib(), zarr_version = 2L)
    "volcano"
  },
  "Rarr v3 zstd" = function() {
    p <- file.path(fx, "rarr-v3.zarr")
    dir.create(p)
    writeLines('{"zarr_format": 3, "node_type": "group", "attributes": {}}', file.path(p, "zarr.json"))
    Rarr::write_zarr_array(src, file.path(p, "volcano"), chunk_dim = c(32, 32),
                           compressor = Rarr::use_zstd(), zarr_version = 3L)
    "volcano"
  }
)

store_of <- c(
  "gdal v2 none" = "gdal-v2-none.zarr",
  "gdal v2 blosc" = "gdal-v2-blosc.zarr", "gdal v2 zlib" = "gdal-v2-zlib.zarr",
  "gdal v3 zstd" = "gdal-v3-zstd.zarr", "gdal v3 sharded" = "gdal-v3-shard.zarr",
  "zarr v3 default" = "rcf-v3.zarr", "pizzarr v2 default" = "pizzarr-v2.zarr",
  "pizzarr v3 default" = "pizzarr-v3.zarr",
  "Rarr v2 zlib" = "rarr-v2.zarr", "Rarr v3 zstd" = "rarr-v3.zarr"
)

## ---- readers -------------------------------------------------------------
## Each takes (store path, array path) and returns an R matrix or array.

readers <- list(
  terra = function(s, a) {
    r <- terra::rast(sprintf('ZARR:"%s":/%s', s, a))
    terra::as.matrix(r, wide = TRUE)
  },
  stars = function(s, a) stars::read_mdim(s, a)[[1]],
  vapour = function(s, a) {
    dsn <- sprintf('ZARR:"%s":/%s', s, a)
    d <- vapour::vapour_raster_info(dsn)$dimension
    matrix(vapour::vapour_read_raster(dsn, native = TRUE)[[1]], d[2], d[1], byrow = TRUE)
  },
  "gdalraster mdim" = function(s, a) {
    ds <- gdalraster::mdim_as_classic(s, a, idx_xdim = 1, idx_ydim = 0)
    on.exit(ds$close())
    matrix(ds$read(1, 0, 0, ds$getRasterXSize(), ds$getRasterYSize(),
                   ds$getRasterXSize(), ds$getRasterYSize()),
           ds$getRasterYSize(), byrow = TRUE)
  },
  GDAL7 = function(s, a) {
    ds <- GDAL7::gdal_open(s, multidim = TRUE)
    GDAL7::read_mdarray(GDAL7::open_mdarray(GDAL7::get_root_group(ds), a))
  },
  zarr = function(s, a) zarr::open_zarr(s, read_only = TRUE)[[paste0("/", a)]][],
  pizzarr = function(s, a) {
    z <- pizzarr::zarr_open(pizzarr::DirectoryStore$new(s), mode = "r", path = a)
    z$get_item("...")$data
  },
  Rarr = function(s, a) Rarr::read_zarr_array(file.path(s, a)),
  zaro = function(s, a) zaro::zaro_read(zaro::zaro(s, verbose = FALSE), a, verbose = FALSE),
  "RNetCDF (NCZarr)" = function(s, a) {
    nc <- RNetCDF::open.nc(sprintf("file://%s#mode=zarr,file", s))
    on.exit(RNetCDF::close.nc(nc))
    RNetCDF::var.get.nc(nc, a)
  }
)

## ---- judge ---------------------------------------------------------------

judge <- function(x) {
  x <- unname(drop(as.array(unclass(x))))
  dim(x) <- unname(dim(x)) # some readers name the dims
  storage.mode(x) <- "double"
  same <- function(y) identical(dim(y), dim(src)) &&
    isTRUE(all.equal(y, src, check.attributes = FALSE))
  fr <- function(m) m[nrow(m):1, , drop = FALSE]
  fc <- function(m) m[, ncol(m):1, drop = FALSE]
  # what you must do to the result to get volcano back
  fixes <- list("exact" = identity, "flip rows" = fr, "flip cols" = fc,
                "flip both" = function(m) fr(fc(m)),
                "t" = t, "t + flip rows" = function(m) fr(t(m)),
                "t + flip cols" = function(m) fc(t(m)),
                "t + flip both" = function(m) fr(fc(t(m))))
  for (f in names(fixes)) {
    y <- tryCatch(fixes[[f]](x), error = function(e) NULL)
    if (!is.null(y) && same(y)) return(f)
  }
  # right shape, but the bytes were laid out in the other memory order
  if (length(x) == length(src) &&
      isTRUE(all.equal(as.vector(x), as.vector(t(src)), check.attributes = FALSE)))
    return("WRONG: C/F order")
  if (length(x) == length(src) && isTRUE(all.equal(sort(as.vector(x)), sort(as.vector(src)))))
    return("WRONG: shuffled")
  "WRONG"
}

short <- function(e) {
  m <- gsub("[\r\n\t]+", " ", conditionMessage(e))
  paste("ERR:", substr(trimws(m), 1, 70))
}

pkg_of <- c(terra = "terra", stars = "stars", vapour = "vapour",
            "gdalraster mdim" = "gdalraster", GDAL7 = "GDAL7", zarr = "zarr",
            pizzarr = "pizzarr", Rarr = "Rarr", zaro = "zaro",
            "RNetCDF (NCZarr)" = "RNetCDF")

arrays <- character()
wrote <- character()
for (w in names(writers)) {
  arrays[w] <- tryCatch(writers[[w]](), error = function(e) NA_character_)
  wrote[w] <- if (is.na(arrays[w])) "write failed" else "ok"
}

res <- matrix("-", length(writers), length(readers),
              dimnames = list(names(writers), names(readers)))
for (w in names(writers)) {
  if (is.na(arrays[w])) next
  s <- file.path(fx, store_of[[w]])
  for (r in names(readers)) {
    if (!ok(pkg_of[[r]])) next
    res[w, r] <- tryCatch(
      suppressWarnings(judge(readers[[r]](s, arrays[[w]]))),
      error = short)
  }
}

out <- data.frame(writer = rownames(res), write = wrote[rownames(res)], res,
                  check.names = FALSE, row.names = NULL)
write.csv(out, file.path(here, "results.csv"), row.names = FALSE)

vers <- vapply(unique(c(pkg_of, "sf")), function(p)
  if (ok(p)) as.character(utils::packageVersion(p)) else "not installed", "")
sink(file.path(here, "sessioninfo.txt"))
cat("date:", format(Sys.Date()), "\n")
cat("R:", R.version.string, "\n")
cat("GDAL:", gdalraster::gdal_version()[1], "\n")
cat("netCDF-C:", system2("nc-config", "--version", stdout = TRUE), "\n")
cat("blosc in GDAL Zarr:", grepl("blosc", paste(system2("gdalinfo", c("--format", "Zarr"), stdout = TRUE), collapse = " ")), "\n")
cat("pizzarr compiled features:", paste(pizzarr::pizzarr_compiled_features(), collapse = ", "), "\n\n")
print(vers, quote = FALSE)
sink()

print(out, right = FALSE)
