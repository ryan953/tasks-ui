# Dex Tasks

A native macOS app for [`dex`](https://www.npmjs.com/package/@zeeg/dex) tasks. Tasks
on the left, the task you picked on the right, and everything editable in place.

| Sidebar | Detail |
| --- | --- |
| ![Task list](docs/sidebar.png) | ![Task detail](docs/detail.png) |

## What it does

- **Browse** the task tree, with subtasks nested under their parent and a
  `done/total` count on every branch.
- **Search** descriptions, context, results and IDs. A parent stays visible when one
  of its subtasks matches, so nothing hides.
- **Filter** by ready / blocked / pending / completed, and sort by priority, created,
  updated or name.
- **Edit** description, context and priority, then Save — only the fields you changed
  are sent.
- **Edit dependencies**: add and remove blockers, and reparent a task. The pickers
  leave out anything that would make a cycle, so `dex` never has to reject it.
- **Mark as done** with a result, and reopen a task you finished too early.
- **Follow along**: the window refreshes when anything else changes a task, so the
  CLI or an agent editing the same store shows up immediately.

## Install

Download the zip from [Releases](../../releases), unzip it, and drag
**Dex Tasks.app** to `/Applications`.

The build is not signed with an Apple Developer certificate, so the first launch
needs **right-click → Open**, or:

```sh
xattr -dr com.apple.quarantine "/Applications/Dex Tasks.app"
```

Requires macOS 14 or later and the [`dex`](https://www.npmjs.com/package/@zeeg/dex)
CLI:

```sh
npm install -g @zeeg/dex
```

## How it talks to dex

Every read and write goes through the `dex` CLI rather than the JSON on disk, so
`dex` stays the only writer: it keeps `blockedBy` and `blocks` in step on both tasks,
maintains `parent_id`/`children`, and refuses dependency cycles.

There is exactly one exception. `dex` has no un-complete command, so **Reopen**
rewrites `completed`, `completed_at` and `result` in the task's JSON file directly —
the same thing the
[VS Code extension](https://github.com/ryan953/vscode-dex-tasks) does. No
relationship fields are touched, so nothing `dex` keeps in sync can drift.

### Finding dex

A launched `.app` inherits only `/usr/bin:/bin:/usr/sbin:/sbin`, and `dex` is a Node
script with a `#!/usr/bin/env node` shebang — under that `PATH` it fails with
`env: node: No such file or directory` and the app would look empty for no visible
reason. So at startup the app asks your login shell for its `PATH` and runs `dex`
with it. That covers Homebrew, nvm, fnm, volta, mise and asdf without special cases.

If your setup still needs a nudge, set an explicit path in **Settings (⌘,)**, along
with a storage path if you want to work against a store other than the configured
one.

## Keyboard

| | |
| --- | --- |
| `⌘N` | New task |
| `⌘R` | Refresh |
| `⌘S` | Save changes |
| `⌘↩` | Mark as done / create the task |
| `⌘,` | Settings |

## Building

```sh
swift build            # debug
swift test             # unit, integration and view-snapshot suites
Scripts/bundle.sh      # dist/Dex Tasks.app
Scripts/bundle.sh --version 1.2.3 --universal
```

The app icon is drawn by `Scripts/make-icon.swift` at bundle time, so no binary
artwork is kept in the repository.

### Tests

- `Tests/DexKitTests` — decoding, argument building, the task tree, and an
  integration suite that drives the real `dex` binary against a temporary store
  (skipped when `dex` is not installed).
- `Tests/DexUITests` — renders the real views into an offscreen window and writes
  PNGs to `.build/snapshots`, so a layout regression is visible rather than
  described.

## Releasing

Push a tag. The workflow builds a universal binary, bundles it, and attaches the zip
to a GitHub release.

```sh
git tag v0.1.0 && git push origin v0.1.0
```

## Licence

MIT
