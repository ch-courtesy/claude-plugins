export const meta = {
  name: 'bench-s4-parallel-2stage',
  description: 'Benchmark S4: extract-all (barrier) THEN verify-all (barrier) — same 2 stages as S3 but barriered',
  phases: [{ title: 'Extract' }, { title: 'Verify' }],
}

// parallel(extract) — wait for ALL extracts — then parallel(verify). The barrier
// between stages means the slowest extract gates the start of every verify.
// Same work as S3; the wall-clock delta vs S3 is the cost of the barrier.

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
const VERIFIED = {
  type: 'object',
  additionalProperties: false,
  required: ['skillName', 'subcommands', 'purpose', 'corrected'],
  properties: {
    skillName: { type: 'string' },
    subcommands: { type: 'array', items: { type: 'string' } },
    purpose: { type: 'string' },
    corrected: { type: 'boolean' },
  },
}

function extractPrompt(f) {
  return `Read the file \`${f}\` (relative to repo root) and extract:\n` +
    `- skillName: the frontmatter \`name\` value verbatim.\n` +
    `- subcommands: the invocation subcommands in the description's trailing \`(a/b/c)\` group after the Skill(...) call pattern. Empty array [] if none.\n` +
    `- purpose: one-line summary of what the skill does.`
}
function verifyPrompt(f, prev) {
  return `Re-read \`${f}\` (relative to repo root) and verify this extraction:\n` +
    `${JSON.stringify(prev)}\n\n` +
    `Check skillName matches the frontmatter \`name\` exactly and subcommands exactly match the description's trailing \`(a/b/c)\` group ([] if none). ` +
    `Return the corrected object plus \`corrected\`: true if you changed any field, false otherwise.`
}

const t0 = budget.spent()
phase('Extract')
const extracted = await parallel(
  FILES.map((f, i) => () => agent(extractPrompt(f), { label: `extract:${i + 1}`, phase: 'Extract', schema: ITEM }))
)
phase('Verify')
const verified = await parallel(
  extracted.map((prev, i) => () =>
    prev ? agent(verifyPrompt(FILES[i], prev), { label: `verify:${i + 1}`, phase: 'Verify', schema: VERIFIED }) : null
  )
)
const items = verified.filter(Boolean)
const tokens = budget.spent() - t0

return { strategy: 's4-parallel-2stage', tokens, items }
