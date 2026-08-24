#!/bin/sh
# claude/.claude/settings.json is unlike every other file in this repo: it is
# the live file Claude Code READS AND WRITES, reached through a symlink (see
# the clear_stow_conflicts comment in install.sh). Tracking the real file is
# deliberate — it means a config change made in a session lands in the repo
# instead of needing a hand-merge. The cost is that Claude Code, not a human,
# decides what gets written there, and this repo is PUBLIC.
#
# That combination has already misfired once: an auto-mode onboarding pass
# wrote an `autoMode` block into this file containing an employer's org name,
# private repo, CI secret NAMES, internal service inventory, internal
# hostnames, and the mechanism gating its production deploys. No secret
# values — but a reconnaissance map of someone else's infrastructure, one
# `git push` from being public. It was caught by reading a diff. This test
# exists so the next one does not depend on anyone reading a diff.
#
# The rule it enforces: this file holds GENERIC, PORTABLE preferences only.
# Anything machine-specific, employer-specific, or project-specific belongs in
# that project's own .claude/settings.local.json (gitignored), where it is also
# closer to the code it describes.
#
# NB: this test deliberately contains no employer name, domain, or project
# name. Hardcoding those to grep for them would leak the very identifiers it
# is meant to keep out of a public repo. Every pattern below is generic.
HERE="$(dirname "$0")"
. "$HERE/lib.sh"
REPO="$(cd "$HERE/.." && pwd)"
SETTINGS="$REPO/claude/.claude/settings.json"

[ -r "$SETTINGS" ] && pass "settings.json is readable" \
  || fail "settings.json is readable"

# A guard that skips when its tooling is absent is not a guard. jq is already
# required by install.sh and statusline-command.sh, so demand it.
if command -v jq >/dev/null 2>&1; then
  pass "jq is available"
else
  fail "jq is available (cannot validate settings.json without it)"
  finish
fi

jq -e . "$SETTINGS" >/dev/null 2>&1 \
  && pass "settings.json is valid JSON" \
  || fail "settings.json is valid JSON (a malformed file silently disables ALL settings in it)"

# ── keys that must never be committed here ───────────────────
# Each of these is a known carrier of machine-local or organisational detail.
# They are called out separately from the unknown-key case below so the failure
# message can say where the content belongs instead of just "unexpected".
#
#   autoMode        - allow/soft_deny/hard_deny rules and the classifier's
#                     `environment` block: org names, hosts, secret names,
#                     deploy gates. This is the key that misfired.
#   env             - arbitrary environment variables, i.e. a natural home for
#                     tokens someone sets "just for now".
#   apiKeyHelper / awsCredentialExport / awsAuthRefresh / gcpAuthRefresh /
#   otelHeadersHelper / proxyAuthHelper
#                   - absolute paths to credential-minting scripts on THIS box.
#   sandbox         - credentials.files / credentials.envVars name real secret
#                     files and variables; network.allowedDomains names
#                     internal hosts.
#   claudeMd        - managed-memory prose; org policy text, not a preference.
#   sshConfigs      - hostnames, usernames, identity-file paths.
#   remote          - environment IDs tied to one account.
#   pluginConfigs   - per-plugin user config; carries project values.
#   autoMemoryDirectory / plansDirectory
#                   - machine paths.
#   companyAnnouncements
#                   - employer-authored text.
for k in autoMode env apiKeyHelper awsCredentialExport awsAuthRefresh \
         gcpAuthRefresh otelHeadersHelper proxyAuthHelper sandbox claudeMd \
         sshConfigs remote pluginConfigs autoMemoryDirectory plansDirectory \
         companyAnnouncements; do
  if jq -e --arg k "$k" 'has($k)' "$SETTINGS" >/dev/null 2>&1; then
    fail "settings.json must not contain '$k' — move it to the relevant project's .claude/settings.local.json (gitignored), or to a machine-local file"
  else
    pass "settings.json has no '$k'"
  fi
done

# ── every other key must be a known-generic preference ───────
# An allowlist, not a denylist. Claude Code gains settings keys on its own
# schedule, and a denylist would pass silently on whichever new key first
# carries org detail. Failing on the UNKNOWN means a leak can only ever be
# loud; the cost is that adding a genuinely generic preference also requires
# adding it here, which is a deliberate one-line review step.
#
# To add a key: confirm its value would be identical on a stranger's laptop.
# If it would not, it does not belong in this file at all.
ALLOWED=" attribution includeCoAuthoredBy includeGitInstructions theme
  editorMode keybindingFlavor vimInsertModeRemaps verbose viewMode defaultView
  language outputStyle statusLine subagentStatusLine hooks permissions
  enabledPlugins extraKnownMarketplaces additionalMarketplaces
  enableAllProjectMcpServers enabledMcpjsonServers disabledMcpjsonServers
  model fallbackModel effortLevel modelSettings alwaysThinkingEnabled
  fastMode fastModePerSessionOptIn preferredNotifChannel
  skipAutoPermissionPrompt skipDangerousModePermissionPrompt
  useAutoModeDuringPlan autoCompactEnabled autoCompactWindow
  precomputeCompactionEnabled cleanupPeriodDays respectGitignore
  syntaxHighlightingDisabled spinnerTipsEnabled spinnerVerbs
  spinnerTipsOverride prefersReducedMotion showTurnDuration
  showMessageTimestamps showThinkingSummaries terminalProgressBarEnabled
  todoFeatureEnabled fileCheckpointingEnabled autoScrollEnabled
  wheelScrollAccelerationEnabled tui worktree teammateMode
  promptSuggestionEnabled emojiCompletionEnabled showClearContextOnPlanAccept
  workflowSizeGuideline workflowKeywordTriggerEnabled skillOverrides
  autoUpdatesChannel minimumVersion voice voiceEnabled spellcheck
  feedbackSurveyRate feedbackDrafts axScreenReader "
# The list above is wrapped for readability, so its entries are separated by
# newlines and indentation as well as spaces. Collapse all whitespace to single
# spaces and re-pad the ends, so the " $k " match below sees a uniform
# separator no matter where a key falls in the wrapping.
ALLOWED=" $(printf '%s' "$ALLOWED" | tr '\n\t' '  ' | tr -s ' ') "

for k in $(jq -r 'keys[]' "$SETTINGS"); do
  case "$ALLOWED" in
    *" $k "*) pass "'$k' is a known-generic preference" ;;
    *) fail "'$k' is not on the generic-preference allowlist — if its value would be identical on a stranger's laptop, add it to ALLOWED in this test; otherwise move it to a project or machine-local settings file" ;;
  esac
done

# ── value-level scan, whatever the key ───────────────────────
# An allowlisted key can still hold machine or org detail in its VALUE — a
# permission rule scoped to an absolute worktree path, a hook command pointing
# at somebody's home directory. Key-level checks alone would wave those
# through, so scan the text too.

# Absolute home paths. $HOME is portable across machines and users; the
# expanded form is not. The repo's own files use $HOME/~ throughout, so a
# literal home path here is always a machine leaking in.
if grep -nE '"[^"]*(/home/|/Users/)' "$SETTINGS" >/dev/null 2>&1; then
  fail "settings.json contains an absolute home path — use \$HOME or ~ so the value is portable"
  grep -nE '"[^"]*(/home/|/Users/)' "$SETTINGS" >&2
else
  pass "settings.json has no absolute home paths"
fi

# Secret-shaped identifiers. Naming a secret is not as bad as pasting one, but
# a list of an employer's credential variable names is exactly the content that
# made the autoMode block a problem.
if grep -nE '[A-Z0-9_]*(SECRET|PASSWORD|API_?KEY|ACCESS_TOKEN|WEBHOOK)[A-Z0-9_]*' "$SETTINGS" >/dev/null 2>&1; then
  fail "settings.json names a secret-shaped variable — credential names belong in a machine-local or project-local file"
  grep -nE '[A-Z0-9_]*(SECRET|PASSWORD|API_?KEY|ACCESS_TOKEN|WEBHOOK)[A-Z0-9_]*' "$SETTINGS" >&2
else
  pass "settings.json names no secret-shaped variables"
fi

finish
