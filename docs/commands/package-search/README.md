# package-search

Smart query over the packages index (packages source only).

> **Hidden command.** `package-search` is functional but does **not** show up in `cupertino --help`. It exists as a focused entry point against `packages.db` only. For a unified surface across docs + samples + HIG + packages + Swift Evolution / Swift.org / Swift Book, use [`ask`](../ask/) instead.

## Synopsis

```bash
cupertino package-search "<question>" [--limit <n>] [--db <path>]
```

## Description

`package-search` is a thin wrapper on `Search.SmartQuery` configured with a single fetcher: the packages-FTS candidate fetcher. Same ranking infrastructure as `cupertino ask` (reciprocal-rank fusion, k=60), just scoped to one source.

Use it when you want results from `packages.db` only and want to bypass the multi-source fan-out cost of `ask`. For everything else, prefer `ask`.

## Options

| Option | Description |
|--------|-------------|
| `<question>` (positional, required) | Plain-text question |
| `--limit` | Max number of chunks to return. Default `3`. |
| `--db` | Override `packages.db` path. Defaults to the configured packages database. |

## Examples

```bash
cupertino package-search "swift-collections deque API"
cupertino package-search "vapor middleware composition" --limit 5
cupertino package-search "swift-syntax visitor pattern" --db /tmp/packages.db
```

## Relationship to `ask`

`ask` and `package-search` share the `SmartQuery` core. `ask` runs every available `CandidateFetcher` in parallel and fuses the rankings; `package-search` runs only `PackageFTSCandidateFetcher`. Ranking tweaks land in one place because both go through `SmartQuery`.

## See Also

- [ask](../ask/) — unified surface across all sources
- [search](../search/) — single-source FTS with `MATCH` syntax
- [setup](../setup/) — provisions `packages.db` (downloaded from `cupertino-packages`)
