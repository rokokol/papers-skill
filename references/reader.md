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

How to get the text, in this order, stopping at the first that yields the full text:
1. Run ToolSearch with "+paper-search" to load the MCP tools, then call mcp__paper-search__read_SOURCE_paper with paper_id PAPER_ID and save_path SAVE_PATH
2. If that fails or returns only an abstract, call mcp__paper-search__download_with_fallback with source SOURCE, paper_id PAPER_ID, doi DOI, title TITLE, save_path SAVE_PATH, then open the PDF it saved with the Read tool
3. If the MCP tools are not available, run `paper-search read SOURCE PAPER_ID -o SAVE_PATH` in Bash
If every step yields only the abstract, write the digest from the abstract and say so in the last field.

Rules:
- Return the digest and nothing else: no raw text, no outline, no quotation longer than one sentence
- Every number in the digest comes from the paper; when the paper gives none, say "no numbers reported" rather than estimating
- Distinguish what the paper claims from what it shows; a result on one benchmark is not a general claim
- Name the limitations the authors admit and, separately, the ones they do not
- Keep the whole digest under 450 words
```

## Filling the placeholders

| Placeholder | Value |
|---|---|
| `IDENTIFIER` | what the user wrote, verbatim |
| `SOURCE`, `PAPER_ID` | from the identifier table in [sources.md](sources.md#identifiers); the tool name is `read_arxiv_paper`, `read_pubmed_paper`, and so on |
| `DOI`, `TITLE` | when known from a shortlist or a Crossref lookup, else omit the arguments |
| `QUESTION` | the user's question in their words; "summarise it" is a valid question |
| `SAVE_PATH` | `~/.cache/papers/` expanded to an absolute path |
| `TEMPLATE_PATH` | the absolute path of `references/digest-template.md` in this skill's directory |
| `LANGUAGE` | the language of the conversation |

## What comes back

The subagent's final message is the digest. The master shows it as received, adds its own reading in one or two paragraphs, and moves to `note` or `review`. A final message that is not in the template's shape, or exceeds its bound, is a failed read: say so and spawn again with the same prompt rather than editing the digest into shape yourself.
