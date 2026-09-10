# The vault profile

This skill does not know how any vault is organised, and it should not: a note's shape, folder and frontmatter belong to the vault's owner. The owner states them once in a profile, and the `note` mode reads it. Without a profile the skill still works; it asks for a path and writes plain Markdown.

## Where

`$OBSIDIAN_VAULT_PATH/.claude/papers/profile.yml`. The variable comes from the environment or from `env.OBSIDIAN_VAULT_PATH` in the harness's settings; unset means ask the user, never search the disk for a vault.

## Fields

```yaml
# The vault-local skill that owns note style, found at .claude/skills/<style_skill>/SKILL.md
style_skill: conspect
# The preset of that skill to write a paper note with; the preset defines the frontmatter and body
preset: paper
# Folder for the notes, relative to the vault root
notes_dir: "04. Книжная полка/Статьи"
# Folder for kept PDFs, relative to the vault root; omit to keep no PDF
attachments_dir: "00. Вложения/Статьи"
# Language of the note body; omit to use the language of the conversation
language: ru
```

`style_skill` and `preset` are required; the rest is optional.

## How the note mode uses it

1. Read the profile; a missing required field means stop and say which
2. Read `$OBSIDIAN_VAULT_PATH/.claude/skills/<style_skill>/SKILL.md` and the preset it names, and follow them as if the skill had been loaded: a vault-local skill is offered as a skill only to sessions started under the vault
3. Map the digest's fields onto the preset's frontmatter and body; the preset decides names, order and tags, this skill decides nothing about them
4. Write the note into `notes_dir`, move the PDF into `attachments_dir` when the profile names one and the PDF was obtained, and link it from the note the way the preset says
5. Report the path and, when the style skill ships a linter, its verdict

## Without a profile

Ask where to put the file, then write it there as plain Markdown: a frontmatter of `title`, `doi`, `arxiv`, `url`, `authors`, `year`, `venue`, `created`, followed by the digest verbatim. Nothing else is inferred about the vault.
