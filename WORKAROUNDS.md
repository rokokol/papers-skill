# Workarounds

Things in this repository that exist only because something upstream is broken or missing. Each entry says what to run to find out whether it is still needed, and what makes it removable. A permanent choice that differs from the obvious route belongs in a `DEVIATIONS.md`, not on this list

Rules for this file: one entry per workaround, and every entry carries a mechanical removal check, a command whose output decides it, never a date

---

## Semantic Scholar failures patched into `paper-search-mcp`

**Where:** `nix/package.nix`, `patches`: a `fetchpatch` of the commit behind [openags/paper-search-mcp#115](https://github.com/openags/paper-search-mcp/pull/115), limited to `paper_search_mcp/`, so the tests it also touches, which the PyPI release does not ship, stay out. The install without Nix in the README takes the PyPI release as it is, so it answers zero for a refusal until a release carries the fix

**Symptom it prevents:** `search_papers` with `semantic` among its sources answers `"semantic": 0` and an empty `errors` map when Semantic Scholar refused the request (rate limited after every retry, an HTTP error, a network error), which is the same answer as a query that matched nothing. The anonymous pool is throttled at busy hours, so without the patch a zero from `semantic` says nothing. With it, the refusal lands in `errors["semantic"]`, and `search_semantic` fails as a tool call instead of returning an empty list

**Why it happens:** `SemanticSearcher.request_api()` does tell the failures apart, and `search()` logs the failure and returns `[]`; `search_papers` records a source's error only when its searcher raises

**Removal check:**

```sh
# prints a count above 0 once the latest PyPI release ships the fix: then bump version and
# hash in nix/package.nix to that release, and drop patches and this entry. It fails
# rather than printing 0 when the sdist has no semantic.py, since a renamed module is not
# the same answer as an unfixed one
# (Python rather than jq and tar: GNU tar needs --wildcards here, and bsdtar rejects it)
v=$(curl -s https://pypi.org/pypi/paper-search-mcp/json | python3 -c 'import json, sys; print(json.load(sys.stdin)["info"]["version"])')
curl -s "https://pypi.org/pypi/paper-search-mcp/$v/json" \
  | python3 -c 'import json, sys; print(next(u["url"] for u in json.load(sys.stdin)["urls"] if u["packagetype"] == "sdist"))' \
  | xargs curl -sL \
  | python3 -c 'import sys, tarfile; t = tarfile.open(fileobj=sys.stdin.buffer, mode="r|gz"); c = [t.extractfile(m).read().count(b"SemanticScholarRequestError") for m in t if m.name.endswith("/academic_platforms/semantic.py")]; sys.exit("no academic_platforms/semantic.py in the sdist") if not c else print(sum(c))'
```

**Upstream:** [openags/paper-search-mcp#115](https://github.com/openags/paper-search-mcp/pull/115), merged

---

## PMC full text read by `tools/pmc_text.py`, not by the server

**Where:** `tools/pmc_text.py` and `tests/test_pmc_text.py`; the first rung of the ladder and the `PMC_ID` and `PMC_TEXT` placeholders in `references/reader.md`; the PMC paragraph of "Full text" in `references/sources.md`; the reading subagent's bullet in `SKILL.md`

**Symptom it prevents:** a biomedical paper with an open-access copy in PMC is digested from its abstract, or not at all. `read_pubmed_paper` returns a fixed note that PubMed has no text. The server's `pmc` and `europepmc` downloads ask `https://www.ncbi.nlm.nih.gov/pmc/articles/<PMCID>/pdf/` and Europe PMC's `?pdf=render` link, and both answer with HTML: a bot check with status 200, and a 403

**Why it happens:** `PubMedSearcher.read_paper()` returns its message without a request. PMC's article pages are for a browser, and PMC publishes its open-access articles for programs as a separate dataset on AWS, `pmc-oa-opendata`, which the server does not use

**Removal check:**

```sh
# prints a byte count far above the 207 of the note once the server reads PubMed through
# PMC: then drop tools/pmc_text.py, its test and its gate step, the ladder's first rung
# and its placeholders, and this entry. PMID 32015507 is an open-access article in PMC
nix develop -c paper-search read pubmed 32015507 -o "$(mktemp -d)" 2>/dev/null | wc -c
```

**Upstream:** [openags/paper-search-mcp#151](https://github.com/openags/paper-search-mcp/pull/151), open: the server reads PubMed, PMC and Europe PMC through the same dataset
