# Changelog

All notable changes to SimpleStartify are documented here.

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
