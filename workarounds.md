# Workarounds

Things in this repository that exist only because something upstream is broken or missing. Each entry says what to run to find out whether it is still needed, and what makes it removable. Deliberate choices live in the module or reference they belong to, not on this list

Rules for this file: one entry per workaround, and every entry carries a mechanical removal check, a command whose output decides it, never a date

---

## Semantic Scholar failures patched into `paper-search-mcp`

**Where:** `nix/package.nix`, `patches`: a `fetchpatch` of the commit behind [openags/paper-search-mcp#111](https://github.com/openags/paper-search-mcp/pull/111), limited to `paper_search_mcp/`, so the tests it also touches, which the PyPI release does not ship, stay out

**Symptom it prevents:** `search_papers` with `semantic` among its sources answers `"semantic": 0` and an empty `errors` map when Semantic Scholar refused the request (rate limited after every retry, an HTTP error, a network error), which is the same answer as a query that matched nothing. The anonymous pool is throttled at busy hours, so without the patch a zero from `semantic` says nothing. With it, the refusal lands in `errors["semantic"]`, and `search_semantic` fails as a tool call instead of returning an empty list

**Why it happens:** `SemanticSearcher.request_api()` does tell the failures apart, and `search()` logs the failure and returns `[]`; `search_papers` records a source's error only when its searcher raises

**Reported:** [openags/paper-search-mcp#111](https://github.com/openags/paper-search-mcp/pull/111), open

**Removal check:**

```sh
# non-zero once the latest PyPI release ships the fix: then bump version and hash in
# nix/package.nix to that release, and drop patches and this entry
v=$(curl -s https://pypi.org/pypi/paper-search-mcp/json | jq -r .info.version)
curl -sL "$(curl -s "https://pypi.org/pypi/paper-search-mcp/$v/json" | jq -r '.urls[] | select(.packagetype == "sdist") | .url')" \
  | tar -xzO --wildcards '*/academic_platforms/semantic.py' | grep -c SemanticScholarRequestError
```
