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
let g:simplestartify_custom_header = []   " list of lines, or a string
let g:simplestartify_custom_footer = []

let g:simplestartify_lists = [
  \ {'type': 'remote'}, {'type': 'files'}, {'type': 'sessions'},
  \ {'type': 'bookmarks'}, {'type': 'commands'}, {'type': 'special'}]
let g:simplestartify_bookmarks = []
let g:simplestartify_commands = []
let g:simplestartify_skiplist = [
  \ '\.git[\\/]\%(COMMIT_EDITMSG\|MERGE_MSG\|TAG_EDITMSG\|SQUASH_MSG\)$',
  \ '\.git[\\/]rebase-\%(merge\|apply\)[\\/]']

let g:simplestartify_remote_count = 3   " clamped to 0..12
let g:simplestartify_recent_count = 7   " clamped to 0..50
let g:simplestartify_session_count = 4  " clamped to 0..13
let g:simplestartify_session_dir = '~/.vim/session'
let g:simplestartify_session_persistence = 0
let g:simplestartify_session_autoload = 0
let g:simplestartify_session_savevars = []
let g:simplestartify_session_savecmds = []
let g:simplestartify_session_line_providers = ['g:SimpleRemoteSessionLines']

let g:simplestartify_change_to_vcs_root = 0
let g:simplestartify_change_to_dir = 0
let g:simplestartify_open_action = 'edit'  " or split / vsplit / tabedit
let g:simplestartify_quit_action = 'auto'  " or quit / close / qall
let g:simplestartify_reopen_on_empty = 0

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

`g:simplestartify_custom_header` and `g:simplestartify_custom_footer` replace
each layout's banner and its key hints. Both accept a list of lines or a
string; a string that looks like a function call is evaluated on every draw
and may return a string or a list, so a dynamic header works:

```vim
let g:simplestartify_custom_header = ['MY VIM', '']
let g:simplestartify_custom_footer = 'happy hacking'
let g:simplestartify_custom_header = 'strftime("%A %d %B")'
```

A Funcref is deliberately not accepted: Vim refuses to store one in a global
whose name does not start with a capital (`E704`), so this option could never
hold one -- the evaluated string is the equivalent. The lines are plain text
and each layout renders them in its own style, so one configured header still
looks like part of whichever layout was dealt. An expression that throws
reports the failure and falls back to the built-in banner.

`g:simplestartify_session_persistence` controls automatic rewrites only: when
enabled, the active managed session is saved at `VimLeavePre` and before
`:SLoad` switches sessions. An explicit `:SClose` always saves the active
managed session, regardless of this setting.

`g:simplestartify_session_autoload` turns a directory into a workspace: with
no active session, a `Session.vim` in the working directory is loaded at
`VimEnter` when no file was named on the command line (before the dashboard
would open), and on a global directory change (`:cd`). Loading a session
deletes every listed buffer first, which is why both of those limits exist:
`vim README.md` opens README.md and no session, and a window-local `:lcd` --
this plugin's own after `g:simplestartify_change_to_dir`, or any other
plugin's -- is not a project change and loads nothing. It goes through the
ordinary load path, so the modified-buffer refusal and the rollback snapshot
still apply, and it is never recorded as the last session or rewritten
automatically -- its parent is not the configured session directory. A
`Session.vim` is sourced Vimscript, so enable this only for directories you
trust.

`g:simplestartify_session_savevars` and `g:simplestartify_session_savecmds`
add global variables and Ex command lines to every session this plugin writes.
They are appended to the temporary file before it is renamed into place, so a
session carrying extra state is still replaced atomically. A variable that is
unset, or holds something `string()` cannot render as sourceable text such as
a Funcref, is skipped rather than producing a session that fails to load.

`g:simplestartify_session_line_providers` names global functions asked for
extra session lines at every save. Each returns a list of strings that are
written after the saved variables and before the saved commands. A provider
that is not defined in this Vim is skipped silently, which is what lets
SimpleRemote's `g:SimpleRemoteSessionLines` be the zero-config default; one
that throws or returns something else reports it and the save continues.

Sessions also emit `User SimpleStartifySessionSavePre`/`SavePost` and
`LoadPre`/`LoadPost`. `SavePre` runs inside the same `try` as the write, so a
hook that throws fails the save and leaves the previous session file intact.
The two load events run after the load is final, outside the rollback `try`: a
hook that throws is reported and the session stays loaded, and a load that was
rolled back fires neither event.

### Sections

`g:simplestartify_lists` decides what the dashboard shows and in what order.
Eight section types exist: `remote` (SimpleRemote workspaces, see below),
`files` (recent files anywhere), `dir` (recent files below the working
directory), `project` (recent files below its Git root), `sessions`,
`bookmarks`, `commands`, and `special` (new buffer, restyle, quit).

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
out for being empty -- except `remote`, which is empty whenever SimpleRemote
is absent and gets a report section of its own instead of a warning.

### SimpleRemote workspaces

With [SimpleRemote](https://github.com/beamiter/simpleremote) installed, the
`remote` section -- first in the default deck -- lists the workspaces you can
go back to: the most recent connections, capped by
`g:simplestartify_remote_count`, followed by every configured profile the
recent list did not already show. Profiles are configuration rather than
history, so the count does not apply to them.

```
  REMOTE WORKSPACES
    [a]  SSH  devbox · /srv/app (connected)
    [b]  DOCKER  api · /workspace/api
    [c]  SSH  staging (profile)
```

`<CR>` hands the whole specification back to SimpleRemote, which connects and
opens the remote workspace tree; `s`, `v` and `t` start it in a split or a new
tab. The entry that is already connected is not reconnected -- the workspace
tree is re-rooted there and shown. A dashboard that is on screen redraws when
SimpleRemote connects, disconnects or switches workspace, so the `(connected)`
marker keeps up; a connection never opens a dashboard nobody asked for.

A bookmark whose path starts with `remote://` is a path inside a workspace and
is kept as written instead of being expanded against the working directory. It
may name the workspace it belongs to, and is then opened by connecting first
and editing the file once the workspace is ready -- into the window the split
or tab verb opened for it, or into a split of its own if that window was
closed while the connection was still being made:

```vim
let g:simplestartify_bookmarks = [
  \ {'path': 'remote:///srv/app/README.md', 'key': 'w',
  \  'workspace': {'kind': 'ssh', 'target': 'devbox', 'root': '/srv/app'}}]
```

Sessions carry the workspace too: `g:SimpleRemoteSessionLines` is the default
session-line provider, so `:SSave` records the connected workspace and `:SLoad`
reconnects it and re-reads the session's `remote://` buffers. Do not put
`g:simpleremote_workspace` in `g:simplestartify_session_savevars` -- that
global is SimpleRemote's live connection state, and restoring it from a file
would announce a connection that does not exist.

Every call into SimpleRemote is feature-detected. Without it, the `remote`
section simply is not drawn, remote bookmarks say a workspace has to be
connected first, and nothing reports an error. `:SimpleStartifyHealth` says
whether SimpleRemote is installed and what it is connected to. See
`:help simplestartify-remote`.

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
| `q` | close the dashboard window, or quit Vim when it is the only one (`g:simplestartify_quit_action`) |
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

The dashboard itself takes a window-placement modifier, so
`:vertical SimpleStartify`, `:botright SimpleStartify centered` and
`:tab SimpleStartify` put it beside your work instead of over it. Modifiers
that are not about placement are ignored rather than passed on: `noautocmd`
would suppress the `FileType` event the dashboard is set up by. `q` in such a
window closes that window; only a dashboard that is alone quits Vim, and it
refuses -- naming the buffers -- while anything listed is modified.
`g:simplestartify_reopen_on_empty` brings the dashboard back when the last
named buffer is deleted, instead of leaving you on an empty `[No Name]`.

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
`g:simplestartify_mru_file` at `VimLeavePre` and five seconds after the first
file recorded since the last write -- a Vim killed with `SIGKILL`, stopped
with its container or out of battery never reaches `VimLeavePre`, and losing
the whole session's history to that is the one thing this record exists to
prevent. Every write re-reads the file first, so a second Vim's work is merged
rather than overwritten. It is a cache: deleting it costs history and nothing
else. Missing files and duplicate absolute paths are skipped, and the search
gives up after four hundred recorded paths it rejects -- one that no longer
exists, or one that `g:simplestartify_skiplist` matches -- so a record full of
files that have been deleted cannot stall startup. Sessions are ordered newest
first.

## Commands

| Command | Effect |
| --- | --- |
| `:SimpleStartify [style]` | open the dashboard; an explicit style overrides the configured draw |
| `:vertical` / `:tab` / `:botright SimpleStartify` | open it in its own window or tab instead of taking over the current one |
| `:SimpleStartifyRefresh` | rebuild the current style without rerolling it |
| `:SimpleStartifyNextStyle` | make a new eligible random draw while on the dashboard |
| `:SimpleStartifyHealth` | open a report of environment, styles, sections, SimpleRemote, recent-file sources and session state, one `[OK]`/`[WARN]`/`[ERROR]` line per fact |
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

This compiles every Vim9 `def` and runs the fixture-helper, smoke, width/layout,
random-choice, section and filter, SimpleRemote integration, recent-files,
highlighting, health, session-safety, project-session, window-management and
vim-startify compatibility regression tests. The SimpleRemote script runs
without SimpleRemote on the `runtimepath`: it stubs the `g:SimpleRemote*`
functions and fires the `User SimpleRemote*` events by hand, which is the same
contract the plugin keeps at runtime. The project-session script starts a child Vim so
the `VimEnter` hook is exercised the way a user starts an editor, with and
without a file argument.

Fixtures that must not look like they sit inside a Git repository cannot always
use Vim's own temporary directory -- a stray `/tmp/.git`, or a `$HOME` that is
itself a checkout, would make every upward root search find that repository.
`tests/fixture.vim` picks a repository-free base instead, removes it on
`VimLeave` so an aborted run leaves nothing behind, and creates it 0700 in a way
that fails on an already-taken name, the fallback bases (`/dev/shm`, `/var/tmp`)
being world-writable and the name guessable.

## License

MIT
