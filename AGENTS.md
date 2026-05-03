# Agent Contract

## Purpose Boundary
- This repository is public and installer-only.
- Keep scope limited to bootstrap and enrollment scripts.
- Do not add private orchestration logic, private API internals, or secrets.

## Mandatory Workflow
- Before any code edit, propose a concrete plan and wait for explicit user approval.
- Do not create or change existing `.md` files.
- Keep changes minimal and scoped to the requested behavior.
- If the result does not satisfy these rules, rewrite it before handoff.

## Coding Rules
- Follow existing architecture and style already present in this repository.
- Do not overengineer.
- Do not add comments in code.
- Use human-readable naming and straightforward control flow.
- Bash-specific pragmatism is allowed when it improves reliability and readability.

## Verification Before Handoff
- Run:
```bash
bash -n install.sh lib/*.sh
```

## Security Rules
- Never commit tokens, passwords, private endpoints, or private policy data.
- Never move super-master internals into this public repository.
