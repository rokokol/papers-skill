# The corpus mode: PaperQA2 on local models

A reading subagent answers questions about one paper. When the question spans a folder of papers at once, that is retrieval over a corpus, and [PaperQA2](https://github.com/Future-House/paper-qa) does it: it indexes the folder, embeds its chunks, retrieves the passages that bear on a question, summarises each with its own model calls, and answers with citations to the passages. This repository ships it as a locked environment (`nix/paperqa/`, the `pqa` command) and a settings preset for Ollama, so nothing leaves the machine and nothing is billed per token.

## When it beats review

- The folder holds a dozen or more papers on the topic, and the questions keep coming back to the same set
- The question is about evidence across papers ("which of these measured X", "what supports Y"), not about one paper's method
- Below that, `review` over a handful of digests answers faster and with no index to build

## The preset

`pqa -s papers` reads `~/.pqa/settings/papers.json`; the Home Manager module writes it from `programs.papers.corpus`, so the file is generated, never edited by hand. Its shape, with the defaults the module uses:

```json
{
  "llm": "ollama_chat/qwen3.5:9b",
  "llm_config": { "model_list": [ { "model_name": "ollama_chat/qwen3.5:9b", "litellm_params": { "model": "ollama_chat/qwen3.5:9b", "api_base": "http://localhost:11434", "timeout": 600, "think": false } } ] },
  "summary_llm": "ollama_chat/qwen3.5:9b",
  "summary_llm_config": { "model_list": [ "…the same route…" ] },
  "embedding": "ollama/bge-m3",
  "embedding_config": { "kwargs": { "api_base": "http://localhost:11434" } },
  "prompts": { "use_json": false },
  "answer": { "max_concurrent_requests": 2, "evidence_k": 5, "answer_max_sources": 3 },
  "parsing": { "multimodal": 0, "use_doc_details": false, "enrichment_llm": "ollama_chat/qwen3.5:9b", "enrichment_llm_config": { "model_list": [ "…the same route…" ] } },
  "agent": {
    "agent_llm": "ollama_chat/qwen3.5:9b",
    "agent_llm_config": { "model_list": [ "…the same route…" ] },
    "search_count": 4,
    "index": { "paper_directory": "/home/me/.cache/papers" }
  }
}
```

Without the module, write the same file by hand at that path, or under another `HOME`-like root named by `PQA_HOME`. Both Ollama models must be pulled before the first run: `ollama pull qwen3.5:9b` and `ollama pull bge-m3`. The `timeout` matters: litellm's default of 60 seconds is shorter than Ollama loading a 9B model into the GPU on the first call, and that first call fails the whole index (measured 2026-09-10). The concurrency matters for the same reason: Ollama serves one model, so four parallel requests only queue behind each other until the timeout. `parsing.multimodal` at 0 keeps indexing to text: the default parses every figure and table and asks the model for a caption of each, which on a local model turns one paper into ten minutes of GPU time and adds nothing to text retrieval. `parsing.use_doc_details` off keeps indexing off the network: on, PaperQA2 asks the model for a structured citation of each paper and then Semantic Scholar and Crossref for its metadata, and an anonymous Semantic Scholar 429 there ended the whole index with exit 1 (measured 2026-09-11); retrieval needs the text and the embeddings, and the citation the model reads off the first chunk stays either way. `pqa ask` on a local model took three settings to get right, and the module carries all three. Every PaperQA2 agent ends a turn by forcing a tool call, and litellm's `ollama/` provider speaks to Ollama's generate endpoint, which has no tool calls: the model answers with an empty message and `ask` finishes with "no papers" (measured 2026-09-10: 12 s with the default agent, 80 s with `fake`). The `ollama_chat/` provider speaks to the chat endpoint and the tool calls arrive; with it the same question ran to the evidence stage in 22 minutes and then failed on the JSON summary prompt, where a 9B reasoning model returned the summary with the score missing. Text prompts (`prompts.use_json` off), `think` off in the route, and a smaller evidence budget brought the same question to a correct cited answer in 44 s. Embeddings stay on `ollama/`, the provider litellm embeds through.

## Which models

- **Embedding**: `bge-m3` is multilingual, so a corpus that mixes English papers with Russian notes or questions in Russian still retrieves well; that is why it is the default here. `nomic-embed-text` is a quarter of the size and English-only, fine for a corpus that is all English and questions that are too. `mxbai-embed-large` sits between them in size and scores a little above `nomic` on English benchmarks
- **LLM**: PaperQA2's own README warns that 7B-class models follow its many-step instructions poorly. `qwen3.5:9b` fits a 12 GB GPU whole and is the smallest that answers reliably; a larger model such as `gemma4:26b` answers better and several times slower once it spills into RAM. Change `programs.papers.corpus.llm` rather than the file

## Commands

```sh
pqa -s papers index ~/.cache/papers                  # build or refresh the index; run after adding PDFs
pqa-evidence -s papers -k 8 "word error rate against human transcribers"   # the passages, no answer model
pqa -s papers ask "which of these papers measured word error rate against humans"
pqa -s papers search "weak supervision"              # which papers in the index match; no passages
```

`pqa-evidence` is this repository's own script (`tools/evidence.py`, run by the environment's interpreter): PaperQA2's paper search over the index, then its evidence gathering with the contextual summaries switched off, so the only model that runs is the embedding model and the passages come back in seconds, untouched. In the skill it is the default: the master writes the synthesis, since retrieval is where a local model is as good as any and synthesis is where it is not. `ask` spends the local model on the per-passage summaries and the final answer and returns one cited paragraph; it is the economy option for when the conversation's context is to be spared, and the preset below is what makes it work on a local model. `pqa search` is a different thing from both: a keyword search over the index that names papers, not passages.

The index lives under `~/.pqa/indexes/` and is keyed by a hash of the settings that shape the chunks (the folder, the embedding model, the chunking, `multimodal`): a changed embedding model means a rebuilt index, a changed LLM or `use_doc_details` reuses the old one. Adding papers is dropping PDFs into the folder and running `index` again; the folder is the same one the reading subagent downloads into, so a paper read once is in the corpus already.

## Limits

- Everything PaperQA2 knows comes from the folder: a question about a paper not in it gets an honest "no evidence", not a search
- A local 9B model summarises well and reasons less well; when the answer hinges on a subtle comparison, read the two papers with `read` and decide in the master
- The first `index` over a large folder is slow: every chunk is embedded once, on the GPU
- A file that fails to index is marked `ERROR` in the index, logged once as "Error parsing … skipping index for this file", and skipped without a word by every later `index` into the same index, even when the failure was a passing rate limit. A paper that is in the folder but never answers is the sign; trash that index's directory under `~/.pqa/indexes/` and index again to retry it. The index names are hashes, so this lists every file marked failed and the index it sits in, looking where PaperQA2 does, under `PQA_HOME` when it is set (the map is a zlib-compressed pickle of plain strings, so any Python 3 reads it):

  ```sh
  python3 -c 'import os, pathlib, pickle, zlib; root = pathlib.Path(os.environ.get("PQA_HOME") or pathlib.Path.home()) / ".pqa" / "indexes"; [print(z.parent.name, f) for z in sorted(root.glob("*/files.zip")) for f, h in pickle.loads(zlib.decompress(z.read_bytes())).items() if h == "ERROR"]'
  ```
