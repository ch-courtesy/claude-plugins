export const meta = {
  name: 'bench-s2-parallel',
  description: 'Benchmark S2: 8 agents, one per file, run concurrently with a barrier (parallel)',
  phases: [{ title: 'Extract' }],
}

// parallel(thunks): all 8 agents run concurrently (under the ~16 cap), barrier
// at the end. Isolates the concurrency speedup vs S1's serial awaits.

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
const raw = await parallel(
  FILES.map((f, i) => () => agent(prompt(f), { label: `par:${i + 1}`, phase: 'Extract', schema: ITEM }))
)
const items = raw.filter(Boolean)
const tokens = budget.spent() - t0

return { strategy: 's2-parallel', tokens, items }
