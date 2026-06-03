export const meta = {
  name: 'bench-s0-monolith',
  description: 'Benchmark S0: single agent extracts all 8 SKILL.md items (no fan-out baseline)',
  phases: [{ title: 'Extract' }],
}

// One agent processes all 8 files in its own context. Baseline for "don't use a
// workflow, just one subagent". Measures the no-orchestration case.

const FILES = [
  'plugins/autopilot/skills/dispatch/SKILL.md',
  'plugins/autopilot/skills/fsd/SKILL.md',
  'plugins/autopilot/skills/loop/SKILL.md',
  'plugins/autopilot/skills/spec/SKILL.md',
  'plugins/autopilot/skills/using-autopilot/SKILL.md',
  'plugins/project-init/skills/bootstrap/SKILL.md',
  'plugins/project-init/skills/context-rule-creator/SKILL.md',
  'plugins/project-init/skills/engineering-rule-creator/SKILL.md',
]

const ITEM = {
  type: 'object',
  additionalProperties: false,
  required: ['skillName', 'subcommands', 'purpose'],
  properties: {
    skillName: { type: 'string' },
    subcommands: { type: 'array', items: { type: 'string' } },
    purpose: { type: 'string' },
  },
}
const SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['items'],
  properties: { items: { type: 'array', items: ITEM } },
}

const t0 = budget.spent()
phase('Extract')
const result = await agent(
  `For EACH of these ${FILES.length} files (paths relative to repo root), read it and extract:\n` +
  `- skillName: the frontmatter \`name\` value verbatim.\n` +
  `- subcommands: the invocation subcommands listed in the description's trailing \`(a/b/c)\` group after the Skill(...) call pattern. Empty array [] if the description has no such group.\n` +
  `- purpose: one-line summary of what the skill does.\n\n` +
  `Files:\n${FILES.map((f, i) => `${i + 1}. ${f}`).join('\n')}\n\n` +
  `Return one object per file in the same order.`,
  { label: 'monolith-all', phase: 'Extract', schema: SCHEMA }
)
const tokens = budget.spent() - t0

return { strategy: 's0-monolith', tokens, items: result ? result.items : [] }
