# Digest template

The shape every reading subagent returns and every note is built from. Field names stay in English so the master can check them; the content is in the language of the conversation. The whole digest is at most 450 words; a field with nothing to say holds one short sentence saying so, never nothing.

```
## <Title as printed>

**Authors** — first author et al. (n authors), year, venue or preprint server
**Identifiers** — arXiv / DOI / PMID as available, one line
**TL;DR** — two sentences: what was done and what came out

**Question** — the problem the paper sets itself, in one or two sentences
**Method** — how it is approached: the model, the design, the analysis, the intervention; name the one idea a reader must keep
**Data** — datasets, subjects or corpora, with sizes; the baselines or controls
**Results** — the main findings with the numbers as reported (metric, value, comparison); three to five lines
**Limitations** — what the authors admit, then what they do not: scope, data, missing baselines, unreported variance
**For the question** — what this paper contributes to the question given in the prompt, and what it cannot settle
**Worth following** — up to five references the paper leans on, as identifiers or exact titles
**Read** — one of: full text; abstract only; extraction truncated after section N; and the source used
```

## Bounds and checks the master applies

- Every field of the template, in its order, none omitted
- Under 450 words in total; a digest that runs over was written by summarising the text instead of answering the fields
- **Results** carries numbers or the words "no numbers reported"; a results field made of adjectives is a failed read
- **Read** names what was actually read; a digest whose last field is missing is treated as abstract-only
- No quotation longer than one sentence, no section-by-section outline, no raw text
