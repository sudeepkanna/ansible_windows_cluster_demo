# Manager Guide — Developer → Tester → Reviewer

This repository is prepared for a visible GitHub Agentic Workflows model using OpenAI Codex.

## Operating model

Manager (human) defines the requirement in a GitHub issue.

1. Add the label `agent-dev` to the issue.
2. **Developer Agent** reads the issue, changes code, and opens a draft PR whose title starts with `[agent-dev]`.
3. **Tester Agent** runs on the PR and posts one result comment:
   - `TESTER RESULT: PASS`, or
   - `TESTER RESULT: FAIL`.
4. **Reviewer Agent** is triggered by the tester comment, reviews developer work + tester evidence + CI, and submits:
   - `REVIEWER DECISION: CHANGES REQUIRED`, or
   - `REVIEWER DECISION: READY FOR MANAGER APPROVAL`.
5. The Manager makes the final merge/reject decision.

No agent workflow is permitted to merge the PR.

## Agent workflow sources

- `.github/workflows/developer-agent.md`
- `.github/workflows/tester-agent.md`
- `.github/workflows/reviewer-agent.md`

These are GitHub Agentic Workflow Markdown sources. `gh aw compile` generates the corresponding `.lock.yml` GitHub Actions workflows.

## One-time setup

Prerequisites:

- GitHub CLI (`gh`)
- authenticated GitHub session with workflow/repository permissions
- GitHub Agentic Workflows extension (`github/gh-aw`)
- repository secret `OPENAI_API_KEY` (or `CODEX_API_KEY`)

Run from a clone of this repository:

```bash
gh auth login --scopes repo,workflow
gh extension install github/gh-aw
gh aw init --engine codex
gh aw compile
```

Then commit the generated `.lock.yml` files.

Set the OpenAI secret without putting it in shell history when possible. GitHub documents both `OPENAI_API_KEY` and `CODEX_API_KEY`; `CODEX_API_KEY` takes precedence if both exist.

Example interactive secret command:

```bash
gh secret set OPENAI_API_KEY
```

Paste the value when prompted.

## Manager requirement template

Create an issue similar to:

```markdown
# Requirement
Make Windows Failover Cluster provisioning fully idempotent.

## Inputs
- cluster_name
- cluster_ip
- cluster_nodes
- quorum_mode
- quorum_witness_path

## Required behavior
- If the requested cluster already exists, do not recreate it.
- If a node already belongs to a different cluster, fail safely.
- If the cluster does not exist, validate prerequisites and create it exactly once.
- A second run with identical desired state must be a no-op for cluster creation.
- Mutation modules must support Ansible check mode where practical.
- Use PowerShell `Ansible.Basic` custom modules for cluster-specific state logic.
- Credentials must come from AAP/Tower credentials, never source control.
- Add tests and documentation.
```

Add label `agent-dev` only after the requirement is ready.

## Testing levels

The Tester Agent can perform static/repository validation on GitHub-hosted runners. A claim that a real cluster was successfully created requires a Windows integration environment, such as:

- an AAP/Tower test inventory; or
- a controlled self-hosted Windows/Ansible integration runner that can reach the Windows nodes.

Recommended live proof:

1. Run against nodes with no cluster: creation occurs once.
2. Run the exact same desired state again: cluster creation reports no change.
3. Run in `--check` mode: no mutation occurs.
4. Run against a node already in another cluster: workflow fails safely before creation.
5. Verify quorum rerun is also a no-op when already correct.

## Approval rule

The PR is only ready for manager consideration after:

- deterministic CI is green;
- Tester Agent has reported PASS;
- Reviewer Agent has reported READY FOR MANAGER APPROVAL;
- any required live Windows integration evidence has been reviewed.

The Manager remains the only merge authority.