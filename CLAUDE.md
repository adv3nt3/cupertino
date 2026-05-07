# Cupertino

## Active focus

[#183 — bugs → recrawl → vector → tutor](https://github.com/mihaelamj/cupertino/issues/183). v1.0.0 "First Light" shipped 2026-05-05, v1.0.1 shipped 2026-05-08; current focus is v1.0.2.

## v1.0.1 — shipped 2026-05-08

Binary-only release on top of v1.0.0. `databaseVersion` stays at `1.0.0`, so `cupertino setup` from a v1.0.1 binary downloads the same `cupertino-databases-v1.0.0.zip` bundle as v1.0.0.

Closed:

- [#261](https://github.com/mihaelamj/cupertino/issues/261) — `search --source packages` now queries packages.db ([PR #262](https://github.com/mihaelamj/cupertino/pull/262))
- [#200](https://github.com/mihaelamj/cupertino/issues/200) — case-axis URL dedup in crawler queue + indexer ([PR #264](https://github.com/mihaelamj/cupertino/pull/264))
- [#242](https://github.com/mihaelamj/cupertino/issues/242) — stale `cupertino serve` siblings reaped at startup ([PR #267](https://github.com/mihaelamj/cupertino/pull/267))

Why no re-index: verified before tagging that the shipped v1.0.0 `search.db` has zero case-axis duplicate pairs (a `GROUP BY LOWER(uri) HAVING variants > 1` query returned empty across 405,782 docs). Apple's JSON references during that crawl were uniformly lowercase, so the v1.0.0 corpus dodged the #200 bug. Re-index would be ~12 h locally with no observable benefit on the existing data; the fix is preventive for future crawls. If a refreshed bundle is wanted later, ship as v1.0.1.1.

[#199](https://github.com/mihaelamj/cupertino/issues/199) (contentHash + id non-determinism) deferred to v1.0.2: needs a design pass, not a bundle-DB concern.

## v1.0.2 (next)

Live milestone: [v1.0.2 (#8)](https://github.com/mihaelamj/cupertino/milestone/8). Carries [#199](https://github.com/mihaelamj/cupertino/issues/199) (deferred from v1.0.1), [#203](https://github.com/mihaelamj/cupertino/issues/203) crawler HTML fallback link extraction, [#236](https://github.com/mihaelamj/cupertino/issues/236) WAL on local DBs, [#241](https://github.com/mihaelamj/cupertino/issues/241) help-text audit, [#253](https://github.com/mihaelamj/cupertino/issues/253) concurrent `save` detection, plus follow-ups [#276](https://github.com/mihaelamj/cupertino/issues/276) dedup verification post-#199+#200 and [#277](https://github.com/mihaelamj/cupertino/issues/277) crawler stores under request URL not response.url. Likely a re-index release because #199 changes hash semantics; bundling decision at tag time.

Live bug list: https://github.com/mihaelamj/cupertino/issues?q=is%3Aopen+is%3Aissue+label%3Abug

Workflow: trunk-based development. Branch from `main` per bug (`fix/<issue>-<topic>`), PR to `main`, squash merge. Auto-delete-on-merge is enabled. No long-lived feature branches.

## Phase 2 onwards

See #183. v1.1+ design and academic research review live in `mihaela-blog-ideas/cupertino/research/`. The diagnostic block in MCP responses (Phase 2.1) is the keystone for everything that follows; do not start it until v1.0.2 ships.

## Conventions

See `AGENTS.md` for code style, commit format, and the "ask when unsure" workflow.

## Imported Rules

@../../private/mihaela-agents/Rules/AGENTS.md
