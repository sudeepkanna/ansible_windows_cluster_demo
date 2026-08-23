# Manager Guide — Developer → Tester → Reviewer

This repository is prepared for a visible GitHub Agentic Workflows model using OpenAI Codex.

## Operating model

1. Manager defines the requirement in a GitHub issue.
2. Manager applies label `agent-dev` when ready.
3. Developer Agent reads the issue, changes code, and opens a draft PR with title prefix `[agent-dev]`.
4. Tester Agent runs on that PR and posts `TESTER RESULT: PASS` or `TESTER RESULT: FAIL`.
5. Reviewer Agent is triggered by the tester comment and submits `REVIEWER DECISION: CHANGES REQUIRED` or `REVIEWER DECISION: READY FOR MANAGER APPROVAL`.
6. Manager makes the final merge/reject decision.

No agent workflow has merge permission.

## Workflow sources

- `.github/workflows/developer-agent.md`
- `.github/workflows/tester-agent.md`
- `.github/workflows/reviewer-agent.md`

GitHub Agentic Workflows compiles these Markdown sources into `.lock.yml` workflows using `gh aw compile`.

## One-time setup

```bash
gh auth login --scopes repo,workflow
gh extension install github/gh-aw
gh aw init --engine codex
gh aw compile
```

Review and commit the generated `.github/workflows/*.lock.yml` files.

Add the OpenAI credential as an Actions secret:

```bash
gh secret set OPENAI_API_KEY
```

Paste the API key when prompted. `CODEX_API_KEY` is also supported and takes precedence if both are configured.

## Prepared manager issue

Issue #3 contains the Windows Failover Cluster requirement and acceptance tests. Do not add the `agent-dev` label until the compiled workflows are present on the default branch and the API secret is configured.

## Live integration requirement

Static GitHub testing is not equivalent to creating a real Windows cluster. Final live validation should use an AAP/Tower test inventory or controlled integration environment and prove:

- fresh nodes create the cluster once;
- identical second run does not recreate it;
- existing requested cluster is a no-op for creation;
- node already belonging to another cluster fails safely;
- check mode does not mutate;
- already-correct quorum is a no-op.

## Approval rule

Only consider merge after CI is green, Tester Agent reports PASS, Reviewer Agent reports READY FOR MANAGER APPROVAL, and any required live Windows evidence has been reviewed. The Manager remains the only merge authority.