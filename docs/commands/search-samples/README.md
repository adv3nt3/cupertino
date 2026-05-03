# cupertino search-samples (REMOVED)

> **Note:** The `cupertino search-samples` command has been removed. Sample-code search is now part of the unified `cupertino search` command.

## Why Removed?

The standalone `search-samples` subcommand was folded into the unified [`search`](../search/) command in v0.10. `search` now covers Apple documentation, sample code, HIG, Apple Archive, Swift Evolution, swift.org, the Swift Book, and Swift packages from a single entry point, with `--source` to narrow.

## Migration

| Old | New |
|---|---|
| `cupertino search-samples "SwiftUI"` | `cupertino search "SwiftUI" --source samples` |
| `cupertino search-samples "View" --framework swiftui` | `cupertino search "View" --source samples --framework swiftui` |
| `cupertino search-samples "X" --search-files` | covered by `search` automatically (sample source files are indexed) |

## See Also

- [search](../search/) — unified search across all sources
- [ask](../ask/) — natural-language question across all sources with rank fusion
