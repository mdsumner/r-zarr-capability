# Publishing notes

The site is GitHub Pages, built with classic Jekyll from the root of `main`.
It uses the primer theme with a custom `_layouts/default.html` (a navigation
bar and horizontally scrolling tables), as
[rust-proj-capability](https://github.com/mdsumner/rust-proj-capability) does.

## Site map

| page | what it is |
|---|---|
| [README.md](README.md) | landing page: TL;DR, the landscape table, headline probe findings |
| [landscape.md](landscape.md) | one entry per package, marked verified (V) or inferred (I) |
| [gdal.md](gdal.md) | GDAL Zarr/Icechunk driver features by version; classic vs multidim by R binding |
| [probe/README.md](probe/README.md) | the write-by-read grid and what to take from it |

These are linked, not rendered: `probe/probe.R`, `probe/results.csv` and
`probe/sessioninfo.txt`.

## Rendering facts

- **Markdown:** GitHub-flavoured, with pipe tables and fenced code.
- **No front matter:** titles come from the first `#` heading
  (jekyll-titles-from-headings).
- **Links:** relative links to `.md` files, which jekyll-relative-links
  rewrites to `.html`.
- **Wide tables:** the layout makes them scroll rather than wrap.
- **Excluded:** `probe/fixtures/` (gitignored) and `*.R`.

## Regenerating

Run `Rscript probe/probe.R`, then update the grid in `probe/README.md` from
`results.csv`. Also update the prose findings in `README.md`,
`landscape.md` and `probe/README.md`, which quote the grid.
