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
