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
  "llm": "ollama/qwen3.5:9b",
  "llm_config": { "model_list": [ { "model_name": "ollama/qwen3.5:9b", "litellm_params": { "model": "ollama/qwen3.5:9b", "api_base": "http://localhost:11434", "timeout": 600 } } ] },
  "summary_llm": "ollama/qwen3.5:9b",
  "summary_llm_config": { "model_list": [ "…the same route…" ] },
  "embedding": "ollama/bge-m3",
  "embedding_config": { "kwargs": { "api_base": "http://localhost:11434" } },
  "answer": { "max_concurrent_requests": 2 },
  "parsing": { "multimodal": 0 },
  "agent": {
    "agent_llm": "ollama/qwen3.5:9b",
    "agent_llm_config": { "model_list": [ "…the same route…" ] },
    "index": { "paper_directory": "/home/me/.cache/papers" }
  }
}
```

Without the module, write the same file by hand at that path, or under another `HOME`-like root named by `PQA_HOME`. Both Ollama models must be pulled before the first run: `ollama pull qwen3.5:9b` and `ollama pull bge-m3`. The `timeout` matters: litellm's default of 60 seconds is shorter than Ollama loading a 9B model into the GPU on the first call, and that first call fails the whole index (measured 2026-09-10). The concurrency matters for the same reason: Ollama serves one model, so four parallel requests only queue behind each other until the timeout. `parsing.multimodal` at 0 keeps indexing to text: the default parses every figure and table and asks the model for a caption of each, which on a local model turns one paper into ten minutes of GPU time and adds nothing to text retrieval. `pqa ask` does not work with this preset, and the reason is the model, not the settings: every PaperQA2 agent, the default tool selector and the fixed-order `fake` one alike, ends a turn by forcing a tool call (`tool_choice` required, or the `complete` tool), and `qwen3.5:9b` served by Ollama answers a forced tool call with an empty message, so `ask` finishes with "no papers" (measured 2026-09-10, 12 s and 80 s respectively). `ask` needs a model that returns tool calls through litellm; with a local one, `pqa-evidence` is the corpus mode.

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

`pqa-evidence` is this repository's own script (`tools/evidence.py`, run by the environment's interpreter): PaperQA2's paper search over the index, then its evidence gathering with the contextual summaries switched off, so the only model that runs is the embedding model and the passages come back in seconds, untouched. In the skill it is the corpus mode: the master writes the synthesis, since retrieval is where a local model is as good as any and synthesis is where it is not. `ask` would spend the local model on the per-passage summaries and the final answer, and is the economy option when a model that can drive it is configured; see the limits below for why the default preset cannot. `pqa search` is a different thing from both: a keyword search over the index that names papers, not passages.

The index lives under `~/.pqa/indexes/` and is keyed by a hash of the settings: a changed model means a rebuilt index. Adding papers is dropping PDFs into the folder and running `index` again; the folder is the same one the reading subagent downloads into, so a paper read once is in the corpus already.

## Limits

- Everything PaperQA2 knows comes from the folder: a question about a paper not in it gets an honest "no evidence", not a search
- A local 9B model summarises well and reasons less well; when the answer hinges on a subtle comparison, read the two papers with `read` and decide in the master
- The first `index` over a large folder is slow: every chunk is embedded once, on the GPU
