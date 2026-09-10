---
name: papers
description: "Find, read and compare scientific papers without spending the conversation's context on them: a shortlist of identifiers for a topic, a bounded digest of one paper by a reading subagent, a comparison of several, and a note in the user's vault only when they say so. Sources: the paper-search MCP server or its CLI (arXiv, PubMed, Semantic Scholar, OpenAlex, Crossref and more). Use when the user asks to find papers on a topic, look up a DOI or arXiv id, summarise or critique a scientific article, compare papers, or write a literature note. Not for a web page, a blog post or a news article, which is a plain fetch. Triggers: papers, paper, preprint, arXiv, DOI, PubMed, literature review, systematic review, meta-analysis, related work, citations, who cites this, state of the art, what does the research say, научные статьи, найди статьи, препринт, обзор литературы, мета-анализ, литература по теме, найди источники, есть ли работы про, что говорят исследования, разбери статью, конспект научной статьи, сравни статьи"
license: MIT
---

# papers

Scientific papers are long and PDFs are worse: the text of one paper is a large fraction of a conversation's context, and a survey is several of them. This skill keeps the reading out of the main conversation. The master finds and decides; a subagent with its own context reads and returns a digest of bounded length; the master synthesises across digests and, only when the user says so, files one as a note.

## Setup

- **Sources** come from [paper-search-mcp](https://github.com/openags/paper-search-mcp) in one of two forms. As an MCP server registered under a name (assumed `paper-search` below) its tools are `mcp__paper-search__*`; they are deferred, so before the first call run `ToolSearch` with `select:` and the exact names about to be called, in the subagent as well as in the master: the server has 57 tools and a keyword query returns only the first few, so the one needed is often not among them. As a CLI, `paper-search search|download|read|sources` prints JSON or text. Prefer the MCP where it is registered: `download_with_fallback` and the per-source `read_*_paper` tools exist only there. Check availability once per session: `ToolSearch` finds the tools, or `command -v paper-search` finds the binary; neither means stop and point at [README.md](README.md)
- **Keys** are optional and never pass through the conversation: the server reads an env file named by `PAPER_SEARCH_MCP_ENV_FILE` or `~/.config/paper-search-mcp/.env`. Without them Semantic Scholar shares an anonymous rate limit, CORE fails often and Unpaywall is skipped, which is the legal open-access fallback; [references/sources.md](references/sources.md#keys-and-limits) names the variables
- **Downloads** go to one place, `~/.cache/papers/`, passed as `save_path` on every call; the default `./downloads` litters whatever directory the session happens to be in
- **Subagents** always get an explicit `model`, `sonnet` unless the user names another, and are told not to spawn subagents of their own. Reading is delegated; judgement is not

## Modes

Say which mode you are in. A request usually chains them: `search` → `read` → `note`, or `search` → `review`.

**search** — a topic, optional constraints (years, field, open access), and the user's actual question. Pick the sources by area from [references/sources.md](references/sources.md#sources-by-area); default to `search_papers` with two or three sources and `max_results_per_source` of 5. When the sweep is that narrow, run it in the master. When it is wider, or the user wants exhaustiveness, delegate to a scout subagent that runs the searches and returns at most ten candidates as `identifier, source, title, year, venue, one line why` and nothing else; the master never receives abstracts in bulk. Present the shortlist as a table with identifiers the next mode can act on, and say which sources answered and which returned nothing. Nothing found is a result, not a failure.

**read** — one identifier: an arXiv id, a DOI, a PMID, a URL, a title from a previous shortlist, or a PDF the user already has. Resolve the source and id with the table in [references/sources.md](references/sources.md#identifiers), a local file needs no resolution, then spawn one reading subagent with the prompt in [references/reader.md](references/reader.md): it obtains the text, reads it, and returns a digest in the shape of [references/digest-template.md](references/digest-template.md), within the template's bound, in the language of the conversation. Show the digest as received, add your own reading of what it means for the user's question, then offer `note`. If the subagent reports that only the abstract was reachable, or that nothing was, say so before anything else.

**review** — several identifiers or a shortlist. One reading subagent per paper, one at a time; up to three in parallel only when the user asks for speed, since the sources rate-limit and the subagent cap is small. Then synthesise in the master from the digests alone: a comparison table on the axes the user's question implies, agreements, contradictions, and the gaps, each claim tied to an identifier. Do not re-read a paper to settle a contradiction; spawn a reading subagent with the specific question instead.

**note** — after a digest or a review, ask once whether to save it; never write into a vault unasked. On yes, read `$OBSIDIAN_VAULT_PATH/.claude/papers/profile.yml` ([references/profile.md](references/profile.md)): it names the vault's style skill, the preset and the folder, and the note is written through that skill in its language, never in a shape invented here. Without a profile, ask for a path and write plain Markdown with the digest under a frontmatter of `title`, `doi`, `arxiv`, `url`, `authors`, `year`, `venue`, `created`. Keep the PDF only when the profile names an attachments folder.

A folder of papers with questions across all of them at once is retrieval over a corpus, which no mode here does; [docs/paperqa.md](docs/paperqa.md) records when PaperQA2 would earn its setup. Until then, `review` over a handful of digests is the answer.

## The reading subagent

One paper, one subagent, one digest. The contract is what makes the mode cheap, so it is not softened:

- The subagent gets the identifier, the user's question, the save path, the path of the digest template, and the rules in [references/reader.md](references/reader.md); it reads the template itself
- It calls `read_<source>_paper` first; when that fails it calls `download_with_fallback` and reads the PDF with the `Read` tool; when the CLI is the only path it runs `paper-search read <source> <id> -o <save_path>`
- It returns the digest and nothing else: no raw text, no quotes longer than a sentence, no table of contents. The one exception is a single sentence naming what it could not read
- It states, in the digest's last field, what it actually read: full text, or abstract only, or a truncated extraction
- It never spawns subagents, never writes outside the save path, never touches the vault

## Never

- Read a PDF, call `read_*_paper`, `download_*`, or `paper-search read` in the master; that is the whole point of the reading subagent
- Paste abstracts or full search results into the conversation; a shortlist is identifiers plus one line each
- Put an API key into a prompt, a command line, or a note
- Present a digest as the paper's claim without saying what the subagent actually read, or turn a failure line into a digest from memory
- Go to Google Scholar first: it is a scraper with a session limit, and every source it knows is covered elsewhere ([sources.md](references/sources.md#known-pitfalls))
- Invent a reference; every identifier in a report came from a tool result

## Before the report

- The mode was named, and the user's actual question shaped the search or the digest, not just the topic
- Every identifier came from a tool result and is spelled so the next mode can use it
- Each digest says what the subagent read, and a partial read is stated first
- The synthesis of a review cites identifiers per claim and names the contradictions instead of averaging them
- The note question was asked once, and the note went through the profile's style skill

## Which reference when

| Question | Read |
|---|---|
| Which source for which area, how identifiers map to tools, keys, limits and the server's known traps | [references/sources.md](references/sources.md) |
| What to tell the reading subagent, word for word | [references/reader.md](references/reader.md) |
| The digest's fields and bounds | [references/digest-template.md](references/digest-template.md) |
| The profile a vault owner writes so notes land in their style and folder | [references/profile.md](references/profile.md) |

## Layout

```
SKILL.md              this file — setup, modes, the subagent contract, the never list
references/           sources, reader prompt, digest template, profile schema
docs/                 design notes for people, such as when PaperQA2 would earn its setup
nix/                  the paper-search-mcp package and its Home Manager module
flake.nix             packages, the module, the dev shell and checks
check.sh              this repo's own gate
```

Installation, the MCP registration, the Nix module and the profile format live in [README.md](README.md), which is written for people; nothing there is needed while searching or reading.
