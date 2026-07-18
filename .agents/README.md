# LexiRay Agent Assets

`AGENTS.md` is the canonical, agent-independent contract. This directory holds
progressively loaded detail:

- `runbooks/`: executable project procedures for verification, GUI acceptance,
  data safety, installation, Git/CI, and release.
- `adr/`: durable technical decisions and shared domain terminology.
- `skills/`: narrow reusable capabilities discovered by supported agents.
- `prompts/`: optional task starters; they must defer to `AGENTS.md` and the
  runbooks instead of duplicating policy.

Codex loads `AGENTS.md` and `.agents/skills` natively. `CLAUDE.md` imports the
same contract and `.claude/skills` points to `.agents/skills`. Do not add tracked
`.codex` compatibility files or create an agent-specific source of truth.
