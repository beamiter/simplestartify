# Changelog

All notable changes to SimpleStartify are documented here.

## Unreleased

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
  `v:oldfiles` so it does not return on the next draw.
- `:SimpleStartifyHealth` now reports the recent-file count from each source
  and the resolved cache path, which is the answer to "why is this section
  empty".
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
