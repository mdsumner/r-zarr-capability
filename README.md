# Zarr from R: a capability map

There are many ways to reach a Zarr store from R. They fall into a few
families:

- **GDAL**: the Zarr and Icechunk drivers, reached through `terra`, `stars`/`sf`,
  `vapour`, `gdalraster` and `GDAL7`;
- **native R**: `zarr`, `pizzarr` and `Rarr`;
- **Rust-backed**: the `zarrs` crate inside `pizzarr`'s r-universe build, plus `Rzarrs` and `zr`, and `icechunkr`;
- **Arrow and byte references**: `zaro`, `blocklist` and `altarr`;
- **netCDF-C's NCZarr**: `RNetCDF` and `ncdf4`;
- **domain stacks built on these**: Bioconductor's `ZarrArray`, `anndataR`,
  `spatialdataR` and `ImageArray`; R-CF's `geozarr`; Copernicus Marine clients;
- **Python through `reticulate`**.

This repository gives a broad overview of those families. Measurement is
kept light. There is one probe: a write-by-read matrix that runs locally
([probe/](probe/README.md)). Everything else is prose with links:
[landscape.md](landscape.md) covers every package, and [gdal.md](gdal.md)
covers the GDAL tendril by GDAL version and by R binding.

Checked on 2026-11-09 with GDAL 3.14.0dev, netCDF-C 4.9.2 and R 4.6.1.
It is modelled loosely on
[rust-proj-capability](https://github.com/mdsumner/rust-proj-capability).

## TL;DR: which one?

- **Geospatial grids, remote stores, Kerchunk refs, Icechunk, georeferencing:**
  GDAL. GDAL's Zarr driver is the most complete Zarr reader R can reach:
  - v2 and v3 read and write;
  - sharding (3.13);
  - multiscales as overviews (3.13);
  - `spatial:`/`proj:` georeferencing (3.13);
  - Kerchunk JSON and Parquet references (3.11);
  - Icechunk repositories (3.14).

  The driver is the same everywhere. What differs is how much of the
  multidimensional API each binding exposes:
  - `terra`: classic API, plus `md=` for mdim;
  - `stars`: mdim, through `sf`;
  - `vapour`: classic;
  - `gdalraster`: `mdim_*` utilities on CRAN, and a full class API on the
    `gdalmultidim-api` branch;
  - `GDAL7`: the full mdim object model, with lazy ALTREP arrays.

  See [gdal.md](gdal.md).
- **Plain Zarr, no system libraries, CRAN only:** `zarr` (R-CF). It is native
  R plus Rcpp and has full v3 core, including sharding in our probe. It reads
  v2, but not v2 `zlib`.
- **Read and write v2 and v3 with an xarray-like API, S3/GCS/HTTP and an
  Icechunk handoff:** `pizzarr`. Use the r-universe build for the `zarrs` Rust
  backend; the CRAN build is pure R.
- **Bioconductor, DelayedArray, single-cell or OME-Zarr:** `Rarr`, then
  `ZarrArray`, then `anndataR`, `spatialdataR` and `ImageArray`.
- **Virtual stores (Kerchunk, VirtualiZarr manifests) without GDAL, or Arrow
  object stores:** `zaro`, together with `blocklist` and `altarr`.
- **netCDF-shaped code that already uses `RNetCDF` or `ncdf4`:** NCZarr works,
  but only in narrow cases: v2 only, and without codec plugins it returns wrong
  values for compressed data with no error. See the probe.
- **Something only Python has:** `reticulate` with `xarray`/`zarr-python`.

## The landscape

Versions are the current published ones as of 2026-11-09 (CRAN, Bioc release
or devel, r-universe). Details and caveats are in
[landscape.md](landscape.md).

| package | where | tech | Zarr | write | remote | notes |
|---|---|---|---|---|---|---|
| **GDAL route** | | | | | | |
| `terra` | CRAN 1.9-x | GDAL classic; `rast(md=)` mdim | v2+v3, all GDAL | yes (classic) | `/vsi*` | 2D/3D slabs as SpatRaster |
| `stars` (+`sf`) | CRAN 0.7-3 | GDAL mdim (`read_mdim`, `write_mdim`) | v2+v3 | yes | `/vsi*` | arrays come back in x,y order (transposed) |
| `vapour` | CRAN 0.16 | GDAL classic and warper | v2+v3 | limited | `/vsi*` | raw read and warp of `ZARR:` DSNs |
| `gdalraster` | CRAN 2.7.0 | GDAL classic + `mdim_info`, `mdim_as_classic`, `mdim_translate` | v2+v3 | yes | `/vsi*` | full `GDALMultiDimRaster` class on the `gdalmultidim-api` branch |
| `GDAL7` | GitHub [rgdal-dev/GDAL7](https://github.com/rgdal-dev/GDAL7) | SWIG-derived cpp11 + S7 bindings | v2+v3 | classic only | `/vsi*` | `GDALGroup` and `GDALMDArray`, `get_view`, `advise_read`, ALTREP `as_altarr` |
| `gdalcubes` | CRAN 0.7.6 | GDAL classic only | per GDAL | no | `/vsi*` | Zarr as a 2D-band cube source |
| `CopernicusMarine` | CRAN 0.5.0 | GDAL **mdim**, through a `stars` proxy | ARCO | no | HTTP/S3 | needs GDAL 3.11+ with BLOSC; no native reader (0.4.6) |
| `cmemsarco` | r-universe hypertidy | GDAL **classic** (`ZARR:` DSN strings for `terra`/`vapour`) | ARCO | no | `/vsicurl/`, `/vsis3/` | |
| **native R** | | | | | | |
| `zarr` | CRAN 1.0.1 (R-CF) | R6 + Rcpp, `blosc` | v3 core, reads v2 | yes | memory, file, HTTP, S3 | sharding; no consolidated metadata; extensible stores and codecs |
| `geozarr` | CRAN 0.3.0 (R-CF) | on `zarr` | per `zarr` | yes | per `zarr` | GeoZarr conventions |
| `pizzarr` | CRAN 0.2.1; r-universe 0.2.2 | pure R; r-universe adds Rust `zarrs` | v2+v3 | yes | HTTP; S3/GCS (zarrs) | `IcechunkStore` handoff from `icechunkr` |
| `Rarr` | Bioc 2.0.1 / devel 2.1.57 | R + bundled C codecs | v2+v3 | yes (local) | S3/HTTP (`paws`) | DelayedArray layer moved to `ZarrArray` |
| `rnz` | GitHub DOI-USGS/rnz | on `pizzarr` | v2+v3 | no | HTTP | RNetCDF-like API |
| **Rust-backed** | | | | | | |
| `Rzarrs` | r-universe RGenomicsETL | `zarrs` via savvy | v3 (+v2) | read-first | file, HTTP, S3 | VCF-Zarr, `.zarr.zip`, sharding |
| `zr` | GitHub mdsumner/zr | `zarrs` via extendr | v2+v3 | local only | file, HTTP, S3 | experimental |
| `icechunkr` | private (mdsumner/icechunk-r), in development | Rust `icechunk` via extendr | Icechunk (v3) | yes: repos, sessions, commits | local, S3, GCS, Azure, HTTP | DBI interface; chunk refs as tables; sessions handed to `pizzarr` |
| **Arrow / byte references** | | | | | | |
| `zaro` | r-universe hypertidy | R + Arrow filesystems; optional `gdalraster` | v2+v3, sharded | no | HTTP, S3, GCS | Kerchunk JSON/Parquet, VirtualiZarr manifests; lazy via `altarr` |
| `blocklist` | r-universe hypertidy | GDAL `mdim mosaic` + `rhdf5` | writes Kerchunk Parquet | refs | - | builds virtual stores from NetCDF4/HDF5 |
| **NCZarr** | | | | | | |
| `RNetCDF`, `ncdf4` | CRAN | netCDF-C NCZarr | v2 (4.9.2) | yes | S3 if netCDF-C built so | `file://...#mode=zarr`; codecs need HDF5 filter plugins |
| **Bioconductor / domain** | | | | | | |
| `ZarrArray` | Bioc 1.0.1 | DelayedArray on `Rarr` | per `Rarr` | - | per `Rarr` | |
| `anndataR` | Bioc 1.2.3 | `Rarr` (Suggests) | per `Rarr` | yes | | AnnData `.zarr` |
| `spatialdataR`, `ImageArray` | Bioc devel / 1.0.0 | `Rarr` + `ZarrArray` | per `Rarr` | | | SpatialData, OME-NGFF pyramids |
| `romeo`, `OMERarr`, `VoltRon`, `ZarrDataFrame`, `ZarrSparseMatrix` | r-universe / GitHub | mostly on `Rarr` | | | | OME-Zarr and single-cell; early |
| `lstar` | CRAN 0.2.2 | C++17 | own v3 schema | yes | | single-cell; not a general reader |
| **Python** | | | | | | |
| `reticulate` | CRAN | `xarray`, `zarr-python`, `icechunk` | everything Python does | yes | everything | plus thin wrappers: `ezzarr`, muschellij2/zarrr, `ctreesR` |
| `gdalxarray` | PyPI 0.5.1 (hypertidy) | xarray backend over GDAL multidim | all GDAL | no | `/vsi*` | xarray's model on GDAL's driver, reachable from R through reticulate; `xrdbi` sits on xarray too |

`blosc` (CRAN 0.1.2) is the shared codec dependency of `zarr` and `pizzarr`.

## What the probe shows

We wrote `volcano` (87 x 61, float64) with 10 writer configurations and
read each store with 10 readers. Full grid and caveats:
[probe/README.md](probe/README.md).

- **Every GDAL reader read every store.** That covers v2, v3, sharded, and the
  stores written by `zarr`, `pizzarr` and `Rarr`. GDAL is the reference reader
  in practice.
- **The readers disagree on orientation, not on values.**
  - `stars` and `GDAL7` return arrays in GDAL's fastest-dimension-first order
    (`t`).
  - `terra` flips rows for stores without X/Y coordinate arrays.
  - `vapour`, `gdalraster`, `zarr`, `pizzarr`, `Rarr` and `zaro` return R's
    `[row, col]`.
- **Sharding:** `zarr`, `zaro` and GDAL read it. `pizzarr`'s R path and the
  installed `Rarr` (2.1.14) refused it, with clear errors.
- **v2 `zlib`:** `zarr` 1.0.1 fails with
  `attempt to set an attribute on NULL`. `gzip` is fine.
- **v3 `transpose` codec with partial edge chunks** (as written by `Rarr`):
  `pizzarr` and `zaro` both read the wrong values.
- **NCZarr (`RNetCDF`, netCDF-C 4.9.2):**
  - it reads uncompressed v2;
  - it reads blosc/zlib/zstd v2 as garbage, with no error (no
    `HDF5_PLUGIN_PATH`);
  - it cannot see v3 arrays at all.

## What no R route does yet (as far as we found)

- write Icechunk from a GDAL binding (GDAL's Icechunk driver is read-only);
- write sharded v3 from `Rarr` or `pizzarr`'s pure-R path;
- give a CRAN-only, non-GDAL path for Kerchunk/virtual references (`zaro` is
  r-universe);
- give a single R array type that every reader returns: orientation is the
  binding's choice.

## Layout

- [landscape.md](landscape.md): one entry per package, covering what it is,
  versions, and what we verified versus what we inferred.
- [gdal.md](gdal.md): GDAL Zarr and Icechunk driver features by version, and
  how each R binding exposes them.
- [probe/](probe/README.md): `probe.R`, `results.csv`, `sessioninfo.txt`.
  Fixtures are regenerated into `probe/fixtures/`, which is gitignored.

To rerun the probe:

```sh
Rscript probe/probe.R
```
