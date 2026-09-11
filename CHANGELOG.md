# Changelog

Kept in the shape of [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), dated rather than numbered, and with no `Unreleased` section — this repository is read at whatever revision you have checked out, so whatever is on the default branch is what every reader already has

## 2026-09-11

### Changed

- the corpus preset turns PaperQA2's doc details off (`parsing.use_doc_details`), so `pqa index` no longer asks the model for a structured citation of each paper or Semantic Scholar and Crossref for its metadata; `programs.papers.corpus.docDetails` turns it back on. With it on, one Semantic Scholar 429 ended the whole index with exit 1 and left the paper marked failed in that index for good; `references/paperqa.md` says how to spot such a paper and retry it

### Fixed

- `search_papers` reports a Semantic Scholar refusal (rate limited, an HTTP error, a network error) under `errors["semantic"]` instead of answering zero results for it, and `search_semantic` fails instead of returning an empty list: the packaged `paper-search-mcp` carries the fix from openags/paper-search-mcp#111 until a release does, as `workarounds.md` records

### Removed

- `x86_64-darwin` from the flake's systems: the locked nixpkgs refuses to evaluate for Intel Macs, so its packages could never be built. `aarch64-darwin` stays, and is now built and checked on a macOS runner on every push and pull request

## 2026-09-10

### Added

- the `papers` skill: `search` turns a topic into a shortlist of identifiers with one line per paper, `read` turns an identifier into a digest of at most 450 words written by a reading subagent in its own context, `review` compares several digests, and `note` files one into the user's vault only when they say so, through a profile the vault's owner writes. The master never reads a PDF or a search result in bulk; that is what keeps a paper from costing a conversation's context
- `references/`: which source for which area and how identifiers map to the server's tools, the reading subagent's prompt word for word, the digest template with its bounds, the vault profile schema, and the corpus mode
- the `corpus` mode: a question across a folder of papers goes to PaperQA2 on local models. The flake carries PaperQA2 2026.8.12 as a locked environment built by uv2nix from `nix/paperqa/uv.lock`, since it is not in nixpkgs and pins litellm below what nixpkgs has, and exposes it as `packages.paper-qa`; the lock pins `fhlmi` and `fhaviary` to what PaperQA2's own lock names, because the newer `fhlmi` its metadata allows crashes the agent before its first call, and adds `pillow` and `fonttools`, which its PDF reader needs and does not declare. `programs.papers.corpus` installs it and writes the `pqa -s papers` preset for Ollama, with `qwen3.5:9b` answering and `bge-m3` embedding by default, text-only parsing, a model timeout long enough for the first GPU load, and two concurrent calls
- `pqa-evidence`, retrieval without the answer model: PaperQA2's paper search and evidence gathering with the contextual summaries off, so only the embedding model runs and the passages come back untouched for the agent to reason over. It is the corpus mode's default; `pqa ask` is the option that spares the conversation's context, and the preset makes it work on a local model: the `ollama_chat/` provider, which carries the tool calls every PaperQA2 agent ends on, thinking off, text summary prompts instead of JSON, and a smaller evidence budget, measured at 44 s per question on `qwen3.5:9b`
- the profile installs a wrapper over the PaperQA2 environment rather than the environment itself: a whole site-packages in a Home Manager profile collides with any other Python environment there on the files they share
- `paper-search-mcp` 0.1.4 packaged from PyPI in `nix/package.nix`, built against nixpkgs' mcp 1.x, which is what keeps the server importable: upstream leaves the SDK unbounded and breaks under 2.x. The unused `fastmcp` requirement is dropped. The flake exposes the package, an overlay, and a Home Manager module with `programs.papers.enable` and `programs.papers.envFile`, which points both binaries at an env file a secret store renders
- `check.sh`, the gate: lint, the vendored skill, pin and changelog checkers, and two checks that tie the documents to the packaged server — every `mcp__paper-search__*` tool the documents name exists in the server's tool list, and every source name in `references/sources.md` is one the CLI lists — each proven able to fail on a planted defect
