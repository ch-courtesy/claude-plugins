export const meta = {
  name: 'bench-s1-serial',
  description: 'Benchmark S1: 8 agents, one per file, awaited sequentially (no concurrency)',
  phases: [{ title: 'Extract' }],
}

// One agent() per file, but awaited one at a time in a for-loop. Isolates
// per-agent overhead with zero concurrency — the slow baseline that S2 beats.

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

function prompt(f) {
  return `Read the file \`${f}\` (relative to repo root) and extract:\n` +
    `- skillName: the frontmatter \`name\` value verbatim.\n` +
    `- subcommands: the invocation subcommands in the description's trailing \`(a/b/c)\` group after the Skill(...) call pattern. Empty array [] if none.\n` +
    `- purpose: one-line summary of what the skill does.`
}

const t0 = budget.spent()
phase('Extract')
const items = []
for (let i = 0; i < FILES.length; i++) {
  const r = await agent(prompt(FILES[i]), { label: `serial:${i + 1}`, phase: 'Extract', schema: ITEM })
  if (r) items.push(r)
}
const tokens = budget.spent() - t0

return { strategy: 's1-serial', tokens, items }
