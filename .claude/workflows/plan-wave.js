export const meta = {
  name: 'plan-wave',
  description: 'Implement one wave of plan tasks in parallel worktrees (TDD), review each with three independent adversarial lenses, fix until clean, then merge the wave and run the full suite',
  whenToUse: 'Executing a milestone plan wave by wave (ultracode quality). args: {plan: "docs/superpowers/plans/<file>.md", tasks: [2, 4, 6, 8], base: "main"}.',
  phases: [
    { title: 'Implement', detail: 'one agent per task, own worktree, TDD' },
    { title: 'Review', detail: 'spec-guard + adversarial correctness + concurrency/performance, per task' },
    { title: 'Fix', detail: 'fix confirmed findings, re-review, up to 3 rounds' },
    { title: 'Integrate', detail: 'merge passing branches into base, full build and test' },
  ],
}

const plan = args && args.plan
const tasks = (args && args.tasks) || []
const base = (args && args.base) || 'main'
if (!plan || !tasks.length) throw new Error('Pass args: {plan, tasks: [...], base?}')

const DONE = {
  type: 'object',
  properties: {
    branch: { type: 'string' },
    worktree: { type: 'string', description: 'absolute path of the worktree' },
    testsPassed: { type: 'boolean', description: 'swift build and swift test both succeeded' },
    summary: { type: 'string', description: 'what was built; every deviation from the plan and why (test wrong vs code wrong)' },
  },
  required: ['branch', 'worktree', 'testsPassed', 'summary'],
}
const FINDINGS = {
  type: 'object',
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          severity: { type: 'string', enum: ['blocker', 'should', 'nit'] },
          where: { type: 'string', description: 'path:line' },
          problem: { type: 'string' },
          scenario: { type: 'string', description: 'concrete input or state that fails' },
        },
        required: ['severity', 'where', 'problem', 'scenario'],
      },
    },
  },
  required: ['findings'],
}
const VERDICT = {
  type: 'object',
  properties: { real: { type: 'boolean' }, why: { type: 'string' } },
  required: ['real', 'why'],
}

const STRINGS = `New UI text: run scripts/strings.sh to extract it into Resources/Localizable.xcstrings, then translate the new keys into all 29 other languages and commit the catalog. Never add keys to the catalog by hand.`

const LENSES = [
  { key: 'spec', agentType: 'spec-guard',
    prompt: 'Review against docs/spec.md, the plan task, and the AGENTS.md rules (clean room, never lose data, error wording, layering).' },
  { key: 'break', prompt: 'You are an adversarial tester. Try to break this task: corrupt, missing, huge, zero-size, unusual-name, symlinked, read-only and case-clashing files; empty and one-item folders; boundaries. Write throwaway checks in a scratch file if useful (do not commit them). Report only failures you can demonstrate or point to in code.' },
  { key: 'perf', prompt: 'Review for Swift 6 strict-concurrency correctness (actor isolation, Sendable, races, cancellation) and against the performance budgets in AGENTS.md (no file reads or decoding on the main thread, decode at screen size, bounded memory, folder scans never open file contents).' },
]

const implement = n => agent(
  `Implement Task ${n} of ${plan}, exactly as written, using superpowers:test-driven-development.
You are in your own git worktree branched from ${base}. Name your branch task-${n}.
First confirm the tasks Task ${n} "Needs" (plan's execution-order table) are present in ${base}; if not, stop and say so.
Touch only the files Task ${n} lists (plus the string catalog). ${STRINGS}
Never run the app or anything that uses the screen. Run \`swift build\` and \`swift test\`; both must pass.
If a plan test is wrong, fix the test and say why; never change specified behaviour to make a test pass.
Commit with a conventional commit message. Do not tick checkboxes in the plan.`,
  { label: `task ${n}`, phase: 'Implement', isolation: 'worktree', schema: DONE })

const reviewAll = (done, n, round) => parallel(LENSES.map(l => () => agent(
  `Review plan Task ${n} of ${plan} (round ${round}). Branch ${done.branch}, worktree ${done.worktree}: cd there; compare with ${base} (git diff ${base}...HEAD). Implementer's note: ${done.summary}
${l.prompt}
Do not run the app. Return findings only for real problems with a concrete failing scenario. No style opinions, no praise. Empty list if clean.`,
  { label: `review ${n} ${l.key} r${round}`, phase: 'Review', schema: FINDINGS, ...(l.agentType ? { agentType: l.agentType } : {}) })))

// Each blocker/should finding must survive an independent skeptic before anyone fixes it.
const verify = (f, done, n) => agent(
  `In worktree ${done.worktree} (plan Task ${n} of ${plan}), check this claimed defect. Default to real=false unless you can confirm it from the code or by running a test (never the app).
Where: ${f.where}
Problem: ${f.problem}
Failing scenario: ${f.scenario}`,
  { label: `verify ${n} ${f.where}`, phase: 'Review', schema: VERDICT })

async function confirmedFindings(done, n, round) {
  const reviews = (await reviewAll(done, n, round)).filter(Boolean)
  const candidates = reviews.flatMap(r => r.findings).filter(f => f.severity !== 'nit')
  const verdicts = await parallel(candidates.map(f => () => verify(f, done, n).then(v => (v && v.real ? f : null))))
  return verdicts.filter(Boolean)
}

const results = await pipeline(tasks, implement, async (done, n) => {
  if (!done) return { task: n, ok: false, note: 'implementer failed' }
  let open = await confirmedFindings(done, n, 1)
  for (let round = 2; open.length && round <= 4; round++) {
    await agent(
      `cd ${done.worktree} (branch ${done.branch}). Fix these confirmed findings for plan Task ${n} of ${plan}. For each, first add a failing test that shows it, then fix. Never run the app. Run swift build and swift test; commit with "fix:" messages.
${open.map((f, i) => `${i + 1}. [${f.severity}] ${f.where}: ${f.problem}. Scenario: ${f.scenario}`).join('\n')}`,
      { label: `fix ${n} r${round - 1}`, phase: 'Fix' })
    open = await confirmedFindings(done, n, round)
  }
  return { task: n, ok: done.testsPassed && open.length === 0, branch: done.branch, worktree: done.worktree,
           summary: done.summary, openFindings: open }
})

const passing = results.filter(r => r && r.ok)
const failing = results.filter(r => !r || !r.ok)
if (failing.length) log(`${failing.length} task(s) not clean after 3 fix rounds; not merged`)

phase('Integrate')
const integration = passing.length ? await agent(
  `In the main repository checkout (not a worktree), on branch ${base}: merge these branches one at a time with --no-ff: ${passing.map(r => r.branch).join(', ')}.
Other waves may be integrating into the same checkout: if .git/MERGE_HEAD exists, wait (check every 30 s, up to 20 min) until it is gone before you start.
Resolve conflicts only if trivial and explain each. For a Resources/Localizable.xcstrings conflict, run scripts/merge-strings.py, then git add Resources/Localizable.xcstrings (if it stops because both sides changed a key, that conflict is not trivial). Otherwise abort that merge and report it.
Stage only the files you resolved (git add <file>); never git add -A or git add ., and leave untracked files alone.
Then run swift build and swift test on ${base}. Report merged branches, any skipped, and the test summary line.`,
  { label: 'merge wave', phase: 'Integrate', schema: {
    type: 'object',
    properties: { merged: { type: 'array', items: { type: 'string' } }, skipped: { type: 'array', items: { type: 'string' } },
                  testsPassed: { type: 'boolean' }, testSummary: { type: 'string' } },
    required: ['merged', 'skipped', 'testsPassed', 'testSummary'] } }) : null

return { results, integration }
