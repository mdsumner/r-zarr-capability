# Probe: write by read

`probe.R` writes R's `volcano` matrix (87 x 61, float64) with each
writer, then reads every resulting store back with each reader. Fixtures are
written to `probe/fixtures/` (gitignored) and rebuilt on every run. Output:

- [results.csv](results.csv): the grid below;
- [sessioninfo.txt](sessioninfo.txt): versions.

```sh
Rscript probe/probe.R
```

Run on 2026-11-09 with:
- R 4.6.1, GDAL 3.14.0dev and netCDF-C 4.9.2;
- terra 1.9-57, stars 0.7-3, vapour 0.16.0.9002, gdalraster 2.7.0.9002 and
  GDAL7 0.1.0;
- zarr 1.0.1, pizzarr 0.2.2 (the r-universe build, with zarrs), Rarr 2.1.14,
  zaro 0.0.1.9030 and RNetCDF 2.11-2.

Rarr and zaro trail their current releases (devel 2.1.57 and 0.0.1.9036).

## Writers

| writer | layout |
|---|---|
| gdal v2 none / blosc / zlib | `gdal_translate -of ZARR -co FORMAT=ZARR_V2 -co COMPRESS=…`; C order, single chunk, X/Y coordinate arrays, `.zmetadata` |
| gdal v3 zstd | `FORMAT=ZARR_V3 COMPRESS=ZSTD` |
| gdal v3 sharded | `FORMAT=ZARR_V3 COMPRESS=GZIP BLOCKSIZE=32,32 SHARD_CHUNK_SHAPE=16,16` |
| zarr v3 default | `zarr::as_zarr(volcano, name = "volcano")`: `transpose` + `bytes` + `blosc(zstd, bitshuffle)`, single chunk |
| pizzarr v2 / v3 default | `zarr_create_array(data = volcano, zarr_format = 2L/3L)`: v2 `order: "F"` + `zstd`; v3 `bytes` + `zstd` |
| Rarr v2 zlib | `write_zarr_array(zarr_version = 2L, use_zlib())`, 32x32 chunks, `order: "F"` |
| Rarr v3 zstd | `write_zarr_array(zarr_version = 3L, use_zstd())`, 32x32 chunks, `transpose` codec |

## Reading a cell

- `exact`: the reader returned `volcano` as is.
- `t`, `flip rows`, …: the values are right once you apply that transform.
  This is the reader's orientation convention, not an error.
- `WRONG`: the reader returned values without an error, and no transpose or
  flip recovers `volcano`. `WRONG: shuffled` means the right values are
  present in some other arrangement.
- `ERR`: the reader raised an error. The message is truncated.

## Results

| writer | terra | stars | vapour | gdalraster mdim | GDAL7 | zarr | pizzarr | Rarr | zaro | RNetCDF (NCZarr) |
|---|---|---|---|---|---|---|---|---|---|--- |
| gdal v2 none | exact | t | exact | exact | t | exact | exact | exact | exact | t |
| gdal v2 blosc | exact | t | exact | exact | t | exact | exact | exact | exact | WRONG |
| gdal v2 zlib | exact | t | exact | exact | t | ERR: attempt to set an attribute on NULL… | exact | exact | exact | WRONG |
| gdal v3 zstd | exact | t | exact | exact | t | exact | exact | exact | exact | ERR: NetCDF: Variable not found… |
| gdal v3 sharded | exact | t | exact | exact | t | exact | ERR: Unsupported V3 codec: 'sharding_indexe… | ERR: The following codecs are not supported… | exact | ERR: NetCDF: Variable not found… |
| zarr v3 default | flip rows | t | exact | exact | t | exact | exact | exact | WRONG: shuffled | ERR: NetCDF: Variable not found… |
| pizzarr v2 default | flip rows | t | exact | exact | t | exact | exact | exact | exact | WRONG |
| pizzarr v3 default | flip rows | t | exact | exact | t | exact | exact | exact | exact | ERR: NetCDF: Variable not found… |
| Rarr v2 zlib | flip rows | t | exact | exact | t | ERR: attempt to set an attribute on NULL… | exact | exact | exact | WRONG |
| Rarr v3 zstd | flip rows | t | exact | exact | t | exact | WRONG | exact | WRONG | ERR: NetCDF: Variable not found… |

## What to take from it

1. **GDAL reads everything here**, whichever binding you use. The GDAL
   columns differ only in orientation:
   - `stars` and `GDAL7` keep GDAL's fastest-first dimension order;
   - `terra` flips rows when there are no Y coordinates.
2. **Sharding** is read by GDAL, `zarr` and `zaro`. `pizzarr`'s R codec
   path and Rarr 2.1.14 refuse it, with clear messages.
3. **`zarr` (R-CF) cannot decode the v2 `zlib` compressor.** `gzip` is fine.
   The error message does not say what is missing.
4. **The v3 `transpose` codec is a trap:**
   - `pizzarr` reads it correctly from a single-chunk store, but
     reads wrong values from Rarr's 32x32-chunked store, which has partial
     edge chunks;
   - `zaro` reads wrong values from both.

   Both of these are silent. They are worth reporting upstream.
5. **NCZarr (RNetCDF on netCDF-C 4.9.2):**
   - it reads uncompressed v2;
   - **compressed v2 comes back as garbage with no error**: with no
     `HDF5_PLUGIN_PATH`, the codecs are not loaded;
   - v3 arrays are invisible.

## Not covered

The probe only uses local stores and float64 data. It does not cover:
- remote stores (HTTP, S3, GCS);
- Kerchunk and VirtualiZarr references;
- Icechunk repositories;
- fill values and NA handling;
- strings and other data types;
- consolidated metadata on its own;
- `Rzarrs`, `zr`, the gdalraster `gdalmultidim-api` branch, and the
  reticulate route.

Each of these would be a natural next column or row.
