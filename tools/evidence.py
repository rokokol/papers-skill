#!/usr/bin/env python3
"""Print the passages PaperQA2 would hand its answer model, without calling that model.

Usage: evidence.py [-s SETTINGS] [-k N] QUERY

Runs PaperQA2's own two retrieval steps against the index that `pqa -s SETTINGS index`
built: the paper search over the index, then evidence gathering over the papers it
returned, with the per-passage contextual summaries switched off. The only model that
runs is the embedding model, so the passages come back in seconds and untouched, for
whoever reads the output to reason over. Prints Markdown: one section per passage with
the paper, the chunk name and the text, in the retriever's order. Exit 1 when the index
holds no paper for the query, so a caller cannot mistake silence for a result.
"""

import argparse
import asyncio
import sys

from paperqa import Docs, Settings
from paperqa.agents.search import get_directory_index


async def gather(settings: Settings, query: str, k: int) -> list:
    settings.answer.evidence_skip_summary = True
    settings.answer.evidence_k = k
    index = await get_directory_index(settings=settings, build=False)
    results = await index.query(
        query,
        top_n=settings.agent.search_count,
        field_subset=[f for f in index.fields if f != "year"],
    )
    if not results:
        return []
    docs = Docs()
    for result in results:
        # The index stores one Docs per file, so the first doc is the file's
        doc = next(iter(result.docs.values()))
        await docs.aadd_texts(texts=result.texts, doc=doc, settings=settings)
    session = await docs.aget_evidence(query, settings=settings)
    return session.contexts[:k]


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=(__doc__ or "").strip().splitlines()[0])
    parser.add_argument("-s", "--settings", default="papers", help="pqa settings preset name (default: papers)")
    parser.add_argument("-k", type=int, default=8, help="how many passages to print (default: 8)")
    parser.add_argument("query")
    args = parser.parse_args(argv[1:])

    settings = Settings.from_name(args.settings)
    contexts = asyncio.run(gather(settings, args.query, args.k))
    if not contexts:
        print(f"evidence: no paper in the index matched {args.query!r}", file=sys.stderr)
        return 1
    for context in contexts:
        doc = context.text.doc
        title = getattr(doc, "title", None) or doc.docname
        print(f"## {title}\n\n*{context.text.name}*\n\n{context.text.text.strip()}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
