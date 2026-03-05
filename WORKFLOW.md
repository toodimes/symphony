---
tracker:
  kind: linear
  team_key: "AIW"
  labels: ["symphony"]
  assignee: "me"
  dispatch_states: "Todo, In Progress"
  active_states: "Todo, In Progress, Code Review, On Staging"
  terminal_states: "Done, Canceled"
polling:
  interval_ms: 5000
workspace:
  root: ~/code/symphony-workspaces
hooks:
  after_create: |
    git clone --depth 1 https://github.com/toodimes/symphony .
    if command -v mise >/dev/null 2>&1; then
      mise trust && mise exec -- mix deps.get
    fi
  before_remove: |
    mise exec -- mix workspace.before_remove
agent:
  backend: claude
  max_concurrent_agents: 10
  max_turns: 20
claude:
  command: claude
  permission_mode: bypassPermissions
codex:
  command: codex --config shell_environment_policy.inherit=all --config model_reasoning_effort=high --model gpt-5.3-codex app-server
  approval_policy: never
  thread_sandbox: workspace-write
  turn_sandbox_policy:
    type: workspaceWrite
---

You are working on a Linear ticket `{{ issue.identifier }}`

{% if attempt %}
Continuation context:

- This is retry attempt #{{ attempt }} because the ticket is still in an active state.
- Resume from the current workspace state instead of restarting from scratch.
- Do not repeat already-completed investigation or validation unless needed for new code changes.
- Do not end the turn while the issue remains in an active state unless you are blocked by missing required permissions/secrets.
  {% endif %}

Issue context:
Identifier: {{ issue.identifier }}
Title: {{ issue.title }}
Current status: {{ issue.state }}
Labels: {{ issue.labels }}
URL: {{ issue.url }}

Description:
{% if issue.description %}
{{ issue.description }}
{% else %}
No description provided.
{% endif %}

Instructions:

1. This is an unattended orchestration session. Never ask a human to perform follow-up actions.
2. Only stop early for a true blocker (missing required auth/permissions/secrets). If blocked, record it in the workpad and move the issue according to workflow.
3. Final message must report completed actions and blockers only. Do not include "next steps for user".

Work only in the provided repository copy. Do not touch any other path.

Requires a Linear MCP server or injected `linear_graphql` tool. If neither is present, stop and ask the user to configure Linear.

## Skills

- `linear`: interact with Linear.
- `commit`: produce clean, logical commits.
- `push`: keep remote branch current.
- `pull`: sync with latest `origin/main`.
- `land`: when ticket reaches `Merging`, open and follow `.codex/skills/land/SKILL.md`.

## Rules

- Determine the ticket's current status first, then follow the matching flow.
- Use exactly one persistent `## Codex Workpad` comment per issue for all progress tracking (see template below). Do not post separate summary comments.
- Plan and verify before implementing. Reproduce the issue signal before changing code.
- Treat any ticket-authored `Validation`, `Test Plan`, or `Testing` section as mandatory acceptance input — mirror it in the workpad and complete it before handoff.
- Keep ticket metadata current (state, acceptance criteria, links).
- Out-of-scope improvements go in a separate Backlog issue (with title, description, acceptance criteria, same project, `related` link to current issue).
- Do not edit the issue body/description for planning or progress tracking.
- Temporary proof edits (local-only validation hacks) must be reverted before commit.
- If blocked by missing tools/auth, exhaust fallbacks first. GitHub access is not a valid blocker until all fallback strategies are documented in the workpad. For true blockers, move to `Human Review` with a brief in the workpad: what's missing, why it blocks, and the exact human action needed.
- If the branch PR is already closed/merged, create a fresh branch from `origin/main` and start over.

## Status map

- `Backlog` -> do not modify; wait for human to move to `Todo`.
- `Todo` -> move to `In Progress`, then start execution flow. If a PR is already attached, run PR feedback sweep first.
- `In Progress` -> continue execution from the current workpad.
- `Human Review` -> do not code or change ticket content; poll for review updates.
- `Merging` -> run the `land` skill (do not call `gh pr merge` directly).
- `Rework` -> full reset: close existing PR, delete workpad comment, fresh branch from `origin/main`, start over.
- `Done` -> shut down.

## Execution flow

1. Find or create the `## Codex Workpad` comment. Reconcile it: check off completed items, update the plan for current scope.
2. Run `pull` to sync with `origin/main`. Record the result in the workpad Notes.
3. Write a hierarchical plan with acceptance criteria and validation steps in the workpad. Self-review and refine before implementing.
4. Implement against the plan. Keep the workpad current — check off items, add discovered work, update after each milestone.
5. Validate: run tests, execute all ticket-provided test plan items, prefer targeted proofs. Ensure validation passes before every push.
6. Create/update PR. Attach PR URL to the issue. Ensure the PR has the `symphony` label.
7. Run PR feedback sweep: gather all comments (top-level, inline, review summaries), treat each as blocking until addressed or explicitly pushed back on. Repeat until clean.
8. Merge latest `origin/main`, rerun checks, confirm everything is green. Refresh the workpad so it matches completed work.
9. Move to `Human Review`.

## Human Review and merge

1. In `Human Review`, do not code or change ticket content. Poll for updates.
2. If review feedback requires changes, move to `Rework`.
3. When issue reaches `Merging`, run the `land` skill until merged, then move to `Done`.

## Completion bar before Human Review

- Workpad checklist fully complete and accurate.
- All acceptance criteria and ticket-provided validation items complete.
- Validation/tests green for latest commit.
- PR feedback sweep clean — no outstanding actionable comments.
- PR checks green, branch pushed, PR linked on issue with `symphony` label.

## Workpad template

Use this exact structure for the persistent workpad comment:

````md
## Codex Workpad

```text
<hostname>:<abs-path>@<short-sha>
```

### Plan

- [ ] 1\. Parent task
  - [ ] 1.1 Child task
  - [ ] 1.2 Child task
- [ ] 2\. Parent task

### Acceptance Criteria

- [ ] Criterion 1
- [ ] Criterion 2

### Validation

- [ ] targeted tests: `<command>`

### Notes

- <short progress note with timestamp>

### Confusions

- <only include when something was confusing during execution>
````
