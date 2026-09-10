# A corpus: when PaperQA2 earns its place

A reading subagent answers questions about one paper at a time. When the question spans a folder of papers ("across everything I have on X, what evidence supports Y"), that is retrieval over a corpus, and the tool for it is [PaperQA2](https://github.com/Future-House/paper-qa): it indexes a directory of PDFs, retrieves the passages that bear on a question, summarises each with its own model calls, and answers with citations to the passages. It is not implemented in this version of the skill; this page records what it would take, so the decision can be made when the corpus exists.

## When it is worth it

- Twenty or more papers on one topic already sit in a folder, and the questions keep coming back to the same set
- The questions are about evidence across papers, not about one paper's method
- Before that point, `review` over a handful of digests answers faster and with no setup

## What it costs

- PaperQA2 makes its own LLM and embedding calls through LiteLLM; by default that is OpenAI. It runs on Anthropic models with an API key billed per token, or locally through Ollama plus a sentence-transformers embedding model, at lower quality and with a GPU strongly advised
- An index per corpus, rebuilt when papers are added; the `pqa index` command keeps it
- It is a Python application (`pip install paper-qa`, the `pqa` command); it is not in nixpkgs, so a Nix consumer packages it the way `nix/package.nix` packages the search server

## How it would be wired

A `corpus` mode in this skill would run `pqa -i <name> ask "<question>"` in Bash with the settings preset that names the local models, and return the answer with its citations; the answer is already bounded, so it can run in the master. A settings preset for Ollama, kept where `pqa` looks for them:

```
llm: ollama/<model>
summary_llm: ollama/<model>
embedding: st-<sentence-transformers model>
```

The exact keys follow PaperQA2's `Settings`; check its README for the current names before writing the preset, since they have changed between major versions.
