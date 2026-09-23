# Changelog

Kept in the shape of [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), dated rather than numbered, and with no `Unreleased` section — this repository is read at whatever revision you have checked out, so whatever is on the default branch is what every reader already has

## 2026-09-23

### Changed

- the workflows take the family's shape: `build.yml` is what a cascade calls, `macos.yml` is its own badge, and the checks both run live once in a new `gate.yml` that neither of them duplicates. `ci.yml` is gone, and the `ci` badge points at `build.yml` — the same rename every sibling already carries
- `vendor-sync.yml` is vendored from the [ci](https://github.com/rokokol/ci-skill) skill like everywhere else. It could not be before: it needed a matrix over the runners, because `macos.yml` called `ci.yml` and `ci.yml` could not call it back. With the checks in `gate.yml` the recursion is gone, `build.yml` reaches macOS for a caller that hands it a ref, and the copy here is the template again
- `bump-cascade.yml` verifies through `build.yml` rather than its own matrix, for the same reason

### Added

- `check-prose.sh`, vendored from [create-readme](https://github.com/rokokol/create-readme-skill), and the gate runs it over every markdown this repository ships. Seven of its siblings already carried the copy and this one did not, so the house prose rules — a paragraph on one line, no full stop closing one, plain quotation marks — were decided nowhere here. The list is wider than the documents an agent loads: it covers the changelog and the workarounds, and `WORKAROUNDS.md` was outside every list the gate had

## 2026-09-15

### Changed

- the wrong tool name `references/reader.md` shows on purpose, `read_arXiv_paper`, is excused in `check-interface.allow`, which no agent loads, rather than by a `check-interface: allow` comment in the reference every reading subagent loaded; the vendored `check-interface.sh`, `check-skill.sh` and `check-changelog.sh` take their current revisions
- `check-skill.sh` is vendored from the [skill-authoring](https://github.com/rokokol/skill-authoring-skill) skill, where the rules it checks now live, and reports the rules a skill can break without breaking as warnings on stdout, the exit code unchanged: a `Layout` or install section in runtime, `used to`, a `path:line` citation, a link to a sibling skill, a concrete model id, and the rest its `--help` lists

## 2026-09-11

### Changed

- the corpus preset turns PaperQA2's doc details off (`parsing.use_doc_details`), so `pqa index` no longer asks the model for a structured citation of each paper or Semantic Scholar and Crossref for its metadata; `programs.papers.corpus.docDetails` turns it back on. With it on, one Semantic Scholar 429 ended the whole index with exit 1 and left the paper marked failed in that index for good; `references/paperqa.md` says how to spot such a paper and retry it
- the repository-wide workaround record follows the maintainer-document convention as `WORKAROUNDS.md` and is linked from a header badge
- the gate holds every document — `README.md` now included — to the packaged server through the ci skill's `check-interface.sh`, vendored: an MCP tool name anywhere, call notation, and a span that is wholly a tool name, each tool's arguments held to that tool's own. It replaces `tests/doc-args.py` and the tool-name grep, and also checks the bare tool names the identifier table uses
- `tests/mcp-tools.py` takes the reply that answers its own request rather than the first JSON line, so a notification the server volunteers is not read as the tool list, follows `nextCursor` to the last page, and stops a server that will not exit instead of dying on the timeout
- `programs.papers.corpus.extraSettings` is merged recursively, so setting one key of `answer` keeps the rest of it; enabling the corpus without `programs.papers.enable` is an assertion failure where it installed nothing in silence
- the description drops the citation triggers, which no mode serves, and gains the corpus mode's

### Removed

- `x86_64-darwin` from the flake's systems: the locked nixpkgs refuses to evaluate for Intel Macs, so its packages could never be built. `aarch64-darwin` stays, and is now built and checked on a macOS runner on every push and pull request
- the step in `references/sources.md` that fetched an arXiv paper's LaTeX source: the reading subagent is barred from WebFetch and the master from reading, so nobody could carry it out

### Fixed

- `search_papers` reports a Semantic Scholar refusal (rate limited, an HTTP error, a network error) under `errors["semantic"]` instead of answering zero results for it, and `search_semantic` fails instead of returning an empty list: the packaged `paper-search-mcp` carries the fix from openags/paper-search-mcp#111 until a release does, as `WORKAROUNDS.md` records
- **the readme's corpus snippet set the answering model to `ollama/qwen3.5:9b`** and called it the default, while the default is `ollama_chat/`, and `references/paperqa.md` shows the `ollama/` provider ending `ask` with "no papers". The snippet sets only the folder now
- **the source check could not catch a made-up source**: it kept only the backticked words the CLI lists, so a misspelt one fell out of the comparison unseen, and the sources that must have a read tool were a list kept in the gate that had already dropped `dblp`. The routing columns are read whole now and every word must be a source or a tool, and the read-tool check takes its sources from the reader prompt's `SOURCE` row
- the note mode moved a kept PDF into the vault's attachments, which took it out of the corpus folder it had been downloaded into; it copies now
- a `doi` or `title` placeholder written `unknown` could be passed to `download_with_fallback` as a real value; the prompt leaves such arguments out
- the corpus mode's "no evidence" was presented as absence, though each query reaches only the few papers one index search brings up (`searchCount`, 4 by default); `SKILL.md` and `references/paperqa.md` say so
- the module's comment on `PQA_HOME` had it as the `.pqa` directory itself, where PaperQA2 takes it as a root and appends `.pqa`
- counts written beside the lists they count — the server's tool total, the free keys, the settings `ask` needs, the reader's rungs — and the readme's promise that every check is proven able to fail, which the linters are not
- `WORKAROUNDS.md`'s removal check fails when the release has no `semantic.py`, where it printed the same 0 as an unfixed release

## 2026-09-10

### Added

- the `papers` skill: `search` turns a topic into a shortlist of identifiers with one line per paper, `read` turns an identifier into a digest of at most 450 words written by a reading subagent in its own context, `review` compares several digests, and `note` files one into the user's vault only when they say so, through a profile the vault's owner writes. The master never reads a PDF or a search result in bulk; that is what keeps a paper from costing a conversation's context
- `references/`: which source for which area and how identifiers map to the server's tools, the reading subagent's prompt word for word, the digest template with its bounds, the vault profile schema, and the corpus mode
- the `corpus` mode: a question across a folder of papers goes to PaperQA2 on local models. The flake carries PaperQA2 2026.8.12 as a locked environment built by uv2nix from `nix/paperqa/uv.lock`, since it is not in nixpkgs and pins litellm below what nixpkgs has, and exposes it as `packages.paper-qa`; the lock pins `fhlmi` and `fhaviary` to what PaperQA2's own lock names, because the newer `fhlmi` its metadata allows crashes the agent before its first call, and adds `pillow` and `fonttools`, which its PDF reader needs and does not declare. `programs.papers.corpus` installs it and writes the `pqa -s papers` preset for Ollama, with `qwen3.5:9b` answering and `bge-m3` embedding by default, text-only parsing, a model timeout long enough for the first GPU load, and two concurrent calls
- `pqa-evidence`, retrieval without the answer model: PaperQA2's paper search and evidence gathering with the contextual summaries off, so only the embedding model runs and the passages come back untouched for the agent to reason over. It is the corpus mode's default; `pqa ask` is the option that spares the conversation's context, and the preset makes it work on a local model: the `ollama_chat/` provider, which carries the tool calls every PaperQA2 agent ends on, thinking off, text summary prompts instead of JSON, and a smaller evidence budget, measured at 44 s per question on `qwen3.5:9b`
- the profile installs a wrapper over the PaperQA2 environment rather than the environment itself: a whole site-packages in a Home Manager profile collides with any other Python environment there on the files they share
- `paper-search-mcp` 0.1.4 packaged from PyPI in `nix/package.nix`, built against nixpkgs' mcp 1.x, which is what keeps the server importable: upstream leaves the SDK unbounded and breaks under 2.x. The unused `fastmcp` requirement is dropped. The flake exposes the package, an overlay, and a Home Manager module with `programs.papers.enable` and `programs.papers.envFile`, which points both binaries at an env file a secret store renders
- `check.sh`, the gate: lint, the vendored skill, pin and changelog checkers, and two checks that tie the documents to the packaged server — every `mcp__paper-search__*` tool the documents name exists in the server's tool list, and every source name in `references/sources.md` is one the CLI lists — each proven able to fail on a planted defect
