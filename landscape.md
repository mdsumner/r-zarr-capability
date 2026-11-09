# Landscape: every R route to Zarr we found

Checked on 2026-11-09. Each entry gives where the package lives, what it is
built on, and what it does with Zarr. Facts are marked:

- **(V)** verified, from a DESCRIPTION, README or NEWS, the package's exports,
  or the probe;
- **(I)** inferred, not checked on a page.

Sources:
- the r-universe search API (`q=zarr`, 34 hits);
- CRAN `available.packages()`;
- the Bioconductor 3.23 and 3.24 VIEWS files;
- GitHub repositories;
- packages installed locally.

Versions in the probe can trail the published ones. Those are noted where
they matter.

## 1. GDAL route

These packages all go through the same GDAL Zarr and Icechunk drivers, so
their spec coverage is GDAL's (see [gdal.md](gdal.md)). They differ in two
things:
- whether they use the **classic** raster API (2D bands, with extra
  dimensions flattened into bands or subdatasets) or the **multidimensional**
  API (groups, arrays, dimensions, attributes);
- the orientation of the arrays they return.

### terra
- CRAN; 1.9-57 was used locally.
- `rast()` uses the classic API by default. Its signature includes `md` and
  `dims` (V), which open through the multidim API and pick dimensions.
- `sds()` lists subdatasets. `writeRaster()` writes Zarr through GDAL
  CreateCopy (I).
- Probe: reads every store (V). The orientation is right when X/Y coordinate
  arrays exist, and flipped in rows when they don't (V).

### stars, with sf
- CRAN `stars` 0.7-3 and `sf` 1.1-3.
- `stars::read_mdim()` and `write_mdim()` sit on `sf::gdal_read_mdim()` and
  `gdal_write_mdim()` (V, exports).
- `read_mdim()` uses the GDAL multidim API and supports `offset`, `count`,
  `step` and `proxy` (V, signature).
- Arrays come back in x,y (GDAL fastest-first) order: transposed relative to
  R's `[row, col]` (V, probe).

### vapour
- CRAN 0.16.
- Classic API through `vapour_read_raster()`, `vapour_raster_info()` and
  `vapour_sds_names()`, plus the warper (`gdal_raster_data()`,
  `vapour_warp_raster()`).
- Probe: reads every store in R orientation (V).
- `gdal_raster_data()` refused stores without georeferencing (they "could not
  be processed with GDALWarp api"). Use `vapour_read_raster()` for those (V).

### gdalraster
- CRAN 2.7.0, from the firelab maintainers. The probe used 2.7.0.9002.
- Classic `GDALRaster` plus multidim utilities: `mdim_info()`,
  `mdim_as_classic()` and `mdim_translate()` (V, exports).
- `mdim_as_classic(dsn, array_name, idx_xdim, idx_ydim)` gives a classic
  `GDALRaster` view of any 2D slice of an MDArray.
- Probe: reads every store in R orientation (V).
- **The `gdalmultidim-api` branch** (mdsumner/gdalraster, last merged with
  main 2026-06-16) adds a full Rcpp-module class `GDALMultiDimRaster` (V,
  `R/gdalmultidim.R`) and about 6,100 lines (V, diff stat):
  - supporting classes `GDALGroupR`, `GDALMDArrayR`, `GDALDimensionR`,
    `GDALAttributeR` and `GDALExtendedDataTypeR`;
  - methods `$getRootGroup()`, `$getArrayNames()`, `$openArray()`,
    `$openArrayFromFullname()`, `$openSubGroup()`, `$createGroup()`, metadata
    and `$info()`;
  - functional wrappers `mdim_read()`, `mdim_read_info()`,
    `mdim_read_dim_values()`, `mdim_read_coord_info()`,
    `mdim_read_array_attrs()` and `mdim_read_group_attrs()`.

  Related branches: `multidimnew`, `as-classic-mdim-factory`, `multidim`. The
  branch is not installed here and was not probed.

### GDAL7
- GitHub [rgdal-dev/GDAL7](https://github.com/rgdal-dev/GDAL7), 0.1.0, active
  (last merge 2026-11-08).
- Bindings generated from GDAL's own SWIG interface files, bound with cpp11
  and S7 (V, README).
- The multidim surface is `gdal_open(path, multidim = TRUE)`,
  `get_root_group()`, `open_group()`, `open_mdarray()`, `mdarray_info()`,
  `read_mdarray(x, start, count, step)`, `get_view(arr, "[0,:,:]")` and
  `as_mdarray()` (V).
- `advise_read()` sends GDAL a batch read hint, so Zarr decodes the chunks it
  touches on `GDAL_NUM_THREADS` threads (V, docs).
- `as_altarr()` gives a lazy, chunk-cached ALTREP array (V).
- It ships a `multidim.zarr` example.
- Probe: reads every store. It returns GDAL dimension order (`t`) (V).

### gdalcubes
- CRAN 0.7.6.
- **Classic API only.** Cubes are built from GDAL image collections of 2D
  bands, so a Zarr store is just another classic raster source (I).

### Copernicus Marine clients
- `CopernicusMarine` (CRAN 0.5.0; 0.4.6.0002 checked locally) uses the
  **multidim API**, through `stars`. It has no Zarr reader of its own in
  0.4.6. Evidence (V, function bodies):
  - `cms_download_subset()` and `cms_zarr_proxy()` open a `stars` mdim proxy
    on a `/vsi*` URI, subset by dimension values, then call `st_as_stars()`;
  - it sets `GDAL_NUM_THREADS=ALL_CPUS`, `GDAL_HTTP_MULTICURL=YES` and
    `GDAL_DISABLE_READDIR_ON_OPEN=EMPTY_DIR`;
  - it requires GDAL 3.11 or later with BLOSC, and `has_blosc()` checks for
    it.

  The same author wrote the CRAN `blosc` package. Earlier versions may have
  decoded chunks themselves (I, not checked). CRAN 0.5.0 was not checked.
- `cmemsarco` (hypertidy, r-universe 0.1.0) is **classic API in practice**.
  It only builds `ZARR:"/vsicurl/<url>":/<array>` and `/vsis3/` strings, and
  suggests `terra` and `vapour` to read them (V, source).

## 2. Native R

### zarr (R-CF)
- CRAN 1.0.1 (2026-11-08); the probe used 1.0.1.
- It is a "native and extensible R driver", written in R6 and Rcpp, with
  `blosc` (V).
- Full v3 core (V, DESCRIPTION). It reads v2.
- Stores: `zarr_localstore`, `zarr_memorystore` and `zarr_httpstore`, plus
  S3 (V, exports and agent).
- Conventions API: `zarr_conventions()`, `zarr_convention_uom()` and others
  (V).
- No consolidated metadata (V, the print method shows
  `✖ Consolidated metadata`).
- Probe:
  - reads v2 and v3 from every writer, including GDAL-sharded stores (V);
  - **fails on v2 `zlib`** with `attempt to set an attribute on NULL`. Stores
    from both GDAL and Rarr hit this (V).
- Default write layout: v3, with `transpose` + `bytes` + `blosc(zstd,
  bitshuffle)`, chunk keys `c.0.0`, and fill value `9.969e36`, which is
  netCDF's default (V, fixture).
- Reverse dependency: `geozarr`.

### geozarr (R-CF)
- CRAN 0.3.0 (2026-10-30), built on `zarr`.
- Implements the GeoZarr domain conventions (V, repo description).
- Not probed.

### pizzarr
- From zarr-developers. CRAN 0.2.1 (2026-08-22); r-universe 0.2.2 (V).
- Two builds:
  - the CRAN build is pure R;
  - the r-universe build links the Rust `zarrs` crate via extendr. It adds
    parallel decode, more codecs, object stores, S3, GCS and Icechunk (V,
    README and `pizzarr_compiled_features()`).
- API: `zarr_open()`, `zarr_create_group()`, `zarr_create_array()`,
  `DirectoryStore`, `HttpStore`, `S3Store`, `GcsStore`, `IcechunkStore` and
  `slice()` (V).
- Probe, using the r-universe 0.2.2 build:
  - it reads v2 and v3 from every writer, except:
  - **sharded v3** gives `Unsupported V3 codec: 'sharding_indexed'` (the R
    codec path, even with `zarrs` compiled in);
  - **Rarr's v3 store** (`transpose` with 32x32 chunks over 87x61) reads wrong
    values;
  - `zarr`'s single-chunk transpose store reads correctly (V).
- Default v2 write layout: `order: "F"` and `zstd`. Every reader handled the
  `F` order except NCZarr, which needs codec plugins anyway (V).
- Its CRAN reverse dependencies: none on CRAN. `rnz` uses it (V).

### Rarr
- Bioconductor, from the Huber group at EMBL. Release 3.23 is 2.0.1, devel
  3.24 is 2.1.57, and r-universe has 2.1.59. **The probe used 2.1.14**, which
  is older than devel.
- R with bundled C codecs: blosc, zlib, gzip, bz2, lzma, lz4 and zstd
  (`use_*()`) (V).
- `read_zarr_array()`, `write_zarr_array(zarr_version = 2L|3L)`,
  `zarr_overview()`, `zarr_consolidate_metadata()` and attribute helpers (V).
- Remote: S3 and HTTP via `paws.storage` and `curl`. No S3 writes and no
  sharded writes yet (V, agent).
- The DelayedArray layer moved to `ZarrArray` (V).
- Probe:
  - Rarr 2.1.14 reads every store except GDAL-sharded, where it says
    `The following codecs are not supported` (V). Newer versions may differ.
- Bioc reverse dependencies (devel): anndataR, ImageArray, spatialdataR,
  spicyR, ZarrArray.

### rnz
- GitHub [DOI-USGS/rnz](https://github.com/DOI-USGS/rnz), forked from
  mdsumner/rnz.
- An RNetCDF-style API (`z_demo()` and similar) over `pizzarr`.
- v2 and v3 (NZ-1.0), over HTTP (V, README/agent).

## 3. Rust-backed

### Rzarrs
- r-universe RGenomicsETL, 0.1.0 (2026-09-07).
- The `zarrs` crate via savvy.
- v3 plus compatible v2, read first.
- Stores: file, HTTP and S3, with GCS and Azure optional.
- Codecs: bytes, gzip, zstd, crc32c, blosc, sharding and transpose.
- Aimed at `.zarr.zip` VCF-Zarr (V, README/agent).

### zr
- GitHub [mdsumner/zr](https://github.com/mdsumner/zr), 0.0.1.
- `zarrs` via extendr: v2 and v3 read over file, HTTP and S3, with local
  write only (V, README).
- Last commit (2026-03-19): "hit up against icechunk limitation".
- The README install line points at hypertidy/zr, which returns 404 (V).
- The locally installed copy is an older stub, so it was not probed.

### icechunkr
- In development in a private repo, mdsumner/icechunk-r (0.0.0.9000).
- Bindings to the Icechunk Rust library: storage (local, S3, GCS, Azure,
  HTTP, memory), repos, branches, tags, sessions, commits, rebase/merge, and
  virtual chunk refs with explicit container authorisation (V, DESCRIPTION
  and exports).
- A DBI interface (`dbConnect()` and friends).
- `ic_chunk_refs()` and `ic_refs_arrow()` read a snapshot's chunk references
  as a table. `ic_to_byterefs()` and `ic_repo_from_byterefs()` round-trip
  Kerchunk-style refs.
- Sessions are handed to `pizzarr::IcechunkStore` as bytes
  (`ic_session_bytes()`).
- This is the only R route that **writes** Icechunk without Python.

## 4. Arrow and byte references (hypertidy)

### zaro
- r-universe hypertidy, 0.0.1.9036; the probe used 0.0.1.9030.
- "Zarr via Arrow": Arrow filesystems and codecs, with optional `gdalraster`
  and `nanoparquet`.
- v2 and v3 with automatic detection, consolidated metadata and sharding (V,
  README and probe).
- Stores: HTTP, S3 and GCS.
- **Virtual stores:** Kerchunk JSON and Parquet, and VirtualiZarr manifests
  (V).
- API: `zaro()`, `zaro_read()`, `zaro_array()`, `zaro_plan()`,
  `zaro_chunks()` and others. Laziness comes from `altarr`.
- Probe:
  - reads every store in R orientation, including sharded (V);
  - **except `transpose`-codec stores** (both `zarr`'s and Rarr's), which read
    wrong values (V).

### altarr, ndr
- `altarr` (hypertidy, 0.1.1) provides lazy chunked arrays as ALTREP vectors
  that carry a `dim` but no class.
- `ndr` adds named-dimension arrays with coordinate indexing.
- Neither is a Zarr reader. They are the lazy array layer that `zaro` and
  `GDAL7` both use.

### blocklist, rustycogs, sds
- `blocklist` builds Kerchunk Parquet reference stores from NetCDF4/HDF5
  collections, using `gdal mdim mosaic` and `rhdf5` (V, README).
- `rustycogs` virtualises TIFF/COG tiles into byte refs with Rust (V, README).
- `sds` is a catalogue of spatial data sources.

## 5. NCZarr: RNetCDF and ncdf4

- netCDF-C has had NCZarr since 4.8. `RNetCDF::open.nc()` and
  `ncdf4::nc_open()` open `"file:///abs/path.zarr#mode=zarr,file"`. Use
  `mode=nczarr` for netCDF-flavoured stores, and `s3` instead of `file` when
  netCDF-C was built with S3.
- Probe (RNetCDF 2.11-2, netCDF-C 4.9.2, no `HDF5_PLUGIN_PATH`) (V):
  - uncompressed v2 reads correctly. Dimensions arrive reversed, as usual for
    netCDF in R;
  - **compressed v2 (blosc, zlib, zstd) reads garbage with no error**: the
    filter plugins are not loaded;
  - **v3 arrays are not found** at all;
  - pure-Zarr arrays without `_ARRAY_DIMENSIONS` get synthetic `_zdim_N`
    dimensions.
- Binary builds that bundle netCDF-C and plugins may behave better. We did
  not check them.

## 6. Bioconductor and domain stacks

- **ZarrArray** (Bioc 1.0.1; devel 1.1.8) is a DelayedArray backend on `Rarr`
  (V).
- **anndataR** (Bioc 1.2.3, from scverse) has a Zarr-backed AnnData through
  `Rarr`, in Suggests (V).
- **spatialdataR** (Bioc devel 0.99.47) handles SpatialData/OME-NGFF using
  `Rarr`, `ZarrArray` and `duckdb`. Companions: `SpatialData.data` and
  `SpatialData.plot` (V).
- **ImageArray** (Bioc 1.0.0) provides pyramidal images over `Rarr`,
  `ZarrArray` and `rhdf5` (V).
- OME-Zarr:
  - **romeo** (huber-group-embl r-universe, 0.99.2) reads, writes and
    validates multiscale OME-Zarr (V);
  - **OMERarr** (GitHub BIMSBbioinfo) is based on ome-zarr-models.py;
  - **VoltRon** (BIMSB, 0.3.2) is not on Bioc and uses ImageArray (I).
- **ZarrDataFrame** (BIMSB r-universe) is undocumented.
- **ZarrSparseMatrix** (GitHub GabrielHoffman) holds CSR/CSC AnnData `X` on
  `Rarr`. Its README says Bioc, but it is in neither VIEWS file.
- **lstar** (CRAN 0.2.2) is a C++17 single-cell store with its own v3 schema.
  It is not a general Zarr reader.
- Not Zarr, though often assumed:
  - `zellkonverter` (H5AD through Python);
  - `RBioFormats`;
  - `rhdf5`/`HDF5Array`, which are siblings;
  - `ncdfCF` and `CFtime`, which belong to the same R-CF org as `zarr` but
    have no Zarr in their DESCRIPTION (V);
  - `openeo` and `rstac`.

## 7. Python via reticulate

- `xarray.open_zarr()`, `zarr-python` 3, `icechunk`, `VirtualiZarr` and
  `kerchunk` all work through `reticulate`. Expect numpy C-order to R
  F-order conversion and orientation bookkeeping.
- Thin wrappers include `ezzarr` (ez-zarr), muschellij2/zarrr and
  hypertidy/zarrr (a 2022 skeleton).
- `ctreesR` wraps Arraylake.
- The dynverse `anndata` package (CRAN 0.8.0) is superseded by `anndataR`.
- Bioconductor/ZarrExperiment is stale (2024).
- `gdalxarray` (hypertidy; PyPI 0.5.1, 2026-10-20) is an xarray backend
  powered directly by GDAL: `xr.open_dataset(path, engine="gdalxarray")`
  (V, README). From R, through `reticulate`, it gives xarray's data model
  over GDAL's multidim API. That covers every GDAL Zarr feature above,
  including Kerchunk and Icechunk, plus non-Zarr multidim sources.
- `xrdbi` (not detailed yet) is a DBI-style layer that works only through
  xarray.
