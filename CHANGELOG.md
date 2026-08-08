# Changelog

All notable changes to SimpleStartify are documented here.

## Unreleased

- The dashboard is now built from configurable sections. `g:simplestartify_lists`
  chooses which of `files`, `dir`, `project`, `sessions`, `bookmarks`,
  `commands` and `special` are drawn and in what order, with an optional
  per-section `header` and `limit`. `dir` and `project` are the recent-file
  list narrowed to the working directory and to its Git root, deduplicated
  against the sections before them.
- Added `g:simplestartify_bookmarks` and `g:simplestartify_commands` for
  pinning paths and Ex commands to the dashboard, accepting vim-startify's
  shapes including an explicit shortcut key. A pinned key is taken out of the
  automatic pools first, so no session can be handed the same letter, and a
  key the dashboard already owns is refused rather than silently replacing the
  mapping behind it. A command that fails is reported instead of throwing out
  of the mapping.
- Added `g:simplestartify_skiplist`, defaulting to the `.git` files another
  tool writes (`COMMIT_EDITMSG` and friends). They are readable, and readable
  used to be the only test a recent file had to pass, so a commit cost a
  shortcut slot. It applies both when a buffer is recorded and when the
  dashboard is drawn.
- An entry past the end of its shortcut alphabet is now drawn without a marker
  and opened with the cursor, instead of being given a fake `[?]` key.
- `:SimpleStartifyHealth` gained a SECTIONS block: what would be drawn, with
  entry counts, and which configured section was left out for being empty.
- Added `g:simplestartify_session_autoload`: with no active session, a
  `Session.vim` in the working directory is loaded at `VimEnter` before the
  dashboard would open, and on `DirChanged`. It goes through the ordinary load
  path, so the modified-buffer refusal, the pre-load persistence write and the
  rollback snapshot all still apply, and it is never adopted as the last
  session or rewritten automatically.
- Added `g:simplestartify_session_savevars` and
  `g:simplestartify_session_savecmds`, appended to the temporary file before
  the rename so a session carrying extra state is still replaced atomically.
  A variable holding something `string()` cannot render as sourceable text is
  skipped instead of producing a session that fails to load.
- Added `g:simplestartify_custom_header` and `g:simplestartify_custom_footer`,
  each a list of lines or a string. A string that looks like a function call
  is evaluated on every draw, which is how a dynamic header works: Vim refuses
  to store a Funcref in a lowercase global (`E704`), so that shape could never
  have been supported. Each layout still renders the lines in its own style,
  and an expression that throws falls back to the built-in banner instead of
  breaking the dashboard.
- Added incremental filtering: `/` and `<C-f>` narrow the dashboard as you
  type, matching the label and the path, session name or command behind it.
  Each keystroke re-draws from the cached model, so no file is stat'ed and no
  directory is scanned while filtering, and the cached model itself is left
  whole so backspacing costs nothing. The query is shown in the footer as well
  as on the command line.
- `g:simplestartify_recent_count` now accepts up to 50 instead of 9. Nine was
  the digit alphabet, not a sensible ceiling: entries past it are drawn
  without a marker and reached with `j`/`k` or the filter.
- Added the `User` events `SimpleStartifySessionSavePre`, `SavePost`,
  `LoadPre` and `LoadPost`. `SavePre` runs inside the same `try` as the write,
  so a hook that throws fails the save and leaves the old session file intact.

- Recent files are now tracked as they are opened instead of being read only
  from `v:oldfiles`, which Vim freezes at startup and never updates. Files
  opened during this session appear on the dashboard immediately, including in
  the mid-session `:SClose` flow, and the section is no longer permanently
  empty under `vim -i NONE`, an empty `'viminfo'`, a fresh container, or a
  first-ever launch. In-session entries rank ahead of `v:oldfiles`.
- Added `g:simplestartify_mru_persist`, `g:simplestartify_mru_max`, and
  `g:simplestartify_mru_file` for that record. It is written atomically at
  `VimLeavePre` and merged with whatever another Vim instance wrote, so
  concurrent instances do not discard each other's history. A cache that
  cannot be parsed or written costs entries, never an error or a lost session.
- Added `:SimpleStartifyForget [path]`, `<Plug>(simplestartify-forget)`, and
  the `D` dashboard mapping, which drop a file from the record and from
  `v:oldfiles` so it does not return on the next draw. The removal also
  survives the merge-and-rewrite the cache performs at `VimLeavePre`, so a
  forgotten path does not reappear in the next Vim either; opening the file
  again is what records it once more.
- `:SimpleStartifyHealth` now reports the recent-file count from each source
  and the resolved cache path, which is the answer to "why is this section
  empty".
- Added `?` and `g?` on the dashboard, plus `<Plug>(simplestartify-help)`,
  showing every live key in a popup. It is built from the buffer's actual
  entries, so it always names the current session letters -- the keys that
  replace a normal-mode command while the dashboard is open, which nothing
  previously told you. The footer now degrades by window width instead of
  being ellipsized away, and always keeps the pointer to `?`.
- Disabling the dashboard no longer removes Vim's intro message anyway.
  `shortmess+=I` was applied unconditionally at plugin load, so a user who set
  `g:simplestartify_auto_open = 0` got a blank buffer and no intro. Intro
  suppression now follows that option and can be overridden with the new
  `g:simplestartify_hide_intro`.
- `:SimpleStartifyHealth` now opens a report instead of echoing two lines. It
  answers "why is my recent list empty" by naming an unusable `'viminfo'`,
  catches a mistyped `g:simplestartify_style` once instead of erroring on
  every draw, surfaces leftover `.simplestartify-tmp-*` files from an
  interrupted save, and reports the state of the last-session pointer. `ok` is
  now false for any ERROR-level fact, including the existing-but-unwritable
  session directory and the existing-but-unwritable recent-file cache
  directory, both of which it previously computed and ignored.
- Added `:SimpleStartifyClean` to remove those leftover temporaries.
- Dashboard entries can now be opened in a horizontal split, a vertical split
  or a new tab with `s`/`<C-x>`, `v`/`<C-v>` and `t`/`<C-t>`, and
  `g:simplestartify_open_action` chooses what plain `<CR>` does. The dashboard
  keeps its window for the split verbs, so several files can be opened in a
  row. `s`, `t` and `v` were removed from the session shortcut alphabet so a
  session can never shadow one of them; 17 letters remain against a cap of 13.
- Fixed `SimpleStartifyKey` never rendering. The documented `[key]` highlight
  competed with a whole-line entry match anchored at column 1, which always
  won Vim's earlier-start priority rule, so setting the group had no effect at
  all. Dashboard highlighting now uses text properties, where the key marker
  is a nested higher-priority span; builds without `+textprop` get the same
  structure through a `contained` syntax match. This also replaces roughly
  forty regex rules rebuilt on every draw.
- Fixed a dashboard window resized while focus was elsewhere keeping its old,
  too-wide content. Reflow now walks the windows showing a dashboard instead
  of testing the current buffer, so a `nowrap` dashboard is no longer chopped
  mid-glyph after resizing its neighbour.
- Reflow now re-lays out a cached model and only when the width actually
  changed, instead of re-reading every recent file and re-scanning the session
  directory on every window entry. Session listing stats each file once
  instead of twice per sort comparison. `:SimpleStartifyRefresh` and the `R`
  mapping remain the way to pick up new data.
- Fixed dashboard shortcut letters surviving a refresh. Deleting a session or
  drawing a style with fewer entries left its letter mapped to a lookup that
  matched nothing, so the shadowed normal-mode motion became a silent no-op
  for the life of the buffer. Only keys the dashboard installed are removed,
  so a user's own `FileType startify` mappings are untouched.
- Fixed `g:simplestartify_mru_max = 0` disabling the cap instead of keeping no
  paths. The documented lower bound of the range meant "unbounded", so the
  in-session record and the cache written at `VimLeavePre` grew without limit
  for exactly the user who asked for the smallest possible store.
- Moved the atomic temp-then-rename primitive into
  `autoload/simplestartify/atomic.vim` so the session store and the
  recent-files cache share one implementation and one reserved namespace.

## 0.1.0 - 2026-08-07

- Initial Vim9 release with four responsive layouts: `minimal`, `boxed`,
  `centered`, and `terminal`.
- Added width-aware random style selection, configurable candidate pools, and
  optional immediate-repeat avoidance.
- Added recent-file actions, keyboard navigation, refresh/reflow behavior, and
  window-local directory changes for a file or its Git root.
- Added confined session save/load/delete/close operations with same-directory
  replacement, explicit overwrite/deletion/discard gates, load rollback, and
  optional automatic managed persistence. Explicit close always saves its
  active managed session. Whenever a managed rewrite is due, a missing,
  replaced, unreadable, or unwritable file aborts the corresponding pre-load
  or close transition.
- Added non-interactive bare `:SLoad!` restore through the hidden,
  atomically-updated `.simplestartify-last` pointer, plus migration support for
  vim-startify's hidden legacy `__LAST__` file/symlink convention. Named
  `:SLoad! name` retains its modified-buffer discard meaning.
- Moved atomic session-directory writes to collision-free hidden
  `.simplestartify-tmp-*` names. Legal session names cannot enter that
  namespace, and crash leftovers are filtered from listings and completion.
- Added the vim-startify command, option, filetype, and user-event
  compatibility layer.
- Added Vim9 compilation, smoke, layout-width, random-choice, and session
  regression tests behind `make check`.
