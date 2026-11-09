# The GDAL tendril

Most R users who read Zarr today do it through GDAL, often without knowing
it. This page covers two things: what the driver can do, by GDAL version, and
what each R binding lets you reach.

Sources:
- the GDAL master docs,
  [`drivers/raster/zarr.rst`](https://github.com/OSGeo/gdal/blob/master/doc/source/drivers/raster/zarr.rst)
  and [`icechunk.rst`](https://github.com/OSGeo/gdal/blob/master/doc/source/drivers/raster/icechunk.rst),
  fetched 2026-11-09;
- the local build (`gdalinfo --format Zarr`, GDAL 3.14.0dev 2026-11-03).

## Driver features by version

| GDAL | feature | notes |
|---|---|---|
| 3.4 | Zarr driver, v2 + v3 read/write | v3 support tracked the spec as it changed. Final-spec v3 arrived in a later release (I) |
| 3.9 | CF-convention CRS read | `grid_mapping` |
| 3.11 | Kerchunk reference stores | `/vsikerchunk_json_ref/` (JSON v0/v1). Parquet refs need the Parquet driver. `CACHE_KERCHUNK_JSON=YES` caches a Parquet copy; `CONVERT_TO_KERCHUNK_PARQUET_REFERENCE=YES` converts one |
| 3.12 | Stores without directory listing | point at `zarr.json`, `.zmetadata`, `.zgroup` or `.zarray` directly |
| 3.13 | v3 **sharding** read + write | `-co SHARD_CHUNK_SHAPE=…`, with `BLOCKSIZE` as the shard shape |
| 3.13 | **multiscales** convention as overviews | `GetOverview()`, `BuildOverviews()`; only the spatial dims are downsampled |
| 3.13 | `spatial:` / `proj:` georeferencing | read, and write with `-co GEOREFERENCING_CONVENTION=SPATIAL_PROJ` (the default is the `_CRS` attribute) |
| 3.13 | multi-threaded chunk decode | automatic with `GDAL_NUM_THREADS`, plus `GDALMDArray::AdviseRead(CACHE_SIZE, NUM_THREADS)` |
| 3.14 | **Icechunk driver** (read-only) | Icechunk v1 and v2 format; inline, native and **virtual** chunk refs (URLs map to `/vsicurl/`, `/vsis3/`, …); `ICECHUNK:path?branch=…` or `?tag=…`; `/vsiicechunk/{…}` for low-level listing |
| 3.14 | `numcodecs.pcodec` | optional build (`HAVE_PCODEC=YES` on this machine) |

Always on, in every version:
- consolidated metadata (`.zmetadata` for v2, consolidated `zarr.json` for
  v3), used by default (`USE_CONSOLIDATED_METADATA`);
- xarray's `_ARRAY_DIMENSIONS`;
- NCZarr dimension names (read).

Codecs on this build:
- compressors `blosc`, `zlib`, `gzip`, `lzma`, `zstd` and `lz4`, plus blosc's
  `blosclz`, `lz4`, `lz4hc`, `snappy`, `zlib` and `zstd`;
- v3 write accepts `NONE`, `BLOSC`, `GZIP` and `ZSTD` only.

All of this is subject to how GDAL was built: libblosc, libzstd and liblz4
are optional. CRAN binary builds of `sf` and `terra` on macOS and Windows
bring their own GDAL, so check `gdalinfo --format Zarr` (or the R binding's
equivalent) for `COMPRESSORS=`.

## Addressing a store

```
/path/to/x.zarr                                  # local, classic or mdim
ZARR:"/path/to/x.zarr":/group/array              # classic: one array
ZARR:"/path/to/x.zarr":/array:0                  # classic: 2D slice of a 3D+ array
ZARR:"/vsicurl/https://host/x.zarr"              # HTTP (no listing needed with consolidated metadata)
/vsis3/bucket/x.zarr   /vsigs/…   /vsiaz/…       # object stores
/vsizip//path/x.zarr.zip                         # zipped store
/vsikerchunk_json_ref/{/path/refs.json}          # Kerchunk JSON
/path/refs.parq                                  # Kerchunk Parquet store
ICECHUNK:"/vsis3/bucket/repo.icechunk?branch=dev"  # Icechunk branch or tag
```

## Classic and multidim, in one paragraph

The classic API sees a single 2D array as a normal raster. Anything bigger
becomes subdatasets: one per array, or per 2D slice of a 3D+ array. The
multidimensional API sees the real structure: groups, arrays, dimensions with
indexing variables, attributes, and views (`[0,:,:]`, `[:,::-1]`). Utilities
work either way:
- `gdal mdim info`, `convert`, `mosaic` and `reproject` (CLI on 3.14);
- `gdalmdimtranslate` and `GDALMDArray::AsClassicDataset()`, which bridge the
  two APIs.

## What each R binding reaches

| binding | classic | multidim | write | lazy / chunk-aware | orientation returned (probe) |
|---|---|---|---|---|---|
| `terra` | `rast()`, `sds()` | `rast(x, md=TRUE, dims=)` | `writeRaster()` (classic CreateCopy) | windowed reads; `GDAL_NUM_THREADS` | `[row, col]`; rows flipped when the store has no X/Y coordinate arrays |
| `stars` / `sf` | `read_stars()` | `read_mdim(offset, count, step, proxy)`, `gdal_read_mdim()` | `write_mdim()` | `proxy = TRUE` | x,y (transposed) |
| `vapour` | `vapour_read_raster()`, `gdal_raster_data()` (warper), `vapour_sds_names()` | no (DSN strings and VRT only) | block writes | window, resample | `[row, col]` |
| `gdalraster` (CRAN) | `GDALRaster` | `mdim_info()`, `mdim_as_classic()`, `mdim_translate()` | classic `create()` / `createCopy()`; `mdim_translate()` | `mdim_as_classic` view | `[row, col]` |
| `gdalraster` `gdalmultidim-api` branch | as CRAN | `GDALMultiDimRaster`: groups, arrays, dimensions, attributes, extended types; `mdim_read*()` | `$createGroup()`, … | read with start and count | not probed |
| `GDAL7` | `gdal_open()`, `read_raster()` | `get_root_group()`, `open_group()`, `open_mdarray()`, `read_mdarray(start, count, step)`, `get_view()`, `as_mdarray()` | classic `gdal_create()`, `gdal_create_copy()`, `write_raster()`; no mdim write yet | `advise_read()` (threaded decode); `as_altarr()` ALTREP | GDAL order (transposed) |
| `gdalcubes` | image collections | no | netCDF out | cube chunks | n/a |
| `CopernicusMarine` | no | `stars` mdim proxy, subset, then `st_as_stars()` | no | proxy | as `stars` |
| `cmemsarco` | `ZARR:` DSN strings for `terra`/`vapour` | no | no | as the reader | as the reader |

Notes:
- **Icechunk through GDAL** needs GDAL 3.14. On this machine every binding
  above sees the `Icechunk` driver, because they all link the same libgdal.
  On CRAN binaries, that depends on when the bundled GDAL is bumped.
- **Kerchunk Parquet** additionally needs GDAL's (Arrow) Parquet driver, which
  CRAN binary GDALs often lack (I).
- **gdalraster mdim branch:** a classic `GDALRaster`-style Rcpp module, which
  keeps it close to gdalraster's existing idiom. GDAL7 instead takes its
  object model from the SWIG `.i` files, so its coverage follows the
  Python/Java bindings. The two cover most of the same ground. The probe
  exercised only GDAL7, because the branch is not installed here.
- **Orientation:** GDAL hands arrays out fastest dimension first. Bindings
  that keep GDAL's order (`stars`, `GDAL7`) give `[x, y]`. Bindings built
  around classic rasters (`terra`, `vapour`, `gdalraster`) give image rows as
  R rows.
