vim9script

# The documentation makes a blanket promise - "for every option documented in
# simplestartify-options, the same suffix under g:startify_ is read when its
# g:simplestartify_ form is unset" - and nothing checked it.  The whole
# fallback chain, the inverted disable-at-vimenter convention and the
# __LAST__ migration were untested, which is exactly the kind of promise that
# rots silently: normalization runs once at load, so a missing Legacy() call
# is invisible until a vim-startify user upgrades.

set nocompatible
set nomore
set hidden

const ROOT = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')

# Vim's temporary directory is not necessarily outside a Git repository: a
# stray /tmp/.git, or a $HOME that is itself a checkout, makes every upward
# .git search from a fixture find *that* repository instead of nothing.  The
# change_to_dir fallback below used to be wrapped in a guard that skipped it
# whenever that happened, which reports a hole in the suite as a pass.  Pick
# a base whose whole ancestor chain is free of .git instead, so the assertion
# always runs, and say so loudly if the machine has none.
def RepoFree(path: string): bool
  var directory = fnamemodify(path, ':p')
  while true
    var stripped = substitute(directory, '[\\/]\+$', '', '')
    if isdirectory(stripped .. '/.git') || filereadable(stripped .. '/.git')
      return false
    endif
    if empty(stripped)
      return true
    endif
    var parent = fnamemodify(stripped, ':h')
    if parent ==# stripped
      return true
    endif
    directory = parent
  endwhile
  return true
enddef

def RepoFreeTemp(): string
  var native = resolve(tempname())
  if RepoFree(native)
    return native
  endif
  for base in [$XDG_RUNTIME_DIR, '/dev/shm', '/var/tmp', $TMPDIR]
    if filewritable(base) == 2 && RepoFree(base)
      return resolve(base) .. '/simplestartify-test-' .. getpid()
        .. '-' .. fnamemodify(native, ':t')
    endif
  endfor
  assert_report('no repository-free temporary directory on this machine: '
    .. 'every candidate has a .git above it, so the "outside a repository" '
    .. 'behaviour cannot be exercised')
  return native
enddef

const TEMP = RepoFreeTemp()
mkdir(TEMP .. '/sessions', 'p')
mkdir(TEMP .. '/outside', 'p')
mkdir(TEMP .. '/repo/.git', 'p')
mkdir(TEMP .. '/plain', 'p')
const INSIDE = TEMP .. '/repo/tracked.txt'
const OUTSIDE = TEMP .. '/plain/loose.txt'
writefile(['x'], INSIDE)
writefile(['x'], OUTSIDE)
execute 'set runtimepath^=' .. fnameescape(ROOT)

# plugin/ normalizes once at load, so every arrangement needs a fresh load
# with the g:simplestartify_ forms genuinely unset - and re-sourcing is itself
# worth exercising, since a plugin file that is not idempotent breaks every
# user who reloads their vimrc.
def Forget()
  for name in keys(g:)
    if name =~# '^\%(simple\)\=startify_' || name =~# '^loaded_\%(simple\)\=startify$'
      execute 'unlet g:' .. name
    endif
  endfor
enddef

def Load()
  # Never let a reload point the recent-file cache at the real home
  # directory: these tests must not write outside their temporary tree.
  g:simplestartify_mru_persist = 0
  execute 'source ' .. fnameescape(ROOT .. '/plugin/simplestartify.vim')
enddef

# 1. The old names alone, across every shape the normalizers accept.
Forget()
g:startify_session_dir = TEMP .. '/sessions'
g:startify_style = 'boxed'
g:startify_styles = ['minimal', 'boxed']
g:startify_avoid_repeat = 0
g:startify_custom_header = ['OLD BANNER']
g:startify_custom_footer = 'old footer'
g:startify_lists = [{'type': 'files', 'header': ['   MRU']}, {'type': 'sessions'}]
g:startify_bookmarks = [{'c': '~/.vimrc'}, '~/.zshrc']
g:startify_commands = [{'u': ['update', ':PlugUpdate']}]
g:startify_skiplist = ['\.log$']
g:startify_recent_count = 3
g:startify_session_count = 2
g:startify_session_persistence = 1
g:startify_session_autoload = 1
g:startify_change_to_vcs_root = 1
g:startify_change_to_dir = 1
g:startify_open_action = 'vsplit'
g:startify_quit_action = 'qall'
g:startify_reopen_on_empty = 1
g:startify_mru_max = 42
g:startify_disable_at_vimenter = 1
Load()

assert_equal(TEMP .. '/sessions', g:simplestartify_session_dir)
assert_equal('boxed', g:simplestartify_style)
assert_equal(['minimal', 'boxed'], g:simplestartify_styles)
assert_equal(0, g:simplestartify_avoid_repeat)
assert_equal(['OLD BANNER'], g:simplestartify_custom_header)
assert_equal('old footer', g:simplestartify_custom_footer)
# vim-startify writes a section header as a one-element list of indented
# text; both that and a plain string have to survive the crossing.
assert_equal([{type: 'files', header: 'MRU'}, {type: 'sessions'}],
  g:simplestartify_lists)
assert_equal([{key: 'c', path: '~/.vimrc'}, {key: '', path: '~/.zshrc'}],
  g:simplestartify_bookmarks)
assert_equal([{key: 'u', command: 'PlugUpdate', label: 'update'}],
  g:simplestartify_commands)
assert_equal(['\.log$'], g:simplestartify_skiplist)
assert_equal(3, g:simplestartify_recent_count)
assert_equal(2, g:simplestartify_session_count)
assert_equal(1, g:simplestartify_session_persistence)
assert_equal(1, g:simplestartify_session_autoload)
assert_equal(1, g:simplestartify_change_to_vcs_root)
assert_equal(1, g:simplestartify_change_to_dir)
assert_equal('vsplit', g:simplestartify_open_action)
assert_equal('qall', g:simplestartify_quit_action)
assert_equal(1, g:simplestartify_reopen_on_empty)
assert_equal(42, g:simplestartify_mru_max)
# The old convention is the inverse switch, and the intro screen follows it.
assert_equal(0, g:simplestartify_auto_open)
assert_equal(0, g:simplestartify_hide_intro)

# 2. The new name always wins, whichever way the old one is set.
Forget()
g:startify_recent_count = 3
g:simplestartify_recent_count = 9
g:startify_open_action = 'vsplit'
g:simplestartify_open_action = 'tabedit'
g:startify_disable_at_vimenter = 1
g:simplestartify_auto_open = 1
Load()
assert_equal(9, g:simplestartify_recent_count)
assert_equal('tabedit', g:simplestartify_open_action)
assert_equal(1, g:simplestartify_auto_open)

# 3. The new spelling of the inverted switch works on its own too.
Forget()
g:simplestartify_disable_at_vimenter = 1
Load()
assert_equal(0, g:simplestartify_auto_open)

# 4. Directory options after opening a recent file.  The documented rule is
# that a found Git root wins and change_to_dir is the fallback, which nothing
# tested: only the VCS half had coverage, so the precedence could invert
# without a single assertion turning red.
Forget()
g:simplestartify_auto_open = 0
g:simplestartify_session_dir = TEMP .. '/sessions'
g:simplestartify_change_to_vcs_root = 1
g:simplestartify_change_to_dir = 1
Load()

def OpenPath(path: string)
  only
  enew!
  SimpleStartify minimal
  for action in values(b:simplestartify_actions)
    if get(action, 'path', '') ==# path
      simplestartify#ActivateKey(action.key)
      return
    endif
  endfor
  assert_report('no dashboard entry for ' .. path)
enddef

execute 'lcd ' .. fnameescape(TEMP)
execute 'edit ' .. fnameescape(OUTSIDE)
execute 'edit ' .. fnameescape(INSIDE)
OpenPath(INSIDE)
assert_equal(resolve(TEMP .. '/repo'), resolve(getcwd()))

# Outside a repository the Git root cannot win, so the fallback is what is
# left.  The fixture lives under a repository-free base precisely so this
# runs unconditionally.
execute 'lcd ' .. fnameescape(TEMP)
assert_true(empty(finddir('.git', TEMP .. '/plain;'))
  && empty(findfile('.git', TEMP .. '/plain;')),
  'fixture is inside a repository: ' .. TEMP .. '/plain')
OpenPath(OUTSIDE)
assert_equal(resolve(TEMP .. '/plain'), resolve(getcwd()))
execute 'lcd ' .. fnameescape(TEMP)

# 5. vim-startify's historical __LAST__ pointer.  The migration branch and,
# more importantly, its "the link must resolve inside the session directory"
# check had no coverage at all.
if has('unix') && executable('ln')
  writefile(['let g:migrated = 1'], TEMP .. '/sessions/work')
  # Deliberately the same basename as the real session above: dropping the
  # "resolves inside the session directory" check turns this link into a
  # request to load sessions/work, which is a different session than the one
  # the link names.  Asserting only "nothing outside was sourced" would pass
  # either way, because the loader re-resolves the basename inside the
  # directory anyway - so the discriminating fact is that *nothing* loads.
  writefile(['let g:escaped = 1'], TEMP .. '/outside/work')
  delete(TEMP .. '/sessions/.simplestartify-last')

  call system('ln -s ' .. shellescape(TEMP .. '/outside/work')
    .. ' ' .. shellescape(TEMP .. '/sessions/__LAST__'))
  assert_equal('link', simplestartify#session#LegacyLastType())
  only
  enew!
  assert_false(simplestartify#session#Load(true, ''))
  assert_equal(0, get(g:, 'escaped', 0))
  assert_equal(0, get(g:, 'migrated', 0))
  # And __LAST__ is never offered as an ordinary entry either.
  assert_equal(-1, index(simplestartify#session#List(), '__LAST__'))

  delete(TEMP .. '/sessions/__LAST__')
  call system('ln -s work ' .. shellescape(TEMP .. '/sessions/__LAST__'))
  only
  enew!
  assert_true(simplestartify#session#Load(true, ''))
  assert_equal(1, get(g:, 'migrated', 0))
  assert_equal(TEMP .. '/sessions/work', v:this_session)

  # Migrating once is the point: the load records the resolved name in the
  # new pointer, so the legacy link is consulted only while that pointer has
  # nothing usable in it.
  assert_equal(['work'],
    readfile(TEMP .. '/sessions/.simplestartify-last'))

  # A plain __LAST__ file is loaded under that name, the way vim-startify
  # wrote it before symlinks.
  delete(TEMP .. '/sessions/__LAST__')
  delete(TEMP .. '/sessions/.simplestartify-last')
  writefile(['let g:plain_last = 1'], TEMP .. '/sessions/__LAST__')
  v:this_session = ''
  only
  enew!
  assert_true(simplestartify#session#Load(true, ''))
  assert_equal(1, get(g:, 'plain_last', 0))
  assert_equal(TEMP .. '/sessions/__LAST__', v:this_session)
  delete(TEMP .. '/sessions/__LAST__')
endif

v:this_session = ''
g:simplestartify_session_persistence = 0
execute 'lcd ' .. fnameescape(ROOT)
delete(TEMP, 'rf')
if !empty(v:errors)
  writefile(v:errors, '/dev/stderr')
  cquit 1
endif
qall!
