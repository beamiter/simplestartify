# SimpleStartify

A small Vim 9 start screen that defaults to a fresh random UI on every entry.

SimpleStartify turns an otherwise empty Vim into a dashboard for recent files,
sessions, and a few common actions. The default `random` mode chooses one of
four built-in layouts and avoids showing the same eligible layout twice in a
row. Resizing reflows the current layout instead of unexpectedly changing it.

Like the rest of the `simple*` suite, it is Vim9script only: no Python, no
daemon, no dependencies.

## The four layouts

| Style | Character | Minimum width in the random pool |
| --- | --- | ---: |
| `minimal` | compact, left-aligned sections | 16 |
| `boxed` | a framed dashboard | 28 |
| `centered` | centered ASCII banner and entries | 24 |
| `terminal` | command-line transcript | 22 |

The width limits only select sensible candidates for random mode at the
current window width. If none of the configured candidates fits, `minimal` is
used. An explicitly requested style still renders at any width; every line is
measured with Vim's display width and shortened when necessary.

## Install

With [SimplePlug](https://github.com/beamiter/simpleplug), vim-plug, or any
plugin manager:

```vim
Plug 'beamiter/simplestartify'
```

Or by hand:

```sh
git clone https://github.com/beamiter/simplestartify \
  ~/.vim/pack/plugins/start/simplestartify
```

Nothing to build. Requires Vim 9.1 or newer.

## Configuration

Set options before the plugin loads. These are the defaults:

```vim
let g:simplestartify_auto_open = 1
let g:simplestartify_hide_intro = 1  " defaults to g:simplestartify_auto_open
let g:simplestartify_style = 'random'
let g:simplestartify_styles = ['minimal', 'boxed', 'centered', 'terminal']
let g:simplestartify_avoid_repeat = 1

let g:simplestartify_lists = [
  \ {'type': 'files'}, {'type': 'sessions'}, {'type': 'bookmarks'},
  \ {'type': 'commands'}, {'type': 'special'}]
let g:simplestartify_bookmarks = []
let g:simplestartify_commands = []
let g:simplestartify_skiplist = [
  \ '\.git[\\/]\%(COMMIT_EDITMSG\|MERGE_MSG\|TAG_EDITMSG\|SQUASH_MSG\)$',
  \ '\.git[\\/]rebase-\%(merge\|apply\)[\\/]']

let g:simplestartify_recent_count = 7   " clamped to 0..50
let g:simplestartify_session_count = 4  " clamped to 0..13
let g:simplestartify_session_dir = '~/.vim/session'
let g:simplestartify_session_persistence = 0
let g:simplestartify_session_autoload = 0
let g:simplestartify_session_savevars = []
let g:simplestartify_session_savecmds = []

let g:simplestartify_change_to_vcs_root = 0
let g:simplestartify_change_to_dir = 0
let g:simplestartify_open_action = 'edit'  " or split / vsplit / tabedit

let g:simplestartify_mru_persist = 1
let g:simplestartify_mru_max = 200    " clamped to 0..5000
" $XDG_STATE_HOME/simplestartify/mru when XDG_STATE_HOME is set:
let g:simplestartify_mru_file = '~/.vim/simplestartify-mru'
```

`g:simplestartify_style` may be `random` or one named style.
`g:simplestartify_styles` is the ordered candidate set used by random mode.
Unknown and duplicate candidates are removed; an empty result restores all
four defaults. With more than one eligible style,
`g:simplestartify_avoid_repeat` removes the current style before the next draw.

`g:simplestartify_session_persistence` controls automatic rewrites only: when
enabled, the active managed session is saved at `VimLeavePre` and before
`:SLoad` switches sessions. An explicit `:SClose` always saves the active
managed session, regardless of this setting.

`g:simplestartify_session_autoload` turns a directory into a workspace: with
no active session, a `Session.vim` in the working directory is loaded at
`VimEnter` (before the dashboard would open) and on `DirChanged`. It goes
through the ordinary load path, so the modified-buffer refusal and the
rollback snapshot still apply, and it is never recorded as the last session or
rewritten automatically -- its parent is not the configured session directory.
A `Session.vim` is sourced Vimscript, so enable this only for directories you
trust.

`g:simplestartify_session_savevars` and `g:simplestartify_session_savecmds`
add global variables and Ex command lines to every session this plugin writes.
They are appended to the temporary file before it is renamed into place, so a
session carrying extra state is still replaced atomically. A variable that is
unset, or holds something `string()` cannot render as sourceable text such as
a Funcref, is skipped rather than producing a session that fails to load.

Sessions also emit `User SimpleStartifySessionSavePre`/`SavePost` and
`LoadPre`/`LoadPost`. `SavePre` runs inside the same `try` as the write, so a
hook that throws fails the save and leaves the previous session file intact.

### Sections

`g:simplestartify_lists` decides what the dashboard shows and in what order.
Seven section types exist: `files` (recent files anywhere), `dir` (recent
files below the working directory), `project` (recent files below its Git
root), `sessions`, `bookmarks`, `commands`, and `special` (new buffer,
restyle, quit).

```vim
let g:simplestartify_lists = [
  \ {'type': 'dir', 'header': 'IN THIS PROJECT', 'limit': 5},
  \ {'type': 'files'},
  \ {'type': 'bookmarks'},
  \ {'type': 'commands'},
  \ {'type': 'sessions'},
  \ {'type': 'special'}]

let g:simplestartify_bookmarks = ['~/.vimrc', {'c': '~/.vim/config'}]
let g:simplestartify_commands = [
  \ 'SimplePlugUpdate',
  \ ['edit vimrc', 'edit $MYVIMRC'],
  \ {'u': ['update plugins', ':SimplePlugUpdate']}]
```

A file already shown by an earlier section is not repeated in a later one, so
`dir` before `files` reads as "this project first, then everything else". File
entries take the `1`..`9` keys; sessions, bookmarks and commands take letters.
A key pinned in a bookmark or command dictionary is reserved before anything
is handed out, so a session can never be given the same one, and a key the
dashboard already owns (`d`, `s`, `q`, ...) is refused and replaced with an
automatic one. Entries past the end of a pool are drawn without a marker and
opened with the cursor and `<CR>`.

`files`, `sessions` and `special` are drawn even when empty; every other
section is left out when it has nothing in it, so the default configuration
looks exactly as it did before sections existed. `:SimpleStartifyHealth` lists
each drawn section with its entry count and names any configured section left
out for being empty.

`g:simplestartify_skiplist` is a list of Vim patterns for paths that are never
recorded and never shown. It defaults to the `.git` files another tool writes
-- `COMMIT_EDITMSG` and friends -- which are readable and would otherwise take
a shortcut slot after every commit. It applies both when a buffer is recorded
and when the dashboard is drawn, so adding a pattern also hides paths recorded
earlier.

The startup screen opens only when Vim has no file arguments and the current
buffer is an unnamed, unmodified, empty normal buffer. Manual commands remain
available when automatic opening is disabled.

When a recent file is opened, `g:simplestartify_change_to_vcs_root` changes the
window-local directory to its nearest Git root when one exists. Otherwise,
`g:simplestartify_change_to_dir` changes it to the file's directory. If both
are enabled, the Git root wins when found.

## Dashboard keys

| Key | Action |
| --- | --- |
| `1` ... `9` | open a recent readable file |
| letter shown beside an entry | load that session, open that bookmark, or run that command |
| `n` | open a new empty buffer |
| `r` | deal another random style |
| `q` | quit Vim |
| `<CR>` / double-click | run the selected entry (see `g:simplestartify_open_action`) |
| `s` / `<C-x>`, `v` / `<C-v>`, `t` / `<C-t>` | run it in a split, vertical split or new tab |
| `/` / `<C-f>` | filter the entries as you type |
| `j` / `k`, `<Tab>` / `<S-Tab>` | move between actionable entries |
| `R` | refresh recent files and sessions, preserving the style and selection |
| `d` | confirm and delete the selected session |
| `D` | forget the selected recent file |
| `?` / `g?` | list every live key, including the current session letters |

Opening an entry in a split or a tab leaves the dashboard in its own window,
so you can open several files in a row; `<CR>` replaces it. Sessions ignore
the split verbs because loading one replaces the whole layout, and `s`, `t`
and `v` are never used as session shortcuts.

`/` and `<C-f>` narrow the dashboard as you type, matching case-insensitively
against each entry's label and the path, session name or command behind it.
Each keystroke re-draws from the model already in memory -- no file is stat'ed
-- and a section with no match disappears while the filter is active. `<BS>`
erases, `<CR>` opens the selection, `<Esc>` clears. This is what makes a list
longer than the nine digit shortcuts usable: entries past the end of a
shortcut alphabet are drawn without a `[key]` marker and are reached with
`j`/`k` or by typing.

Recent files come from the files this session opened, then from `v:oldfiles`.
Vim fills `v:oldfiles` once from `viminfo` during startup and never updates it
afterwards, so a dashboard reopened by `:SClose` would otherwise list only
files from earlier sessions, and a Vim started with `-i NONE` or an empty
`viminfo` would list nothing at all. The in-session record is kept in memory
and, unless `g:simplestartify_mru_persist` is 0, written to
`g:simplestartify_mru_file` at `VimLeavePre`. It is a cache: deleting it costs
history and nothing else. Missing files and duplicate absolute paths are
skipped. Sessions are ordered newest first.

## Commands

| Command | Effect |
| --- | --- |
| `:SimpleStartify [style]` | open the dashboard; an explicit style overrides the configured draw |
| `:SimpleStartifyRefresh` | rebuild the current style without rerolling it |
| `:SimpleStartifyNextStyle` | make a new eligible random draw while on the dashboard |
| `:SimpleStartifyHealth` | open a report of environment, styles, recent-file sources and session state, one `[OK]`/`[WARN]`/`[ERROR]` line per fact |
| `:SimpleStartifyClean` | delete leftover `.simplestartify-tmp-*` files from an interrupted save |
| `:SimpleStartifyForget [path]` | drop a path from the recent list and from `v:oldfiles`; without an argument, the selected dashboard entry |
| `:Startify` | compatibility alias for `:SimpleStartify` |
| `:SSave[!] [name]` | save a session; `!` permits replacing an existing name |
| `:SLoad [name]` | load a named session, or prompt; refuse when listed buffers are modified |
| `:SLoad!` | restore the recorded last session without prompting; permit discarding modified buffers |
| `:SLoad! name` | load a named session and permit discarding modified listed buffers |
| `:SDelete[!] [name]` | delete a session; deletion is refused without `!` |
| `:SClose[!]` | save and close the managed session; `!` permits discarding modified listed buffers |

Omitting a session name normally prompts with completion from the configured
session directory. Bare `:SLoad!` is the exception: it reads the basename in
`.simplestartify-last` and loads that session without prompting. Successful
saves and loads of ordinary sessions update this hidden pointer atomically; an
unusable or absent pointer and legacy entry produce an error instead of a
prompt.

For migration, if the new pointer has no usable entry, bare `:SLoad!` also
recognizes vim-startify's old `__LAST__` regular file or an `__LAST__` symlink
to a readable regular session in the same directory. `__LAST__` itself is
never shown on the dashboard or in completion.

The plugin also defines `<Plug>(simplestartify-open)`,
`<Plug>(simplestartify-refresh)`, `<Plug>(simplestartify-next-style)`,
`<Plug>(simplestartify-forget)`, and `<Plug>(simplestartify-help)`.

## Session safety

Session handling is deliberately confined to one directory:

- A session name must be a single basename. Empty names, `.`, `..`, absolute
  paths, separators, embedded newlines, and the reserved `.simplestartify-`
  prefix are rejected.
- The configured directory may not resolve to the filesystem root. It is
  created with mode `0700` when absent and must be writable.
- Atomic session and last-pointer writes allocate a fresh hidden
  `.simplestartify-tmp-*` path inside the session directory, verify it does not
  already exist, then rename it into place. Legal session names cannot use the
  reserved `.simplestartify-` prefix, so they cannot collide with these files.
  The original target remains untouched if generation or replacement fails.
- Dashboard listing accepts only readable regular session files. Hidden
  `.simplestartify-*` internals, crash-leftover `.simplestartify-tmp-*` files,
  and the legacy `__LAST__` entry are never displayed.
- Existing regular files require `:SSave!` to overwrite; even `!` refuses to
  replace a directory, symlink, or other non-file path. Command-line deletion
  requires `:SDelete!`; dashboard deletion asks for confirmation.
- Automatic persistence is off by default. When enabled, it rewrites the
  current managed session at `VimLeavePre` and before `:SLoad` switches to
  another session. Sessions outside the configured directory are never
  adopted.
- `:SClose` is an explicit save-and-close operation: it always rewrites the
  current managed session, even when automatic persistence is disabled.
- Whenever a managed rewrite is required, its path must still be an existing,
  readable, writable regular file. A missing, replaced, non-file, unreadable,
  or unwritable managed session produces an error. Pre-load persistence and
  `:SClose` abort instead of silently discarding the failure.
- Session generation temporarily removes `options` from `'sessionoptions'` and
  restores the option afterward.
- Before loading, the current session layout is snapshotted. If sourcing the
  requested session fails, SimpleStartify sources that snapshot and restores
  the previous `v:this_session`.

A Vim session is Vimscript and is sourced when loaded. Only load session files
you trust: rollback restores the prior session layout, not arbitrary side
effects from hostile Vimscript. `:SLoad` and `:SClose` refuse to force-delete
modified listed buffers unless `!` is supplied. Save unrelated edits first;
the bang forms explicitly permit them to be discarded. Unlisted buffers are
not part of the delete pass.

## vim-startify compatibility

SimpleStartify keeps `filetype=startify`, the familiar `:Startify`, `:SSave`,
`:SLoad`, `:SDelete`, and `:SClose[!]` commands, and the following user events:

- `User SimpleStartifyReady`, `User Startified`, and `User StartifyReady` after
  the dashboard is rendered;
- `User SimpleStartifySessionLoaded` after a session is sourced.

For every option above, `g:startify_{name}` is used as a fallback when
`g:simplestartify_{name}` is unset. Automatic opening also understands the
inverse `g:startify_disable_at_vimenter` (and
`g:simplestartify_disable_at_vimenter`) convention. The plugin sets
`g:loaded_startify` so a later-loaded vim-startify installation does not
register a second `VimEnter` hook during migration.

## Highlight groups

`SimpleStartifyHeader`, `SimpleStartifyHeaderMinimal`,
`SimpleStartifyHeaderBoxed`, `SimpleStartifyHeaderCentered`,
`SimpleStartifyHeaderTerminal`, `SimpleStartifySection`,
`SimpleStartifyEntry`, `SimpleStartifyKey`, `SimpleStartifyMuted`, and
`SimpleStartifyFooter`.

Entries are highlighted with text properties where the build supports them, so
`SimpleStartifyKey` is a nested, higher-priority span drawn on top of
`SimpleStartifyEntry` rather than competing with it.

## Tests

```sh
make check
```

This compiles every Vim9 `def` and runs the smoke, width/layout, random-choice,
recent-files, highlighting, health, and session-safety regression tests.

## License

MIT
