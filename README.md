# Claude Code Prompt Patcher (v2)

Rebalances Claude Code's system prompts to fix corner-cutting behavior — the model is instructed to be minimal in many more places than it is instructed to be thorough. This script string-replaces the problem prompts in the installed `cli.js`.

**Forked from** [roman01la/483d1db15043018096ac3babf5688881](https://gist.github.com/roman01la/483d1db15043018096ac3babf5688881) and adapted for Claude Code **v2.1.111**. Several of the original patches' target strings no longer exist (Anthropic rewrote the "Output efficiency" section), so the script was re-audited against the current cli.js and extended with 2 new patches covering brevity hammers introduced in recent CC releases.

Tested on macOS with Claude Code installed via Homebrew. Also works on Linux with npm installs.

## Quick start

```bash
chmod +x patch-claude-code.sh
./patch-claude-code.sh --dry-run   # preview (no changes)
./patch-claude-code.sh             # apply + create .backup
./patch-claude-code.sh --check     # see which patches are in place
./patch-claude-code.sh --restore   # revert from .backup and remove watcher
./patch-claude-code.sh --watch     # apply + install launchd watcher (macOS)
./patch-claude-code.sh --unwatch   # remove watcher only
```

Requires `node`, `npm`, and an existing Claude Code install. No `sudo` needed on Homebrew installs (cli.js is user-owned).

## What gets patched (10 patches, 13 replacements)

| # | Target | Before | After |
|---|--------|--------|-------|
| 4M | **Merged**: anti-gold-plating + three-lines-vs-abstraction (one sentence in v2.1.111) | "Don't add features, refactor, or introduce abstractions beyond what the task requires... Three similar lines is better than a premature abstraction. No half-finished implementations either." | "Don't add unrelated features or speculative improvements. However, if adjacent code is broken, fragile, or directly contributes to the problem being solved, fix it as part of the task..." |
| 5 | Error handling at system boundaries | "Don't add error handling, fallbacks, or validation for scenarios that can't happen..." | "Add error handling and validation at real boundaries where failures can realistically occur (user input, external APIs, I/O, network)..." |
| 7 | Subagent task completion (hits 2× — fork and regular subagent) | "Complete the task fully—don't gold-plate, but don't leave it half-done." | "Complete the task fully and thoroughly. Do the work that a careful senior developer would do, including edge cases and fixing obviously related issues you discover..." |
| 8 | Explore agent speed-over-thoroughness | "NOTE: You are meant to be a fast agent that returns output as quickly as possible..." | "NOTE: Be thorough in your exploration. Use efficient search strategies but do not sacrifice completeness for speed..." |
| 9 | "Short and concise" tone hammer | "Your responses should be short and concise." | "Your responses should be clear and appropriately detailed for the complexity of the task." |
| 10 | Subagent code-snippet suppression | "Include code snippets only when the exact text is load-bearing... do not recap code you merely read." | "Include code snippets when they provide useful context (e.g., bugs found, function signatures, relevant patterns, code that informs the decision)..." |
| 11 | Scope matching | "Match the scope of your actions to what was actually requested." | "Match the scope of your actions to what was actually requested, but do address closely related issues you discover during the work when fixing them is clearly the right thing to do." |
| 12 | **New in v2** — end-of-turn summary "Nothing else" hammer | "End-of-turn summary: one or two sentences. What changed and what's next. Nothing else." | "End-of-turn summary: concise but complete. What changed, what's next, and any important caveats or unverified assumptions. Keep it tight, but don't omit load-bearing information." |
| 13 | **New in v2** — numeric length caps | "Length limits: keep text between tool calls to ≤25 words. Keep final responses to ≤100 words unless the task requires more detail." | "Length guidance: keep text between tool calls short and focused. Keep final responses appropriately detailed for the complexity of the task — err on the side of completeness when reporting work done..." |
| 14 | **New in v2** — subagent report "only needs the essentials" (hits 2×) | "...respond with a concise report... so it only needs the essentials." | "...respond with a thorough report covering what was done, key findings, caveats, and any unverified assumptions — the caller will relay this to the user, so include everything they need to verify and act on your work." |
| 15 | **New in v2** — "don't create planning documents" rule | "Don't create planning, decision, or analysis documents unless the user asks for them — work from conversation context, not intermediate files." | "Create planning, decision, or analysis documents when they materially help the work (multi-step plans, research findings, debugging notes, architectural decisions) — files persist across compaction and make work reviewable..." |

### Dropped from v1

Patches 1, 2, 3 (original "Output efficiency" section: "Go straight to the point... Try the simplest approach... Be extra concise", "Keep your text output brief and direct. Lead with the answer...", "If you can say it in one sentence, don't use three.") are **obsolete** — Anthropic rewrote that section in v2.1.111 into a softer "Text output (does not apply to tool calls)" block that already includes "Brief is good — silent is not." Patching them was a no-op.

Patch 6 (three-lines rule) was merged with patch 4 because v2.1.111 combined the two rules into a single sentence.

## Why these patches

Claude Code's system prompt contains roughly 15–20 separate instructions telling the model to be minimal/brief/concise and only a handful telling it to be thorough. That asymmetry leads to corner-cutting: shipping "it works" instead of "it's right", stripping caveats from reports, refusing to fix obviously-related adjacent bugs, and silently skipping verification because "the response is getting too long."

The patches don't flip the instructions — they rebalance. The model still gets told not to gold-plate, but it's also told not to leave work half-done. It's told end-of-turn summaries should be concise but must include unverified assumptions. It's told subagent reports should be thorough, not stripped to essentials.

The original gist's A/B test (unpatched vs patched CC porting box2d to JavaScript) showed the patched version produced a faithful port with dynamic AABB tree, sub-stepping, and soft contacts; the unpatched version produced a generic physics engine with brute-force broad phase. Same model, same prompt — different system prompt.

## Safety

- **Creates `cli.js.backup`** on first run (pristine original, never overwritten)
- **Self-verifies** by running `node cli.js --version` after patching; restores backup on failure
- **Idempotent** — running the patcher on an already-patched cli.js is a no-op (no file write)
- **Fully reversible** via `--restore`

## `--watch` (macOS launchd)

The `--watch` flag installs a launchd agent that watches `cli.js` itself. When `brew upgrade` (or any reinstall) replaces the file, the watcher re-runs the patcher automatically.

- Plist label: `com.user.claude-code-patcher-v2`
- Plist path: `~/Library/LaunchAgents/com.user.claude-code-patcher-v2.plist`
- Log: `~/.claude/patch.log`

**macOS sandbox auto-fix**: launchd agents on macOS cannot execute scripts from `~/Downloads`, `~/Desktop`, or `~/Documents` (blocked by the Transparency, Consent, and Control framework unless the parent has Full Disk Access). When you run `--watch`, the script **auto-copies itself to `~/.local/bin/claude-code-patcher`** and points the plist there. The original clone location can then be deleted safely — the watcher runs from `~/.local/bin/`.

**Self-loop prevention**: the patcher only writes cli.js when patches were actually applied (not on already-patched files), so the watcher fires once per upgrade and then settles.

## Integrating with an updater script

If you already have an `update-claude.sh` / `upcc` alias that does `npm install -g @anthropic-ai/claude-code@latest`, add this at the end:

```bash
# Re-apply patches after update
/path/to/patch-claude-code.sh
```

The patcher handles both "fresh install" (applies all patches) and "already latest" (all patches already applied → no-op) cases.

## Shell aliases (optional convenience)

After running `--watch` once (which copies the script to `~/.local/bin/`), add to `~/.zshrc` or `~/.bashrc`:

```bash
alias dryruncc="$HOME/.local/bin/claude-code-patcher --dry-run"
alias patchcc="$HOME/.local/bin/claude-code-patcher"
alias checkcc="$HOME/.local/bin/claude-code-patcher --check"
alias restorecc="$HOME/.local/bin/claude-code-patcher --restore"
```

If you haven't run `--watch`, you can either run it once (recommended — fixes the canonical install location) or point the aliases at your clone location directly.

## How it works

The `claude` binary on your system is typically a symlink to the npm package's `cli.js`. Claude Code ships as bundled JavaScript where the system prompt strings are plain UTF-8 embedded in the source. The patcher uses `Node.readFileSync` → `String.split/join` for exact-match replacement, then `writeFileSync`. Each patch's `old_string` is unique enough that there's no risk of replacing unrelated content.

When the installed version upgrades, target strings may change. The `--check` mode reports which patches are currently in place; the `--dry-run` mode shows which would apply. If multiple patches skip, Anthropic has likely changed the prompt format — open an issue (or update the strings yourself).

## Credits

Original script and concept: [roman01la's gist](https://gist.github.com/roman01la/483d1db15043018096ac3babf5688881). All credit for the core idea and the A/B testing methodology goes to the original author. This fork adapts the script for Claude Code v2.1.111, merges patches Anthropic combined upstream, and adds two new patches for brevity hammers introduced in recent CC releases.

## License

Same spirit as the original gist — use, modify, redistribute freely.
