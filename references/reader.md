# The reading subagent

The master spawns it with the `Agent` tool, `subagent_type: general-purpose`, an explicit `model` (`sonnet` unless the user named another), and the prompt below with the placeholders filled. One paper per subagent; a review spawns several, one at a time by default.

## Prompt

```
Read one scientific paper and return a digest. Do not spawn subagents. Do not write anywhere except SAVE_PATH.

Paper: IDENTIFIER (source: SOURCE, paper_id: PAPER_ID)
The user's question, which the digest must answer where the paper allows: QUESTION
Save path for downloads: SAVE_PATH
Digest template, read it first and follow its fields and bounds exactly: TEMPLATE_PATH
Language of the digest: LANGUAGE

Obtain the text with the ladder below. Stop at the first rung that yields the full text; a rung that errors or returns only an abstract hands over to the next.
1. Load the tools by exact name: ToolSearch with query "select:mcp__paper-search__read_SOURCE_paper,mcp__paper-search__download_with_fallback" and max_results 2. Then call mcp__paper-search__read_SOURCE_paper with paper_id PAPER_ID and save_path SAVE_PATH
2. Call mcp__paper-search__download_with_fallback with source SOURCE, paper_id PAPER_ID, save_path SAVE_PATH, use_scihub USE_SCIHUB, and doi and title when they are given below; then open the PDF it saved with the Read tool
3. Only when ToolSearch found no paper-search tools at all: run `paper-search read SOURCE PAPER_ID -o SAVE_PATH` in Bash and read its output
If a rung yielded only the abstract and the rest yielded nothing, write the digest from the abstract and say so in the last field. If every rung errored and no text at all was obtained, return only one line, "could not read PAPER_ID: <the last error>", and nothing else.
DOI: DOI
Title: TITLE

Rules:
- Use only the paper-search tools and the Read tool on the file they saved. WebFetch, WebSearch and any browser tool are off limits: a digest built from an abstract page is indistinguishable in shape from one built from the paper
- Return the digest and nothing else: no raw text, no outline, no quotation longer than one sentence
- Every number in the digest comes from the paper; when the paper gives none, say "no numbers reported" rather than estimating
- Distinguish what the paper claims from what it shows; a result on one benchmark is not a general claim
- Name the limitations the authors admit and, separately, the ones they do not
- Keep the whole digest within the template's bound
```

## Filling the placeholders

| Placeholder | Value |
|---|---|
| `IDENTIFIER` | what the user wrote, verbatim |
| `SOURCE` | the server's lowercase source name from the identifier table in [sources.md](sources.md#identifiers): `arxiv`, `pubmed`, `biorxiv`, `medrxiv`, `semantic`, `crossref`, `openalex`, `dblp`; never the user's spelling, since `read_arXiv_paper` is not a tool |
| `PAPER_ID` | the id in that source's form, from the same table |
| `DOI`, `TITLE` | when known from a shortlist or a Crossref lookup; write `unknown` otherwise, and the subagent leaves the arguments out |
| `USE_SCIHUB` | `false` when the user has said so, `true` otherwise, which is upstream's default |
| `QUESTION` | the user's question in their words; "summarise it" is a valid question |
| `SAVE_PATH` | `~/.cache/papers/` expanded to an absolute path |
| `TEMPLATE_PATH` | the absolute path of `references/digest-template.md` in this skill's directory |
| `LANGUAGE` | the language of the conversation |

## A paper the user already has

A local PDF or a path skips the ladder: the prompt keeps every line but replaces the three rungs with "Open FILE_PATH with the Read tool" and the identifier line with the path. The digest's last field then names the file as the source.

## What comes back

The subagent's final message is the digest, or the one-line failure. The master shows a digest as received, adds its own reading in one or two paragraphs, and moves to `note` or `review`. A final message that is not in the template's shape, or over its bound, is a failed read: say so and spawn once more with the same prompt plus the failure named ("the previous attempt exceeded the bound", "the previous attempt omitted the Read field"); after a second failure, report it instead of a third attempt, and never edit the digest into shape yourself. A failure line is shown as such and is never turned into a digest from memory.
