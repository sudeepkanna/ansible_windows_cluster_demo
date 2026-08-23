# Agent Demo: Windows Failover Cluster Idempotency

This branch is a safe demonstration workspace for agent-style code review and remediation.

## Goal

Harden the Windows Failover Cluster automation for idempotency and safer reruns.

## Agent roles simulated

1. **Planner**
   - Inspect orchestration flow and determine where state must be discovered before change operations.
2. **Reviewer**
   - Check whether cluster creation and quorum configuration are guarded by current state.
3. **Implementer**
   - Make minimal changes on this branch only.
4. **Verifier**
   - Compare the branch against `main` and confirm rerun behavior is state-driven.

## Findings so far

- The role already determines `cluster_primary` once and runs `cluster_state.yml` before mutating operations.
- `create_cluster.yml` only invokes `win_cluster_create` when `cluster_present` is false.
- `quorum.yml` calls `win_cluster_quorum_ensure`, whose contract is to compare desired and current quorum before changing it.
- All cluster-wide creation/quorum actions are limited to the primary node.

## Idempotency model

A second run should behave as follows:

- Existing cluster detected -> creation path skipped.
- Existing membership discovered -> conflicting-cluster safety check still runs.
- Quorum report is read-only when the cluster already exists.
- No cluster creation task should report changed on an already-correct cluster.

## Next implementation steps

- Review each custom module in `library/` for strict `changed` semantics and check-mode support.
- Add automated syntax/idempotency validation in CI.
- Add a test scenario that executes the role twice and asserts zero changes on the second run.

No production branch files were modified by this demo.