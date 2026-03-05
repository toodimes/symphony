---
name: plan-review-iteration
description: Review a plan, design decision, or implementation approach using Codex CLI and implement feedback. Use when the user says "review the plan", "review this approach", "get codex to review", "codex review", or wants a second opinion on any design/implementation chunk.
---

# Plan Review Iteration

Use Codex CLI to review implementation plans, design decisions, or specific implementation approaches and incorporate feedback.

## Instructions

1. **Determine what to review**: Identify the review target from conversation context. This can be:

   - **A plan file**: A `.md` file path from the conversation (e.g., written by the planning skill)
   - **Inline content**: A specific approach, design decision, or brainstorming chunk from the current conversation that the user wants reviewed

   If neither is obvious, ask the user what they'd like Codex to review.

2. **Prepare the review content**: Depending on the source:

   - **Plan file exists**: Use the file path directly in the Codex prompt.
   - **Inline content**: Write the content to a temp file so Codex can reference it:

     ```bash
     cat <<'CONTENT_EOF' > /tmp/codex-review-$(date +%s).md
     <CONTENT FROM CONVERSATION>
     CONTENT_EOF
     ```

     Include enough context for the review to be useful: the goal, the proposed approach, any constraints or alternatives considered, and relevant file paths in the codebase.

3. **Run Codex review**: Execute Codex CLI with JSON output. **Set `timeout: 600000` on the Bash tool call** to allow up to 10 minutes before timing out:

   ```bash
   codex exec --full-auto --json "Review the implementation approach at <FILE_PATH> and provide feedback on:

   1. SIMPLICITY: Is the implementation as simple as possible? Does it avoid over-engineering, unnecessary abstractions, or premature optimization?
   2. ROBUSTNESS: Does it handle errors appropriately? Are edge cases considered? Is it resilient to failures?
   3. REUSE: Does the plan leverage existing functions/modules in the codebase, or does it propose writing new code that duplicates existing functionality? Search the codebase for existing implementations before suggesting new code.
   4. SECURITY: Are there any potential security concerns?
   5. COMPLETENESS: Does it cover all requirements and edge cases?
   6. CODE QUALITY: Is the implementation approach sound? Are the patterns appropriate?

   Be specific about any issues found and suggest concrete improvements."
   ```

4. **Extract the session ID**: Parse the JSON output for the `thread.started` event to get the `thread_id`:

   ```json
   {
     "type": "thread.started",
     "thread_id": "0199a213-81c0-7800-8aa1-bbab2a035a53"
   }
   ```

   Save this `thread_id` for use in resume commands.

5. **Handle timeout with resume**: If the command times out (hits the 10 minute bash timeout), resume using the specific session ID. **Set `timeout: 600000` on the Bash tool call** here as well:

   ```bash
   codex exec resume <THREAD_ID> "Continue the plan review and provide your findings."
   ```

   Keep resuming until Codex completes its review. Each resume continues from where the previous session left off.

   **Important**: After 2 consecutive timeouts (~20 minutes total), ask the user if they want to continue before resuming again. This prevents runaway sessions and gives the user control over long-running reviews.

6. **Parse the JSON output**: Extract the feedback from Codex's structured response.

7. **Present feedback**: Summarize Codex's findings for the user.

8. **Implement changes**: Update the plan or approach based on Codex's feedback:
   - Simplify over-engineered approaches
   - Improve error handling and robustness
   - Replace new code proposals with references to existing functions where applicable
   - Fix security concerns
   - Address completeness gaps
   - Improve implementation approaches and code quality

9. **Iterate if needed**: If significant changes were made, consider running another review pass.

## Examples

### Reviewing a plan file

User: "Review the plan with codex"

1. Identify plan file path from conversation (e.g., `/tmp/plan-abc123.md`)
2. Run: `codex exec --full-auto --json "Review the implementation approach at /tmp/plan-abc123.md..."`
3. Extract `thread_id` from the `thread.started` event
4. If timeout, resume with thread_id
5. Present findings, update plan

### Reviewing a brainstorming chunk

User: "Get codex to review this approach" (mid-brainstorming)

1. Gather the relevant approach/decision from the conversation
2. Write it to `/tmp/codex-review-<timestamp>.md` with context (goal, approach, constraints, relevant files)
3. Run: `codex exec --full-auto --json "Review the implementation approach at /tmp/codex-review-<timestamp>.md..."`
4. Extract `thread_id`, handle timeouts as needed
5. Present findings, incorporate feedback into the brainstorming session

## Notes

- Codex requires being in a git repository
- `--full-auto` allows Codex to explore the codebase
- `--json` provides structured JSON Lines output for parsing
- Progress streams to stderr, final output to stdout
- The `thread_id` from the `thread.started` event uniquely identifies the session for resume
- When reviewing inline content, include enough codebase context (file paths, module names) so Codex can actually look at the relevant code
