# git-commitors

Select commit author from a configured list. Useful for shared machines, pair programming, or switching between work/personal identities.

[Русская версия](README.ru.md)

## How it works

You configure a list of authors in `~/.git-commitors`. When you commit, git-commitors shows a selection dialog (zenity/whiptail/terminal) and applies the chosen author.

Two modes available:

| Mode | How | Pros | Cons |
|------|-----|------|------|
| **alias** (recommended) | `git ci -m "msg"` | Works without default git author, no double GPG prompt, clean single commit | Requires using `git ci` instead of `git commit` |
| **hook** | `git commit -m "msg"` | Transparent, works with any git workflow/GUI | Requires default git author configured, GPG prompt on initial commit if `commit.gpgsign=true` |

## Install

```bash
git clone <repo-url> git-commitors
cd git-commitors
./install.sh
```

Interactive prompt will ask for the mode (alias/hook/both), or pass directly:

```bash
./install.sh --alias   # recommended
./install.sh --hook    # global hook
./install.sh --both
```

Remote install:

```bash
curl -fsSL https://raw.githubusercontent.com/davydes/git-commitors/master/get.sh | bash
```

### Uninstall

```bash
./uninstall.sh
```

Removes binary, libraries, global hooks, and `git ci` alias. Config file (`~/.git-commitors`) is preserved.

## Config

File: `~/.git-commitors`

```
# Format: Name | Email | GPG Key ID (optional)

@git
John Doe | john@company.com | ABCD1234EF567890
John Doe | john@personal.com
Jane Smith | jane@work.org
```

- `@git` — imports current user from `git config` (user.name, user.email, user.signingkey)
- GPG key is optional — omit the third field or leave it empty
- Lines starting with `#` are comments

Default config contains only `@git`. If no config file exists, the current git user is used automatically.

### Edit config

```bash
git commitors config    # opens in $EDITOR
git commitors import    # adds @git directive
git commitors list      # shows parsed authors
```

## Usage

### Alias mode (recommended)

```bash
git ci -m "commit message"
git ci -a -m "stage and commit"
git ci                          # opens editor
```

All `git commit` arguments are passed through.

With a single author in config — auto-selected, no dialog. With multiple — picker appears (zenity on desktop, whiptail in terminal, bash `select` as fallback).

### Hook mode

```bash
git commit -m "message"         # picker appears automatically
GIT_COMMITORS_SKIP=1 git commit -m "msg"  # skip picker once
```

### Per-repo hooks (instead of global)

```bash
cd /path/to/repo
git commitors init       # install hooks in this repo
git commitors remove     # remove hooks from this repo
```

## Picker UI

Detected automatically:

| Environment | UI |
|-------------|-----|
| Desktop (X11/Wayland) + zenity | GUI dialog |
| Desktop + kdialog | KDE dialog |
| Terminal + whiptail | TUI menu |
| Terminal + dialog | TUI menu |
| Terminal (bare) | bash `select` |
| No TTY / CI | skipped |

Override: `GIT_COMMITORS_UI=tui` or `GIT_COMMITORS_UI=gui-zenity`, etc.

## Environment variables

| Variable | Description |
|----------|-------------|
| `GIT_COMMITORS_CONFIG` | Override config file path |
| `GIT_COMMITORS_UI` | Force UI: `gui`, `tui`, `gui-zenity`, `tui-whiptail`, `none` |
| `GIT_COMMITORS_SKIP=1` | Skip author selection for one commit |

## Edge cases

| Scenario | Behavior |
|----------|----------|
| 1 author in config | Auto-selected, no dialog |
| 0 authors / no config | Alias mode: error. Hook mode: pass through |
| User cancels dialog | Alias mode: abort. Hook mode: commit with default author |
| CI/CD (`$CI`, `$GITHUB_ACTIONS`, etc.) | Hook skipped |
| `git merge` / `git rebase` | Hook skipped |
| `commit.gpgsign=true`, author without GPG key | Alias mode: `--no-gpg-sign` passed, no prompt. Hook mode: GPG prompt happens on initial commit |

## Project structure

```
bin/git-commitors              # CLI manager + commit wrapper
lib/gc-common.sh               # Config parsing, display detection
lib/gc-picker.sh               # Author picker (zenity/whiptail/dialog/select)
hooks/prepare-commit-msg       # Hook: shows picker, saves selection
hooks/post-commit              # Hook: applies author via amend
install.sh                     # Installer (interactive mode selection)
uninstall.sh                   # Uninstaller
get.sh                         # Remote installer (curl | bash)
```

## Requirements

- bash 4+
- git
- Optional: zenity (GUI), whiptail (TUI, preinstalled on Ubuntu)

## License

MIT
