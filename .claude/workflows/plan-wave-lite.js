export const meta = {
  name: 'plan-wave-lite',
  description: 'Implement plan tasks one after another (TDD), one combined review, at most one fix round, merge each before the next',
  whenToUse: 'Cheaper than plan-wave for small or app-layer tasks, also across plans. args: {items: [{plan: "docs/superpowers/plans/<file>.md", task: 5}, ...], base: "main"}. Leftover findings come back unmerged.',
  phases: [
    { title: 'Implement', detail: 'one agent per task, own worktree, TDD' },
    { title: 'Review', detail: 'one combined reviewer; blocker/should findings checked by a skeptic' },
    { title: 'Fix', detail: 'one fix round, then a re-check of those findings only' },
    { title: 'Integrate', detail: 'merge the clean task into base, full build and test, before the next task' },
  ],
}

const items = (args && args.items) || []
const base = (args && args.base) || 'main'
if (!items.length) throw new Error('Pass args: {items: [{plan, task}, ...], base?}')

const DONE = {
  type: 'object',
  properties: {
    branch: { type: 'string' },
    worktree: { type: 'string', description: 'absolute path of the worktree' },
    testsPassed: { type: 'boolean', description: 'swift build and swift test both succeeded' },
    summary: { type: 'string', description: 'what was built; every deviation from the plan and why' },
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
const MERGED = {
  type: 'object',
  properties: { merged: { type: 'boolean' }, testsPassed: { type: 'boolean' }, testSummary: { type: 'string' } },
  required: ['merged', 'testsPassed', 'testSummary'],
}

const STRINGS = `New UI text: add the keys to Resources/Localizable.xcstrings by hand, in the file's existing format, translated into all 29 other languages (don't commit the whole-file rewrite scripts/strings.sh makes; you may run it to see which keys are new, then reset the file).`

const tag = item => {
  const m = item.plan.match(/milestone-(\d+)/)
  return `${m ? `m${m[1]}` : 'p'}-task-${item.task}`
}

const results = []
for (const item of items) {
  const name = tag(item)
  phase('Implement')
  const done = await agent(
    `Implement Task ${item.task} of ${item.plan}, exactly as written, using superpowers:test-driven-development.
You are in your own git worktree branched from ${base}. Name your branch ${name}.
First confirm the tasks Task ${item.task} needs are present in ${base}; if not, stop and say so.
Touch only the files the task lists (plus the string catalog). ${STRINGS}
Never run the app or anything that uses the screen. Run \`swift build\` and \`swift test\`; both must pass.
If a plan test is wrong, fix the test and say why; never change specified behaviour to make a test pass.
Commit with a conventional commit message. Do not tick checkboxes in the plan.`,
    { label: `${name} implement`, phase: 'Implement', isolation: 'worktree', schema: DONE })
  if (!done) { results.push({ item: name, ok: false, note: 'implementer failed' }); continue }

  const review = () => agent(
    `Review ${name} (Task ${item.task} of ${item.plan}). Branch ${done.branch}, worktree ${done.worktree}: cd there; compare with ${base} (git diff ${base}...HEAD). Implementer's note: ${done.summary}
Check, in one pass: the plan task and docs/spec.md (behaviour, texts, keys, menus); AGENTS.md rules (never lose user data, error wording, layering, Theme tokens, translations); correctness under edge cases (empty and one-item folders, unreadable files, rapid repeated keys, mode switches); Swift 6 concurrency (isolation, races, cancellation, stale async results); performance budgets (no file reads or decoding on the main thread, bounded memory).
Do not run the app. Return findings only for real problems with a concrete failing scenario. No style opinions, no praise. Empty list if clean.`,
    { label: `${name} review`, phase: 'Review', schema: FINDINGS })

  const verify = f => agent(
    `In worktree ${done.worktree} (${name}, Task ${item.task} of ${item.plan}), check this claimed defect. Default to real=false unless you can confirm it from the code or by running a test (never the app).
Where: ${f.where}
Problem: ${f.problem}
Failing scenario: ${f.scenario}`,
    { label: `${name} verify ${f.where}`, phase: 'Review', schema: VERDICT })

  const confirm = async list => (await parallel(list.map(f => () => verify(f).then(v => (v && v.real ? f : null))))).filter(Boolean)

  const reviewed = await review()
  let open = await confirm(((reviewed && reviewed.findings) || []).filter(f => f.severity !== 'nit'))

  if (open.length) {
    await agent(
      `cd ${done.worktree} (branch ${done.branch}). Fix these confirmed findings for ${name} (Task ${item.task} of ${item.plan}). For Core code, first add a failing test that shows it. Never run the app. Run swift build and swift test; commit with "fix:" messages.
${open.map((f, i) => `${i + 1}. [${f.severity}] ${f.where}: ${f.problem}. Scenario: ${f.scenario}`).join('\n')}`,
      { label: `${name} fix`, phase: 'Fix' })
    // Only the fixed findings are re-checked: no new review round.
    open = await confirm(open.map(f => ({ ...f, problem: `${f.problem} (a fix was just committed: is the defect still there?)` })))
  }

  if (!done.testsPassed || open.length) {
    log(`${name}: not merged, ${open.length} finding(s) left`)
    results.push({ item: name, ok: false, branch: done.branch, worktree: done.worktree, summary: done.summary, openFindings: open })
    continue
  }

  phase('Integrate')
  const merge = await agent(
    `In the main repository checkout (not a worktree), on branch ${base}: merge ${done.branch} with --no-ff (message "Merge branch '${name}'").
If .git/MERGE_HEAD exists, another merge is in progress: wait (check every 30 s, up to 20 min) until it is gone before you start.
Resolve conflicts only if trivial and explain each. For Resources/Localizable.xcstrings, merge as JSON: keep ours, add theirs' new or changed keys, keep the file's format so the diff only adds lines. Otherwise abort the merge and report it.
Stage only the files you resolved (git add <file>); never git add -A or git add ., and leave untracked files alone.
Then run swift build and swift test on ${base} (a known timing-flaky test may fail under load: rerun that suite alone and report both). Do not push.`,
    { label: `${name} merge`, phase: 'Integrate', schema: MERGED })
  results.push({ item: name, ok: !!(merge && merge.merged && merge.testsPassed), branch: done.branch, worktree: done.worktree,
                 summary: done.summary, merge, openFindings: [] })
  if (!merge || !merge.merged) log(`${name}: merge failed, later tasks build on ${base} without it`)
}

return { results }
