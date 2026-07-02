# AGENTS.md

## Project Overview
- **Project:** Toonix — a NixOS flake that ports Omarchy v3.8.2 into a QEMU-friendly NixOS desktop.
- **Target user:** developers and Linux desktop users who want an Omarchy-style Hyprland setup on NixOS.
- **My skill level:** intermediate.
- **Stack:** NixOS, Home Manager, Hyprland, UWSM, QEMU, bash, and the bundled Omarchy source tree.

## Commands
- **Install:** `bash vm/install-in-vm.sh` from the live NixOS installer VM, or follow `INSTALL.md`.
- **Dev:** edit the flake and modules in this repo; use `just vm` or `vm/run-toonix-vm.sh` for VM testing.
- **Build:** `just build`
- **Test:** `just check`
- **Lint:** `just fmt` and `git diff --check`

## Do
- Read existing code before modifying anything.
- Match existing patterns, naming, and style.
- Handle errors gracefully; no silent failures.
- Keep changes small and scoped to what was asked.
- Run dev/build checks after changes when available.
- Ask clarifying questions before guessing when the risk is high.

## Don't
- Install new dependencies without asking.
- Delete or overwrite files without confirming.
- Hardcode secrets, API keys, or credentials.
- Rewrite working code unless explicitly asked.
- Push, deploy, or force-push without permission.
- Make changes outside the scope of the request.

## When Stuck
- If a task is large, break it into steps and confirm the plan first.
- If you cannot fix an error in 2 attempts, stop and explain the issue.

## Testing
- Run existing tests after any change when the tools are available.
- Add focused tests or CI coverage for new behavior when practical.
- Never skip or delete tests to make things pass.

## Git
- Small, focused commits with descriptive messages.
- Never force push.

## Response Style
- Always respond with clear and concise messages.
- Use plain English when explaining to the user.
- Avoid long sentences, complex words, or long paragraphs.

# Style

- Two spaces for indentation, no tabs
- Use bash 5 conditionals: use `[[ ]]` for string/file tests and `(( ))` for numeric tests
- In `[[ ]]`, don't quote variables, but do quote string literals when comparing values (e.g., `[[ $branch == "dev" ]]`)
- Prefer `(( ))` over numeric operators inside `[[ ]]` (e.g., `(( count < 50 ))`, not `[[ $count -lt 50 ]]`)
- For strings/paths with spaces, quote them instead of escaping spaces with `\ ` (e.g., `"$APP_DIR/Disk Usage.desktop"`, not `$APP_DIR/Disk\ Usage.desktop`)
- Shebangs must use `#!/bin/bash` consistently (never `#!/usr/bin/env bash`)
- Scripts under `install/` and `migrations/` may be sourced and intentionally omit shebangs

# Command Naming

All commands start with `omarchy-`. Prefixes indicate purpose.

The authoritative command group list lives in `bin/omarchy` in `GROUP_DESCRIPTIONS`. Keep `GROUP_DESCRIPTIONS` updated when adding a new command prefix.

Common prefixes include:

- `cmd-` - check if commands exist, misc utility commands
- `capture-` - screenshots, screen recordings, and other capture tools
- `pkg-` - package management helpers
- `hw-` - hardware detection (return exit codes for use in conditionals)
- `refresh-` - copy default config to user's `~/.config/`
- `restart-` - restart a component
- `launch-` - open applications
- `install-` - install optional software
- `setup-` - interactive setup wizards
- `toggle-` - toggle features on/off
- `theme-` - theme management
- `update-` - update components

Other current prefixes include:

- `ac-`, `audio-`, `battery-`, `branch-`, `brightness-`, `channel-`, `config-`, `debug-`, `dev-`, `drive-`, `first-`, `font-`, `haptic-`, `hibernation-`, `hook-`, `hyprland-`, `menu-`, `migrate-`, `notification-`, `npx-`, `plymouth-`, `powerprofiles-`, `reinstall-`, `remove-`, `screensaver-`, `show-`, `snapshot-`, `state-`, `sudo-`, `swayosd-`, `system-`, `transcode-`, `tui-`, `tz-`, `upload-`, `version-`, `voxtype-`, `webapp-`, `wifi-`, `windows-`

# Command Metadata

Commands in `bin/` can declare CLI metadata in comments near the top of the file. `bin/omarchy` scans the first 80 lines, and tests expect command metadata to remain valid.

Supported metadata keys:

- `# omarchy:summary=...` - short help text
- `# omarchy:group=...` - command group when it differs from the filename-derived prefix
- `# omarchy:name=...` - command name within the group
- `# omarchy:args=...` - usage arguments
- `# omarchy:examples=...` - examples separated with ` | `
- `# omarchy:alias=...` / `# omarchy:aliases=...` - alternate routes
- `# omarchy:hidden=true` - hide from default command listings
- `# omarchy:requires-sudo=true` - mark commands that require sudo

Prefer explicit metadata for user-facing commands. Keep routes consistent with the filename unless there is a deliberate alias or compatibility route.

Example:

```bash
# omarchy:summary=Take a screenshot
# omarchy:group=capture
# omarchy:args=[smart|region|windows|fullscreen] [slurp|copy]
# omarchy:examples=omarchy screenshot | omarchy capture screenshot region
# omarchy:aliases=omarchy screenshot
```

# Install Scripts

Install entry points (`install.sh`, `boot.sh`) use `#!/bin/bash`. Many scripts under `install/` are sourced via `run_logged` and intentionally do not have shebangs.

Install stage files follow this pattern:

- `install/*/all.sh` lists scripts in execution order
- leaf scripts are sourced by `run_logged $OMARCHY_INSTALL/path/to/script.sh`
- avoid `exit` in sourced install scripts unless intentionally aborting the install
- use `$OMARCHY_INSTALL` and `$OMARCHY_PATH` instead of hard-coded Omarchy paths
- keep hardware-specific logic under `install/config/hardware/`
- prefer helper commands for package and command checks where available

Raw `command -v`, `pacman`, and `pacman-key` are acceptable in bootstrap/preflight/package-helper contexts where the helper commands may not be available yet or where direct package-manager behavior is the point of the script.

# Helper Commands

Use these instead of raw shell commands:

- `omarchy-cmd-missing` / `omarchy-cmd-present` - check for commands
- `omarchy-pkg-missing` / `omarchy-pkg-present` - check for packages
- `omarchy-pkg-add` - install packages (handles both pacman and AUR)
- `omarchy-hw-asus-rog` - detect ASUS ROG hardware (and similar `hw-*` commands)

Exceptions are allowed for bootstrap, preflight, migration, and package-helper scripts where the helper may not be available yet, where the helper itself is being implemented, or where direct package-manager behavior is required.

# Config Structure

- `config/` - default configs copied to `~/.config/`
- `default/themed/*.tpl` - templates with `{{ variable }}` placeholders for theme colors
- `themes/*/colors.toml` - theme color definitions (accent, background, foreground, color0-15)

# Visual Changes

When making visual changes, such as Waybar styles or desktop appearance, always take and analyze a screenshot after applying the change to verify the result. Use `omarchy capture screenshot fullscreen save` for fullscreen screenshots.

# Refresh Pattern

To copy a default config to user config with automatic backup:

```bash
omarchy-refresh-config hypr/hyprlock.conf
```

This copies `~/.local/share/omarchy/config/hypr/hyprlock.conf` to `~/.config/hypr/hyprlock.conf`.

# Migrations

To create a new migration, run `omarchy-dev-add-migration --no-edit`. This creates a migration file named after the unix timestamp of the last commit.

New migration format:
- File permissions must be `0644` (`-rw-r--r--`); migrations are sourced, not executed directly
- No shebang line
- Start with an `echo` describing what the migration does
- Use `$OMARCHY_PATH` to reference the omarchy directory
- Prefer helper commands such as `omarchy-cmd-present`, `omarchy-cmd-missing`, `omarchy-pkg-present`, and `omarchy-pkg-missing`

Some older migrations predate these rules. Do not copy older migrations that start with shebangs, omit the leading `echo`, or hard-code `~/.local/share/omarchy`.

Migrations may use raw `pacman`, `command -v`, or direct config edits when needed for historical compatibility or one-off repair work.

Example:
```bash
echo "Disable fingerprint in hyprlock if fingerprint auth is not configured"

if omarchy-cmd-missing fprintd-list || ! fprintd-list "$USER" 2>/dev/null | grep -q "finger"; then
  sed -i 's/fingerprint:enabled = .*/fingerprint:enabled = false/' ~/.config/hypr/hyprlock.conf
fi
```
