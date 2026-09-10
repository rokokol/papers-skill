<div align="center">

# papers skill

**Scientific papers for an agent, without spending the conversation on them (｡•̀ᴗ-)✧**

[![Agent Skill](https://img.shields.io/badge/Agent_Skill-6E56CF?style=flat)](https://agentskills.io)
![MCP](https://img.shields.io/badge/MCP-000000?style=flat)
![Nix](https://img.shields.io/badge/Nix-5277C3?style=flat&logo=nixos&logoColor=white)
![Bash](https://img.shields.io/badge/Bash-4EAA25?style=flat&logo=gnubash&logoColor=white)
[![license](https://img.shields.io/badge/MIT-3DA639?style=flat)](LICENSE)
[![ci](https://github.com/rokokol/papers-skill/actions/workflows/ci.yml/badge.svg)](https://github.com/rokokol/papers-skill/actions/workflows/ci.yml)

</div>

A paper is long and its PDF is worse: the text of one article is a large share of a conversation's context, and a literature question is several of them. This skill keeps the reading out of the main conversation. The agent finds and decides; a subagent with its own context reads one paper and returns a digest of bounded length; the agent compares digests and, only when you say so, files one into your notes

The sources come from [paper-search-mcp](https://github.com/openags/paper-search-mcp), which reaches arXiv, PubMed, Semantic Scholar, OpenAlex, Crossref, bioRxiv and a dozen more through one MCP server or one CLI. This repository packages it for Nix, because the PyPI release breaks under the current MCP SDK and nixpkgs does not carry it, and ships a Home Manager module so the keys never enter a store path or a chat

## Contents

- [Install the skill](#install-the-skill)
- [Install the sources](#install-the-sources)
- [Register the server](#register-the-server)
- [Keys](#keys)
- [Notes in a vault](#notes-in-a-vault)
- [Checks](#checks)
- [Layout](#layout)

## Install the skill

```sh
git clone https://github.com/rokokol/papers-skill ~/Projects/papers
ln -s ~/Projects/papers ~/.claude/skills/papers
```

Or straight into the skills directory your agent reads:

```sh
git clone https://github.com/rokokol/papers-skill ~/.claude/skills/papers
```

> [!NOTE]
> A skill has no version to pin — it is read at whatever revision you have checked out, so `git pull` is the whole upgrade path and the changelog is dated rather than numbered

Then ask for papers on a topic, a DOI or an arXiv id, a digest, or a comparison — in English or with the Russian triggers listed in [SKILL.md](SKILL.md). Nothing in `SKILL.md` is about installation; everything below is

## Install the sources

The skill needs `paper-search-mcp` on the machine, as the MCP server, the `paper-search` CLI, or both; one package provides both binaries

**With Nix**, the flake builds the PyPI release against nixpkgs' MCP SDK 1.x, which is what keeps the server importable:

```sh
nix build github:rokokol/papers-skill#paper-search-mcp
nix profile install github:rokokol/papers-skill#paper-search-mcp
```

Or declaratively, as a Home Manager module. The consumer adds the flake as an input and enables the module; `envFile` is optional and points both binaries at a file with the keys, rendered by whatever secret store the consumer runs:

```nix
{
  inputs.papers-skill = {
    url = "github:rokokol/papers-skill";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

```nix
{ inputs, ... }:
{
  imports = [ inputs.papers-skill.homeModules.default ];
  programs.papers = {
    enable = true;
    envFile = "/run/secrets/rendered/paper-search.env";
  };
}
```

An overlay is there too, `inputs.papers-skill.overlays.default`, for a consumer who reaches for `pkgs.paper-search-mcp`

**Without Nix**, install the release with the SDK pinned below 2, which upstream's own metadata does not do:

```sh
uv tool install --with "mcp<2" paper-search-mcp==0.1.4
```

> [!WARNING]
> Upstream's `download_with_fallback` tool tries Sci-Hub after the open-access routes, and that is on by default. Whether that belongs on your machine is your call, and the skill says so wherever a PDF came from that route; `use_scihub: false` on the call turns it off

## Register the server

Claude Code starts a stdio MCP server per session and stops it on exit; nothing is hosted. With the binary on `PATH`:

```sh
claude mcp add --scope user --transport stdio paper-search -- paper-search-mcp
claude mcp list
```

The skill assumes the name `paper-search`, so its tools are `mcp__paper-search__*`. Another client, or a session where the server is not registered, falls back to the `paper-search` CLI, which the skill drives from Bash; the per-source `read_*_paper` tools and `download_with_fallback` exist only on the server

## Keys

Every source works without a key. Three free ones change how well: a [Semantic Scholar](https://www.semanticscholar.org/product/api) key takes you off the anonymous pool shared by everyone, a [CORE](https://core.ac.uk/services/api) key stops its frequent 500s, and an email for [Unpaywall](https://unpaywall.org/products/api) turns on the open-access step of the download fallback, which is otherwise skipped. The server reads them from an env file: the path in `PAPER_SEARCH_MCP_ENV_FILE`, else `~/.config/paper-search-mcp/.env`

```sh
PAPER_SEARCH_MCP_SEMANTIC_SCHOLAR_API_KEY=...
PAPER_SEARCH_MCP_CORE_API_KEY=...
PAPER_SEARCH_MCP_UNPAYWALL_EMAIL=you@example.com
```

Keep that file out of the repository and out of the chat: the skill never asks for a key and never puts one on a command line. [references/sources.md](references/sources.md) lists the rest of the variables and what each source does without them

## Notes in a vault

The `note` mode files a digest into an Obsidian vault, but only when you say so, and never in a shape invented here: your vault has its own style, and the skill defers to it. Tell it how through one profile in the vault:

```yaml
# $OBSIDIAN_VAULT_PATH/.claude/papers/profile.yml
style_skill: conspect
preset: paper
notes_dir: "04. Книжная полка/Статьи"
attachments_dir: "00. Вложения/Статьи"
```

`style_skill` is a vault-local skill under `.claude/skills/` that owns note style, `preset` the preset of that skill for a paper note, and the two folders are where notes and kept PDFs go. Without a profile the skill asks for a path and writes plain Markdown. [references/profile.md](references/profile.md) has every field

The vault is found through `OBSIDIAN_VAULT_PATH`, the variable the official Obsidian CLI understands; set it in the `env` block of `~/.claude/settings.json` so every session sees it

## Checks

```sh
nix develop -c ./check.sh
nix flake check
```

`check.sh` is the gate CI runs: the scripts lint, the workflows are valid and pinned, the vendored checkers still match their lock, `SKILL.md` loads and every reference and link resolves, the changelog obeys its rules, and every MCP tool and source the documents name is one the packaged server actually advertises. Each check is proven able to fail on a planted defect during the same run. `nix flake check` builds the package and starts the server once, offline

## Layout

```
SKILL.md              what the agent loads: modes, the reading subagent's contract, the never list
references/           sources by area, the reader prompt, the digest template, the profile, paperqa
nix/                  package.nix for paper-search-mcp, home-module.nix for Home Manager
flake.nix             packages, the module, the overlay, the dev shell and the checks
tests/mcp-tools.py    asks a stdio MCP server what tools it has; check.sh compares the documents to it
check.sh              the gate, self-tested against planted defects
check-*.sh            vendored checkers, kept byte-equal to their source by vendor-sync.sh
```
