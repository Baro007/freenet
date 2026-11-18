# Domain Docs

How the engineering skills consume Freenet's domain documentation when exploring the codebase.

## Before exploring, read these

- `CONTEXT.md` at the repository root.
- Relevant ADRs under `docs/adr/`.

If either location does not exist, proceed silently. Do not create empty placeholders. The `/domain-modeling` skill creates them lazily when a term or architectural decision is actually resolved.

## File structure

Freenet is a single-context repository:

```text
/
├── CONTEXT.md
├── docs/
│   └── adr/
│       ├── 0001-example-decision.md
│       └── 0002-example-decision.md
└── app/
```

## Use the glossary's vocabulary

When output names a domain concept in an issue title, refactor proposal, hypothesis, or test name, use the term defined in `CONTEXT.md`. Do not drift to synonyms the glossary explicitly avoids.

If a needed concept is absent, either reconsider whether the term belongs to Freenet's domain or record the gap for `/domain-modeling`.

## Flag ADR conflicts

If proposed work contradicts an existing ADR, surface the conflict explicitly instead of silently overriding the decision.

> Contradicts ADR-0007 (`example decision`) — worth reopening because ...
