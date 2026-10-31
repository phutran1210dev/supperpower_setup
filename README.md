# Superpowers bootstrap

Give every AI coding agent on your team the same playbook — with one command, and without installing anything outside the project but one optional, pinned code-map binary.

`scripts/superpowers.sh` sets up [Superpowers](https://github.com/obra/superpowers) — a library of process skills such as *brainstorming*, *writing plans*, *test-driven development* and *systematic debugging* — for the agents your team uses: Claude Code, Codex, GitHub Copilot, Cursor, Gemini CLI, Antigravity and Devin (ex-Windsurf).

- **Project only.** No plugins, no marketplaces, nothing in `~/.claude`, `~/.codex` or other user config. It works on company machines that block global installs. The one exception is the code map binary in `~/.codebase-memory` (`--no-code-map` skips it).
- **Commit once, the whole team has it.** Teammates get everything by cloning the repo.
- **Safe by default.** Agents are blocked from reading secret files (`.env`, private keys, …) and steered to fast, `.gitignore`-aware search with ripgrep, subagents included.
- **A code map instead of grep-and-read, with a graph UI.** [codebase-memory](https://github.com/DeusData/codebase-memory-mcp) indexes the project — functions, calls, routes, files, in 150+ languages including shell — and every agent gets it as an MCP server, so "who calls X" or "what does this change affect" is one query, not a dozen searches and file reads. `.agents/codebase-memory ui` shows the graph in your browser.
- **Reviewers for your stack.** Twelve general specialists from [everything-claude-code](https://github.com/affaan-m/everything-claude-code) (planner, code reviewer, silent-failure hunter, …), plus the reviewer and build fixer for each stack it finds — TypeScript, React, Python, Go, Rust, Kotlin, Swift, Flutter and more — with the ECC skills they rely on. A Go service gets `go-reviewer`, not 68 agents.
- **Security audit before every release.** Cloudflare's [security-audit](https://github.com/cloudflare/security-audit-skill) skill and a `/release-audit` command, ready for the team to run on a staging, UAT or production build.
- **Pinned and checkable.** Fixed versions, so every run writes the same files; `--check` tells CI when they drift.

## Quick start

**1. Get the script.** Clone or copy this repo; keep the `scripts/` folder together.

**2. Run it on your project.**

```bash
scripts/superpowers.sh ~/code/my-app
```

Pick your agents in the menu (↑/↓, space, enter) and watch the setup run:

```
 ▗▄▄▖ ▗▄▄▖   superpowers · setup
 ▐▙▄▖ ▐▙▄▘   v7.0.1 · ECC v2.2.3 · rg 15.2.0
 ▗▄▟▌ ▐▌     ~/code/my-app

 [1/9] fetch     superpowers v7.0.1 @ 2ce8aa1         ✓  1.2s
 [2/9] skills    22 skills → .agents/skills           ✓  0.1s
 [3/9] security  2 skills · security-audit-skill @ c… ✓  0.8s
 [4/9] agents    26 subagents · ECC v2.2.3 @ c05b2d6  ✓  0.9s
 [5/9] ripgrep   15.2.0 → .agents/bin (local)         ✓  2.3s
 [6/9] code map  0.12.1 · 438 nodes · 1300 edges      ✓  7.3s
 [7/9] claude    skills · hooks · guards · CLAUDE.md  ✓  0.2s
 [8/9] codex     hooks · guards · AGENTS.md           ✓  0.1s
 [9/9] vscode    extension recommendations            ✓  0.0s
 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ 100% 12.1s

 ✦ Ready  2 tools · 24 skills · 26 subagents · 0 warnings
```

**3. Commit the generated files** and follow the `next` steps the summary prints (for example: trust the folder in Claude Code, approve the hooks in Codex).

**4. Start working.** Ask your agent for something — *"Let's build a todo app"* — and it picks the right skill on its own. Or call one directly:

| Agent | Run a skill |
|---|---|
| Claude Code, Copilot, Cursor | `/brainstorming`, `/writing-plans`, `/systematic-debugging`, … |
| Codex | `$brainstorming`, `$writing-plans`, … or pick from `/skills` |
| Gemini CLI, Antigravity, Devin | *"use the brainstorming skill"*, or just describe the task |

## Code map: codebase-memory

Agents normally learn a codebase by searching and reading file after file. The bootstrap also sets up [codebase-memory](https://github.com/DeusData/codebase-memory-mcp): one graph of the project's functions, calls, routes and files, built with tree-sitter in 150+ languages (shell included) and kept current by a file watcher while an agent runs. The agent asks `search_graph`, `trace_path` or `detect_changes` and gets file and line ranges, call paths and the impact of a change.

```bash
.agents/codebase-memory ui                     # the graph in your browser (127.0.0.1:9749, Ctrl-C to stop)
.agents/codebase-memory project                # this project's name in the index
.agents/codebase-memory cli search_graph '{"project":"<name>","query":"login"}'
```

- **Per machine, once:** the pinned, checksum-verified 0.12.1 binary (~47 MB download, ~320 MB unpacked, one static file) goes in `~/.codebase-memory`; every project on that machine shares it. Its own installer, which edits user-level agent configs, is never run. The index lives in its cache, `~/.cache/codebase-memory-mcp`.
- **Per project, committed:** a "Code map" instruction in each agent's block, the wrapper `.agents/codebase-memory`, and a `codebase-memory` server in the MCP config each agent reads (`.mcp.json`, `.vscode/mcp.json`, `.github/mcp.json`, `.cursor/mcp.json`, `.codex/config.toml`, `.gemini/settings.json`, `.agents/mcp_config.json`, `.devin/mcp_config.json`). A server of your own under that name is left alone.
- **Local only:** no telemetry, no network after the download; the UI listens on 127.0.0.1. Claude Code pre-approves the read-only tools and `index_repository`; `delete_project`, `manage_adr` and `ingest_traces` keep asking.
- **Off:** `--no-code-map` (remembered in the lock). Behind a firewall: `CODEBASE_MEMORY_MIRROR=<url>`.

## Security audit before a release

Built staging, UAT or a production candidate? Check out the commit you are shipping and run:

```
/release-audit staging          # or uat, prod — optionally quick|standard|deep and paths
```

(Codex: `$release-audit staging`.) The agent runs the security-audit skill's full six-phase audit on the source — it never probes the deployed environment — and writes `REPORT.md` and `findings.json` to `.security-audit/<env>-<date>-<commit>/`, which git ignores. The report validators need **Node.js** on the machine that runs the audit. Don't want it? `--no-security-audit`.

## Everyday commands

```bash
scripts/superpowers.sh .                        # set up / update (shows the agent picker)
scripts/superpowers.sh -t claude,copilot .      # choose agents without the picker
scripts/superpowers.sh --check .                # CI: exit 1 if the generated files are out of date
scripts/superpowers.sh --uninstall .            # remove everything it added
scripts/superpowers.sh --help                   # all options
```

Re-running is safe: it updates what it wrote, removes agents you deselected, and never touches your own files.

## Requirements

`bash`, `git` and `perl` — all ship with macOS, Linux and Git for Windows. `curl` downloads ripgrep when it isn't installed, and the code map binary (macOS and Linux). The bootstrap needs no Node or Python; only `/release-audit`'s report validators need Node.js.

## Documentation

The details live in the [wiki](../../wiki):

| | |
|---|---|
| [Usage](../../wiki/Usage) | All options, CI with `--check`, updating, uninstalling, Windows, environment variables |
| [Agents](../../wiki/Agents) | Exactly what is created for each agent, and why |
| [Guards](../../wiki/Guards) | The secret-file guard, ripgrep and the search guard, and how to tune them |
| [Security Audit](../../wiki/Security-Audit) | `/release-audit`, the security-auditor agent, reports, and what each agent supports |
| [Development](../../wiki/Development) | Code layout, tests, adding a new agent, how it works inside |

## Credits

Skills from [Superpowers](https://github.com/obra/superpowers) (MIT). Subagents from [everything-claude-code](https://github.com/affaan-m/everything-claude-code) (MIT). Security audits by Cloudflare's [security-audit-skill](https://github.com/cloudflare/security-audit-skill) (MIT). Search by [ripgrep](https://github.com/BurntSushi/ripgrep). Code map by [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) (MIT).
