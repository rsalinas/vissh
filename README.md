# vissh

Jump directly to an SSH host entry in your `~/.ssh/config` (and any included files) for editing, with optional git versioning of the SSH directory.

## Features

- Opens your editor at the exact line of the matching `Host` block
- Resolves `Include` directives recursively
- Picks the most specific match when a host matches multiple patterns
- Shows a diff and asks for confirmation before writing any change
- Auto-commits each confirmed change to a git repository inside `~/.ssh`
- `vissh git <subcommand>` passes git commands through to the `~/.ssh` repo
- Bash tab completion for host names and git subcommands

## Requirements

- Bash 4+
- `git` (optional, only needed for versioning)
- An `$EDITOR` (defaults to `vim`)

## Installation

### System-wide (requires write access to `/usr/local`)

```bash
make install PREFIX=/usr/local
```

### User-local (default, installs to `~/.local`)

```bash
make install
```

### Development (symlinks so edits are live immediately)

```bash
make link
```

The Makefile installs:
- `vissh` → `$PREFIX/bin/vissh`
- Bash completion → `~/.local/share/bash-completion/completions/vissh`

## Usage

### Open a host for editing

```
vissh <host>
```

1. Finds the `Host` block that matches `<host>` in `~/.ssh/config` (and any `Include`d files).
2. Opens a **temporary copy** of the file in `$EDITOR` at the correct line.
3. After you save and quit, validates the full config with `ssh -G`.
   - If invalid: shows the error and offers to re-edit (your changes are preserved in the editor).
4. Shows a unified diff of your changes.
5. Asks for confirmation before writing to the real file.
6. If `~/.ssh` has a git repository, auto-commits the change.

### List all matching entries

```
vissh <host> --all
```

Prints every matching `Host` pattern with its file and line number, sorted by specificity (most specific first).

### List all hosts (used by tab completion)

```
vissh --list-hosts
```

---

## Git versioning

vissh can track every change to your SSH config in a git repository inside `~/.ssh`. Private keys are **never** committed (enforced via `.gitignore`).

### Initialize the repository

```
vissh git init
```

Runs `git init` in `~/.ssh` and creates a `.gitignore` that tracks only:

- `config`
- `*.pub` (public keys)
- `known_hosts`
- `authorized_keys`
- `.gitignore` itself

Make the first commit manually:

```bash
vissh git add config
vissh git commit -m "Initial commit"
```

### View history and changes

```bash
vissh git log --oneline     # commit history
vissh git diff              # uncommitted changes
vissh git status            # current state
vissh git show HEAD         # last commit details
```

### Pass any git subcommand

```
vissh git <subcommand> [args...]
```

All git subcommands are forwarded to `git -C ~/.ssh`. Potentially destructive operations (`reset`, `clean`, `restore`, `push -f`, etc.) print a warning and require explicit confirmation.

### Without a git repository

If `~/.ssh` has no `.git` directory, vissh prints a note on each edit but continues to work normally. Editing and confirmation are unaffected.

---

## How it works

1. `expand_includes` walks `~/.ssh/config` recursively following `Include` directives.
2. `scan_file` extracts every `Host` line with its file path and line number.
3. `pattern_matches` tests each `Host` pattern against the requested hostname using bash glob matching.
4. The best match is the longest (most specific) pattern.
5. The target file is copied to a temp file; the editor opens that temp file.
6. A `diff` between the original and the edited temp file is shown.
7. On confirmation, the temp file replaces the original, and a git commit is created if a repo exists.

## Tab completion

Source the completion file in your shell profile:

```bash
# ~/.bashrc or ~/.bash_profile
source ~/.local/share/bash-completion/completions/vissh
```

Or install it system-wide so bash-completion picks it up automatically:

```bash
make install PREFIX=/usr/local
```

Completion covers:
- `vissh <TAB>` — all known SSH hosts + `git`
- `vissh git <TAB>` — git subcommands (`init`, `log`, `diff`, `status`, …)
- `vissh <host> <TAB>` — `--all`
