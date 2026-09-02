# gcc-c-torture

Verbatim mirror of GCC's `gcc/testsuite/gcc.c-torture`, pinned to the tag recorded in [`PROVENANCE`](PROVENANCE).

## Updating to a newer GCC release

```sh
./sync-upstream.sh releases/gcc-16.2.0
git status
git commit -am "Sync gcc.c-torture from releases/gcc-16.2.0"
```

The script does a blobless, shallow, sparse clone of GCC, replaces the mirrored
paths and regenerates `PROVENANCE`. It never commits or pushes.

## Verifying the mirror

`PROVENANCE` records a checksum over the mirrored paths:

```sh
find ChangeLog.0 compat compile execute unsorted -type f -print0 \
  | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum
```

To check against upstream, re-run `sync-upstream.sh` with the tag named in
`PROVENANCE` and confirm `git status` reports a clean tree.
