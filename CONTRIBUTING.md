# Contributing

This is a personal configuration. Issues and patches are welcome, but it is
shaped around one machine and will stay that way.

## Conventions

**Comments explain why, not what.** The reason a value is what it is, what was
measured, what broke before. A comment restating the code is noise. Most
comments here name a specific failure — that is deliberate, and it is what makes
the file worth reading a year later.

**English everywhere** in comments, documentation and commit messages. UI labels
are German, because this desktop is used in German.

**Numbers come from measurement.** If a comment says 170 ms, or 10.01 s per
calendar, or 107 `clone()` calls, that was measured on this machine. Do not
change such a number without re-measuring, and say how you measured it.

## Commits

Commit messages are English, imperative mood, and explain the reasoning where it
is not obvious from the diff.

Do not add `Co-Authored-By:` trailers naming an AI assistant, `Generated with`
lines, or similar. A `Co-Authored-By:` naming a real person is fine — that one
carries information.

## Before opening a pull request

- Shell scripts pass `bash -n` (or `sh -n`).
- Python passes `python3 -c "import ast; ast.parse(open(f).read())"`.
- Lua config still loads: `hyprctl reload` returns `ok`.
- Quickshell starts with no errors and three layers present:
  `hyprctl layers | grep -c 'namespace: quickshell'` → 3
- Nothing personal is added: no coordinates, no SSIDs, no tokens, no absolute
  paths beyond the `/home/woofi` ones already documented in INSTALL.md.

Run the secret scan:

```sh
gitleaks dir . --no-banner --redact
```
