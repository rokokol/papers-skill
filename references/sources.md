# Sources

What paper-search-mcp can reach, which of it to use for which question, and where it fails quietly. The server's own tool list is the authority on names and arguments; this file is about choosing

## Sources by area

`search_papers` takes `sources` as one comma-separated string (`"arxiv,semantic"`, or `"all"`) and a `max_results_per_source`. Start with the primary pair for the area, add one secondary only when the primary returned nothing useful; never fan out across every source because it is available

| Area | Primary | Secondary | Notes |
|---|---|---|---|
| Computer science, machine learning, speech | `arxiv`, `semantic` | `openalex`, `dblp` | arXiv holds the preprint of almost every ML paper; Semantic Scholar adds citations and venues; dblp is the venue record for conferences |
| Agent systems, LLM applications | `arxiv`, `semantic` | `openalex` | The field moves on arXiv months before venues; sort arXiv by date when recency matters |
| Networking, systems, HPC | `arxiv`, `dblp` | `semantic`, `openalex` | Much of it is in IEEE and ACM venues that are paywalled; dblp finds the record, Unpaywall finds a copy |
| Biology, medicine | `pubmed`, `europepmc` | `biorxiv`, `medrxiv`, `pmc` | PubMed is the index, Europe PMC and PMC hold full text; the preprint servers cover the last year |
| Psychology, cognitive science | `openalex`, `semantic` | `pubmed` | No free index owns the field; OpenAlex has the widest coverage of its journals, PubMed the clinical side |
| Anything else | `openalex`, `semantic` | `crossref` | OpenAlex is the broadest open index; Crossref resolves a DOI to its record |

Per-source tools (`search_arxiv`, `search_pubmed`, `search_semantic`, …) exist for when one source needs its own parameters: `search_arxiv` sorts by relevance or date, `search_semantic` and `search_papers` filter by `year`, `search_crossref` takes a filter string

## Identifiers

The `read` mode needs a source and a `paper_id` in that source's form. Resolve before spawning the reader:

| The user gives | Source | `paper_id` |
|---|---|---|
| `2212.04356`, `2212.04356v3`, an arxiv.org URL | `arxiv` | the id without the `arXiv:` prefix; a version suffix is allowed |
| `10.xxxx/...`, a doi.org URL | `crossref`, then `semantic` | the DOI; `get_crossref_paper_by_doi` gives the record, `read_crossref_paper` or `read_semantic_paper` the text |
| a PMID (digits), a pubmed.ncbi.nlm.nih.gov URL | `pubmed` | the PMID; `read_pubmed_paper` fetches the PMC full text when there is one |
| a PMC id (`PMC1234567`), a Europe PMC URL | `pubmed` | the PMID of the same article, found with `search_pubmed` on the PMC id; `pmc` and `europepmc` are search-only in the server, they have no `read_` tool |
| a bioRxiv or medRxiv DOI (`10.1101/...`) | `biorxiv` or `medrxiv` | the DOI |
| a Semantic Scholar id (40 hex characters) or URL | `semantic` | the id |
| a title from a shortlist | the source that listed it | the `paper_id` from that result |
| a title with no identifier | `search_papers` first | never guess an id from a title |

A paper reachable by several identifiers is read once, through the source most likely to hold its full text: arXiv for anything with an arXiv id, PubMed for anything biomedical, since its read tool pulls the PMC copy when one exists, Crossref plus Unpaywall for the rest. Not every source that can be searched can be read: the server has `read_<source>_paper` for arxiv, pubmed, biorxiv, medrxiv, semantic, crossref, openalex, dblp and the open repositories, and none for pmc, europepmc, core or google_scholar

## Full text

`read_<source>_paper(paper_id, save_path)` downloads and extracts the text in one call and returns it as the tool result, which is why only the reading subagent calls it. When it fails or returns a stub:

1. `download_with_fallback(source, paper_id, doi, title, save_path)` tries the source, open repositories, Unpaywall, and then Sci-Hub when `use_scihub` is left on; pass the DOI and the title so the fallbacks have something to match. The Sci-Hub step is upstream's default and a choice for the owner of the installation, not for this skill; set `use_scihub: false` when the user says so
2. The PDF at `save_path` is read with the `Read` tool, in the subagent
3. For arXiv papers whose extraction is poor, the LaTeX source at `https://arxiv.org/e-print/<id>` is exact; fetch it only when the PDF text is unusable

## Keys and limits

Keys are optional, free, and read by the server from an env file; the variable names carry the `PAPER_SEARCH_MCP_` prefix and the unprefixed legacy names still work

| Variable | Source | Without it |
|---|---|---|
| `PAPER_SEARCH_MCP_SEMANTIC_SCHOLAR_API_KEY` | Semantic Scholar | one anonymous pool shared by everyone, throttled at busy hours; a rejected key falls back to anonymous automatically |
| `PAPER_SEARCH_MCP_CORE_API_KEY` | CORE | frequent 500s and timeouts |
| `PAPER_SEARCH_MCP_UNPAYWALL_EMAIL` | Unpaywall | the Unpaywall step of `download_with_fallback` is skipped entirely |
| `PAPER_SEARCH_MCP_DOAJ_API_KEY` | DOAJ | 100 requests per hour |
| `PAPER_SEARCH_MCP_IEEE_API_KEY`, `PAPER_SEARCH_MCP_ACM_API_KEY` | IEEE Xplore, ACM | the connector stays off; both are skeletons upstream that search but cannot download |

The services' own rules still apply behind the server: arXiv asks for one request every three seconds on a single connection; PubMed allows three requests per second without a key; OpenAlex and Crossref give a faster pool to requests that carry an email. A search that returns a rate-limit error is retried once after a pause, never in a loop

## Known pitfalls

- **arXiv hangs on multi-word queries without quotes** (upstream #101): quote a phrase, or search Semantic Scholar first and read from arXiv by id
- **Google Scholar is a scraper** with roughly ten queries per session before it blocks (#74); it is never the first source and never the only one
- **`download_with_fallback` reaches Sci-Hub by default** (#103); say so when reporting where a PDF came from. In practice that rung yields nothing: the mirror the server assumes, sci-hub.se, no longer resolves, and the mirrors that answer put a captcha in front of every DOI page, which the scraper cannot pass (measured 2026-09-10). What actually finds a paywalled paper's copy is the open-repository rung, and it matches on `title`, so pass the title, never an empty string
- **The server crashes at startup under mcp SDK 2.x** (#107) when installed from PyPI without a pin; the packaged binary in this repository is built against the 1.x SDK and does not
- **A `read_*` result can be an abstract**: PubMed without PMC access, Crossref for a paywalled journal, SSRN. The digest's last field exists to say so
- **The default `save_path` is `./downloads`**, relative to the process's working directory; always pass one
