---
name: release-audit
description: Use when the user runs /release-audit or asks for a security audit before releasing a staging, UAT or production build. Runs the security-audit skill's full audit on the commit being released and writes the report under .security-audit/.
argument-hint: "<staging|uat|prod> [quick|standard|deep] [paths...]"
disable-model-invocation: true
---

# Release audit

A pre-release security audit: the `security-audit` skill's **full audit mode**, run on the commit about to ship to staging, UAT or production, with its report kept in this repository's git-ignored `.security-audit/` folder. Running this command is the explicit full-audit request the skill asks for; the output directory is confirmed with the user in step 2.

Arguments: $ARGUMENTS

If the line above is empty or still reads as a placeholder, take the arguments from the user's message.

- **environment**: `staging`, `uat` or `prod`. Required. If it is missing or anything else, ask for it before doing anything.
- **profile**: optional `quick`, `standard` or `deep`, the skill's run profiles.
- **paths**: optional. Any other argument is a path to scope the run to.

## 1. Load the skill

Read `.agents/skills/security-audit/SKILL.md` in full, or load `security-audit` with your skill tool. This file only fills in the values its "Full audit setup" section asks for; where the two differ, the skill wins.

## 2. Resolve the setup values

1. **Source ref.** Run `git rev-parse HEAD` and `git status --porcelain`. If the build comes from another commit, stop and ask the user to check it out; do not switch branches yourself. Record a dirty worktree as the skill says.
2. **Output directory.** `.security-audit/<environment>-<YYYYMMDD>-<short sha>/`, with `-2`, `-3`, … appended if it exists (the skill needs a new directory). Verify that git ignores the whole directory: `git check-ignore -q .security-audit/<dir>/` (the trailing slash checks the directory itself, not one file in it). If it is not ignored (for example `.security-audit/.gitignore` was deleted), stop and ask for a directory outside the repository: the skill writes inside the target only when version control ignores the whole directory.
3. **Prior runs.** Every earlier `.security-audit/*/` directory with a `coverage-ledger.json` or `findings.json` is a prior run, whatever its environment: they audit the same code. Use them as the skill's "Coverage and prior runs" section says.
4. **Profile.** Use the one given. Otherwise propose `deep` for `prod` (the skill's profile "for high-stakes or large targets") and `standard`, the skill's default, for `staging` and `uat`.
5. **Scope.** Paths make a scoped run, which the report must present as partial coverage.
6. **Node.js.** Run `node --version`. The skill's validators (`validate-findings.cjs`, `validate-coverage-ledger.cjs`) need Node, and a run may only end with both validators passing or with `run_status: "incomplete"` and its exact reason. Without Node, say in the confirmation below that the run can only end incomplete.

Then confirm with the user, in one message: the commit is the one being released to the environment, the output directory, and the profile. The skill writes inside the repository only when the user explicitly selects that directory, so wait for the answer.

Add `"environment": "<environment>"` to `run-metadata.json` next to the fields the skill requires.

## 3. Run the audit

Follow the skill's six phases in order, as its parent. For a release, two of its rules matter most:

- The environment names where the code is going; the audit is still source-first. Do not probe the staging, UAT or production deployment, its endpoints or its data. A fact only the deployment can answer becomes `needs_validation`.
- Hunters and verifiers are separate, fresh agents; the agent that checks a finding never found it. If you cannot launch agents here, stop and say so instead of auditing alone.

## 4. Report back

Once the run reaches one of the skill's two terminal states, tell the user:

- the environment, commit, profile and output directory;
- `run_status`, with the reason if it is incomplete;
- confirmed findings by severity, then the number of `needs_validation` records;
- the path to `REPORT.md`.

Whether to release is the user's call: recommend, don't decide.
