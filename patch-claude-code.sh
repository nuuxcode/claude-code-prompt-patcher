#!/usr/bin/env bash
set -euo pipefail

# patch-claude-code-v2.sh — Adapted for Claude Code v2.1.111 prompt layout
#
# Changes vs upstream gist:
#   - Original patches #1, #2, #3 (Output efficiency section) REMOVED.
#     That entire section no longer exists in v2.1.111 — CC rewrote the
#     "Text output" block and softened most of the brevity hammers. The
#     old target strings are gone, so patching them is a no-op.
#   - Original patches #4 + #6 MERGED into a single patch (#4M) because
#     v2.1.111 combined them into one sentence in the "Doing tasks" section.
#   - Two new patches (#12, #13) target the remaining brevity hammers
#     that v2.1.111 introduced:
#       #12 — "End-of-turn summary: ... Nothing else."
#       #13 — "Length limits: keep text between tool calls to ≤25 words..."
#   - Patches #5, #7, #8, #9, #10, #11 unchanged (still match current cli.js).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
OS="$(uname -s)"

PLIST_LABEL="com.user.claude-code-patcher-v2"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"

find_claude_bin() {
  local candidates=(
    "$(command -v claude 2>/dev/null || true)"
    "$HOME/.local/bin/claude"
    "$HOME/.claude/bin/claude"
    "/opt/homebrew/bin/claude"
    "/usr/local/bin/claude"
  )
  for c in "${candidates[@]}"; do
    if [[ -n "$c" && -e "$c" ]]; then
      echo "$c"
      return 0
    fi
  done
  return 1
}

ensure_npm_package() {
  local npm_root
  npm_root="$(npm root -g 2>/dev/null)" || {
    echo "ERROR: npm not found or npm root -g failed" >&2
    exit 1
  }

  local cli_js="$npm_root/@anthropic-ai/claude-code/cli.js"

  if [[ ! -f "$cli_js" ]]; then
    echo "Claude Code npm package not found. Installing..." >&2
    npm install -g @anthropic-ai/claude-code || {
      echo "ERROR: Failed to install @anthropic-ai/claude-code" >&2
      exit 1
    }
  fi

  echo "$cli_js"
}

get_version() {
  local cli_js="$1"
  local pkg_json
  pkg_json="$(dirname "$cli_js")/package.json"
  if [[ -f "$pkg_json" ]]; then
    node -e "console.log(require('$pkg_json').version)" 2>/dev/null || echo "unknown"
  else
    echo "unknown"
  fi
}

PATCH_SCRIPT='
const fs = require("fs");
const cli_js = process.env.CLI_JS;
const dryRun = process.env.DRY_RUN === "1";
const checkOnly = process.env.CHECK_ONLY === "1";

let src = fs.readFileSync(cli_js, "utf8");
let applied = 0;
let skipped = 0;
let alreadyApplied = 0;
const TOTAL = 10;

function patch(label, old, replacement) {
  if (src.includes(replacement)) {
    alreadyApplied++;
    if (!checkOnly) console.log("  ALREADY APPLIED: " + label);
    return;
  }
  if (!src.includes(old)) {
    skipped++;
    console.log("  SKIP (not found): " + label);
    return;
  }
  if (checkOnly) {
    console.log("  NOT APPLIED: " + label);
    return;
  }
  const occurrences = src.split(old).length - 1;
  src = src.split(old).join(replacement);
  applied += occurrences;
  console.log("  OK (" + occurrences + "x): " + label);
}

// ===========================================================================
// PATCH 4M (merged original #4 + #6): Anti-gold-plating + three-lines rule
// ===========================================================================
patch(
  "Merged anti-gold-plating + three-lines rule",
  "Don\u0027t add features, refactor, or introduce abstractions beyond what the task requires. A bug fix doesn\u0027t need surrounding cleanup; a one-shot operation doesn\u0027t need a helper. Don\u0027t design for hypothetical future requirements. Three similar lines is better than a premature abstraction. No half-finished implementations either.",
  "Don\u0027t add unrelated features or speculative improvements. However, if adjacent code is broken, fragile, or directly contributes to the problem being solved, fix it as part of the task. A bug fix should address related issues discovered during investigation. Use judgment about when to extract shared logic — avoid premature abstractions for hypothetical reuse, but do extract when duplication causes real maintenance risk. No half-finished implementations either."
);

// ===========================================================================
// PATCH 5: Error handling — stop telling the model to skip it
// ===========================================================================
patch(
  "Skip error handling instruction",
  "Don\u0027t add error handling, fallbacks, or validation for scenarios that can\u0027t happen. Trust internal code and framework guarantees. Only validate at system boundaries (user input, external APIs). Don\u0027t use feature flags or backwards-compatibility shims when you can just change the code.",
  "Add error handling and validation at real boundaries where failures can realistically occur (user input, external APIs, I/O, network). Trust internal code and framework guarantees for truly internal paths. Don\u0027t use feature flags or backwards-compatibility shims when you can just change the code."
);

// ===========================================================================
// PATCH 7: Subagent addendum — strengthen completeness over gold-plate fear
// ===========================================================================
patch(
  "Subagent gold-plate instruction",
  "Complete the task fully\u2014don\u0027t gold-plate, but don\u0027t leave it half-done.",
  "Complete the task fully and thoroughly. Do the work that a careful senior developer would do, including edge cases and fixing obviously related issues you discover. Don\u0027t add purely cosmetic or speculative improvements unrelated to the task."
);

// ===========================================================================
// PATCH 8: Explore agent — remove speed-over-thoroughness bias
// ===========================================================================
patch(
  "Explore agent speed note",
  "NOTE: You are meant to be a fast agent that returns output as quickly as possible. In order to achieve this you must:\n- Make efficient use of the tools that you have at your disposal: be smart about how you search for files and implementations\n- Wherever possible you should try to spawn multiple parallel tool calls for grepping and reading files\n\nComplete the user\u0027s search request efficiently and report your findings clearly.",
  "NOTE: Be thorough in your exploration. Use efficient search strategies but do not sacrifice completeness for speed:\n- Make efficient use of the tools that you have at your disposal: be smart about how you search for files and implementations\n- Wherever possible you should try to spawn multiple parallel tool calls for grepping and reading files\n- When the caller requests \"very thorough\" exploration, exhaust all reasonable search strategies before reporting\n\nComplete the user\u0027s search request thoroughly and report your findings clearly."
);

// ===========================================================================
// PATCH 9: Tone — remove redundant "short and concise"
// ===========================================================================
patch(
  "Short and concise in tone",
  "Your responses should be short and concise.",
  "Your responses should be clear and appropriately detailed for the complexity of the task."
);

// ===========================================================================
// PATCH 10: Subagent output — stop suppressing code context
// ===========================================================================
patch(
  "Subagent code snippet suppression",
  "Include code snippets only when the exact text is load-bearing (e.g., a bug you found, a function signature the caller asked for) \u2014 do not recap code you merely read.",
  "Include code snippets when they provide useful context (e.g., bugs found, function signatures, relevant patterns, code that informs the decision). Summarize rather than quoting large blocks verbatim."
);

// ===========================================================================
// PATCH 11: Scope matching — allow necessary adjacent work
// ===========================================================================
patch(
  "Match scope instruction",
  "Match the scope of your actions to what was actually requested.",
  "Match the scope of your actions to what was actually requested, but do address closely related issues you discover during the work when fixing them is clearly the right thing to do."
);

// ===========================================================================
// PATCH 12 (new for v2.1.111): soften end-of-turn summary hammer
// ===========================================================================
patch(
  "End-of-turn summary hammer",
  "End-of-turn summary: one or two sentences. What changed and what\u0027s next. Nothing else.",
  "End-of-turn summary: concise but complete. What changed, what\u0027s next, and any important caveats or unverified assumptions. Keep it tight, but don\u0027t omit load-bearing information."
);

// ===========================================================================
// PATCH 13 (new for v2.1.111): soften numeric length anchors
// ===========================================================================
patch(
  "Numeric length anchors",
  "Length limits: keep text between tool calls to \u226425 words. Keep final responses to \u2264100 words unless the task requires more detail.",
  "Length guidance: keep text between tool calls short and focused. Keep final responses appropriately detailed for the complexity of the task — err on the side of completeness when reporting work done or explaining non-trivial results."
);

// ===========================================================================
// PATCH 14 (new — audit find): Subagent "only needs the essentials" hammer
// Found in KNK constant — the entry prompt for every fork/subagent.
// Tells the agent to strip its report to essentials, causing caveats and
// unverified assumptions to get dropped in relay to the user.
// ===========================================================================
patch(
  "Subagent report essentials hammer",
  "When you complete the task, respond with a concise report covering what was done and any key findings — the caller will relay this to the user, so it only needs the essentials.",
  "When you complete the task, respond with a thorough report covering what was done, key findings, caveats, and any unverified assumptions — the caller will relay this to the user, so include everything they need to verify and act on your work."
);

// ===========================================================================
// PATCH 15 (new — audit find): "don\u0027t create planning/analysis files" rule
// Found in the # Tone and style block near the no-comments rule.
// Blocks the model from using files to structure multi-step work, which
// hurts reviewability and context survival across compactions.
// ===========================================================================
patch(
  "Don\u0027t create planning documents rule",
  "Don\u0027t create planning, decision, or analysis documents unless the user asks for them — work from conversation context, not intermediate files.",
  "Create planning, decision, or analysis documents when they materially help the work (multi-step plans, research findings, debugging notes, architectural decisions) — files persist across compaction and make work reviewable. For small, single-step tasks, work from conversation context."
);

// ===========================================================================
// Results
// ===========================================================================
if (checkOnly) {
  console.log("\n" + alreadyApplied + " applied, " + (TOTAL - alreadyApplied - skipped) + " not applied, " + skipped + " not found in this version");
  process.exit(alreadyApplied === TOTAL ? 0 : 1);
}

if (!dryRun && applied > 0) {
  fs.writeFileSync(cli_js, src, "utf8");
}
console.log("\nPatches applied: " + applied + ", already applied: " + alreadyApplied + ", skipped: " + skipped + " / " + TOTAL + " total");
if (dryRun) console.log("(dry run — no files modified)");
if (skipped > 2) {
  console.log("WARNING: many patches skipped — Claude Code may have changed its prompt format.");
}
'

MODE="${1:-apply}"

case "$MODE" in
  --dry-run)
    CLI_JS=$(ensure_npm_package)
    VERSION=$(get_version "$CLI_JS")
    echo "Claude Code v$VERSION — dry run (v2 script, 10 patches)"
    echo ""
    DRY_RUN=1 CHECK_ONLY=0 CLI_JS="$CLI_JS" node -e "$PATCH_SCRIPT"
    exit 0
    ;;

  --check)
    CLI_JS=$(ensure_npm_package)
    VERSION=$(get_version "$CLI_JS")
    echo "Claude Code v$VERSION — checking patch status"
    echo ""
    DRY_RUN=0 CHECK_ONLY=1 CLI_JS="$CLI_JS" node -e "$PATCH_SCRIPT"
    exit $?
    ;;

  --restore)
    # Also uninstall watcher if present
    if [[ -f "$PLIST_PATH" ]]; then
      launchctl unload "$PLIST_PATH" 2>/dev/null || true
      rm -f "$PLIST_PATH"
      echo "Removed watcher: $PLIST_LABEL"
    fi
    CLI_JS=$(ensure_npm_package)
    BACKUP="$CLI_JS.backup"
    if [[ -f "$BACKUP" ]]; then
      cp "$BACKUP" "$CLI_JS"
      echo "Restored $CLI_JS from backup"
    else
      echo "No backup found at $BACKUP"
    fi
    exit 0
    ;;

  --watch)
    # First apply patches
    "$SCRIPT_PATH"
    echo ""
    echo "=== Installing launchd watcher ==="

    CLI_JS=$(ensure_npm_package)
    NODE_PATH_BIN="$(command -v node)"
    mkdir -p "$HOME/Library/LaunchAgents" "$HOME/.claude"

    cat > "$PLIST_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$PLIST_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$SCRIPT_PATH</string>
    <string>--apply-quiet</string>
  </array>
  <key>WatchPaths</key>
  <array>
    <string>$CLI_JS</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>$(dirname "$NODE_PATH_BIN"):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
  </dict>
  <key>StandardOutPath</key>
  <string>$HOME/.claude/patch.log</string>
  <key>StandardErrorPath</key>
  <string>$HOME/.claude/patch.log</string>
  <key>RunAtLoad</key>
  <false/>
  <key>ThrottleInterval</key>
  <integer>5</integer>
</dict>
</plist>
EOF

    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    launchctl load "$PLIST_PATH"

    echo ""
    echo "Installed launchd watcher: $PLIST_LABEL"
    echo "Watching: $CLI_JS"
    echo "Log:      ~/.claude/patch.log"
    echo ""
    echo "When brew upgrade replaces cli.js, the watcher re-runs the patcher."
    echo "Self-loop prevented: script only writes cli.js when changes are applied,"
    echo "so running on an already-patched file is a no-op and won't re-trigger."
    echo ""
    echo "To remove: $0 --unwatch"
    exit 0
    ;;

  --unwatch)
    if [[ -f "$PLIST_PATH" ]]; then
      launchctl unload "$PLIST_PATH" 2>/dev/null || true
      rm -f "$PLIST_PATH"
      echo "Removed watcher: $PLIST_LABEL"
    else
      echo "No watcher installed at $PLIST_PATH"
    fi
    exit 0
    ;;

  --apply-quiet)
    # Called by launchd — run apply silently-ish, log to stdout (plist captures it)
    echo "[$(date)] Watcher triggered — checking cli.js patch state"
    CLI_JS=$(ensure_npm_package)
    BACKUP="$CLI_JS.backup"
    if [[ ! -f "$BACKUP" ]]; then
      cp "$CLI_JS" "$BACKUP"
      echo "Backed up to $BACKUP"
    fi
    DRY_RUN=0 CHECK_ONLY=0 CLI_JS="$CLI_JS" node -e "$PATCH_SCRIPT"
    echo "[$(date)] Done"
    exit 0
    ;;

  apply|"")
    echo "=== Claude Code Prompt Patcher (v2 — adapted for v2.1.111) ==="
    echo ""
    CLAUDE_BIN=$(find_claude_bin) || { echo "ERROR: claude binary not found"; exit 1; }
    echo "Claude binary: $CLAUDE_BIN"
    CLI_JS=$(ensure_npm_package)
    VERSION=$(get_version "$CLI_JS")
    echo "NPM cli.js: $CLI_JS"
    echo "Version: $VERSION"
    echo ""
    BACKUP="$CLI_JS.backup"
    if [[ ! -f "$BACKUP" ]]; then
      cp "$CLI_JS" "$BACKUP"
      echo "Backed up to $BACKUP"
    fi
    DRY_RUN=0 CHECK_ONLY=0 CLI_JS="$CLI_JS" node -e "$PATCH_SCRIPT"
    local_version=$(node "$CLI_JS" --version 2>&1 || true)
    if [[ -z "$local_version" || "$local_version" == *"Error"* ]]; then
      echo "ERROR: patched cli.js failed to run, restoring backup" >&2
      cp "$BACKUP" "$CLI_JS"
      exit 1
    fi
    echo ""
    echo "Done. Start a new claude session to use patched prompts."
    exit 0
    ;;

  --help|-h)
    echo "Usage: $0 [--dry-run | --check | --restore | --watch | --unwatch | --help]"
    echo ""
    echo "  (no args)  Apply patches to npm cli.js (creates .backup on first run)"
    echo "  --dry-run  Preview without modifying anything"
    echo "  --check    Check which patches are currently applied"
    echo "  --restore  Copy .backup back over cli.js (and remove watcher if present)"
    echo "  --watch    Apply patches + install launchd watcher that re-patches"
    echo "             after brew upgrade replaces cli.js"
    echo "  --unwatch  Remove the launchd watcher only"
    exit 0
    ;;

  *)
    echo "Unknown option: $MODE"
    exit 1
    ;;
esac
