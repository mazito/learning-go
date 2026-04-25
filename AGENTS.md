These are mandatory and IMPORTANT instructions for PI ([pi.dev](http://pi.dev) AI coding agent).

## General

- Compress your phrases as much as you can, almost like a caveman.
- Give brief and to the point responses, avoid long answers.
- Also when reasoning, avoid long phrases. Be Concise.

## Starting a session

When starting a new session read the following files:

- **README.md** — project overview, architecture, code conventions
- **MEMO.md** (or **MEMENTO.md** or **MEMORY.md**) — the state of the last session
- **LEARNINGS.md** — critical learnings to avoid repeating mistakes
- **TODO.md** — list of pending issues

## In session

- **DRAFT.md** — a temp file for long comments and instructions (too long or detailed for terminal prompt)
- **PLAN.md** — where you write the plan when asked. When need to overwrite previous content, make a file copy to `./plans/PLAN-${yymmdd-hhmmss}` to preserve previous plans.

## Closing a session

- Before closing the session, **ALWAYS** update the MEMO.md file with the session context so we can resume later.
- Before closing the session, **ALWAYS** append the changes done in the session to the CHANGES.md file. Use this format:
  ```
  # CHANGES.md - Session: <Title>
  
  ## Date: <YYYY-MM-DD>
  ## Branch: <branch-name>
  
  ### Files Modified
  
  1. **path/to/file.ts**
    - What changed
  
  ### Commits
  - `<hash>` - <message>
  
  ---
  ```

- We also have a `/finito` SKILL to close the session.

## Commits

- **NEVER** include the "Co-authored by" line in commit messages
- **NEVER** commit or push before I ask you to do so

## Coding guardrails

- **NEVER** try to do changes or assume behaviour from the backend code. Respect the separation between the UI and the backend, and respect the existent API.
- When I ask you to **replace** code, comment it out instead of deleting it. Mark comments with `// REMOVED: reason`. Override this when I explicitly ask to **FORCE delete** code.

## Writing for dialogs and UI 

Use this rules when creating titles, subtitles, warnings, confirmations, and any copy text that goes into dialogs, forms or other UI components or pages. When you understand the point of a screen, writing becomes simpler and stricter. Like a door. 

- What is this screen asking me to do? 
- What happens if I do it? 
- What happens if I don’t? 

If you can answer that in one sentence, the text will fall into place. Otherwise do your best effort and i will review and fix it. 
