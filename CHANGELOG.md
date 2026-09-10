# Changelog

Kept in the shape of [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), dated rather than numbered, and with no `Unreleased` section — this repository is read at whatever revision you have checked out, so whatever is on the default branch is what every reader already has

## 2026-09-10

### Added

- the `papers` skill: `search` turns a topic into a shortlist of identifiers with one line per paper, `read` turns an identifier into a digest of at most 450 words written by a reading subagent in its own context, `review` compares several digests, and `note` files one into the user's vault only when they say so, through a profile the vault's owner writes. The master never reads a PDF or a search result in bulk; that is what keeps a paper from costing a conversation's context
- `references/`: which source for which area and how identifiers map to the server's tools, the reading subagent's prompt word for word, the digest template with its bounds, and the vault profile schema; `docs/paperqa.md` records when a corpus would need PaperQA2 instead
- `paper-search-mcp` 0.1.4 packaged from PyPI in `nix/package.nix`, built against nixpkgs' mcp 1.x, which is what keeps the server importable: upstream leaves the SDK unbounded and breaks under 2.x. The unused `fastmcp` requirement is dropped. The flake exposes the package, an overlay, and a Home Manager module with `programs.papers.enable` and `programs.papers.envFile`, which points both binaries at an env file a secret store renders
- `check.sh`, the gate: lint, the vendored skill, pin and changelog checkers, and two checks that tie the documents to the packaged server — every `mcp__paper-search__*` tool the documents name exists in the server's tool list, and every source name in `references/sources.md` is one the CLI lists — each proven able to fail on a planted defect
