export const meta = {
  name: 'bench-s3-pipeline',
  description: 'Benchmark S3: 2-stage extract→verify pipelined per item, NO barrier between stages',
  phases: [{ title: 'Extract' }, { title: 'Verify' }],
}

// pipeline(items, extract, verify): each file flows extract→verify independently.
// An item can be in Verify while another is still in Extract — no barrier.
// Contrast with S4 which forces a barrier between the two stages.

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
const out = await pipeline(
  FILES,
  (f, _orig, i) => agent(extractPrompt(f), { label: `extract:${i + 1}`, phase: 'Extract', schema: ITEM }),
  (prev, f, i) => agent(verifyPrompt(f, prev), { label: `verify:${i + 1}`, phase: 'Verify', schema: VERIFIED })
)
const items = out.filter(Boolean)
const tokens = budget.spent() - t0

return { strategy: 's3-pipeline', tokens, items }
