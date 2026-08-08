vim9script

# The dashboard used to be exactly three hardcoded sections, so there was no
# way to pin a file, put a command on the screen, see "what did I edit in this
# project", or keep .git/COMMIT_EDITMSG out of the shortcut slots.  Everything
# here exercises the configured shapes end to end: normalization, key
# allocation, rendering and activation.

set nocompatible
set nomore
set hidden

const ROOT = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
const TEMP = resolve(tempname())
mkdir(TEMP .. '/sessions', 'p')
mkdir(TEMP .. '/project/.git', 'p')
mkdir(TEMP .. '/project/deep', 'p')
mkdir(TEMP .. '/elsewhere', 'p')
mkdir(TEMP .. '/marked', 'p')

const ONE = TEMP .. '/project/one.txt'
const TWO = TEMP .. '/project/deep/two.txt'
const THREE = TEMP .. '/elsewhere/three.txt'
const PIN = TEMP .. '/marked/pin.txt'
const MARKS = TEMP .. '/marked'
const COMMIT = TEMP .. '/project/.git/COMMIT_EDITMSG'
for path in [ONE, TWO, THREE, PIN, COMMIT]
  writefile(['x'], path)
endfor
for name in ['alpha', 'beta', 'gamma']
  writefile([], TEMP .. '/sessions/' .. name)
endfor

execute 'set runtimepath^=' .. fnameescape(ROOT)
g:simplestartify_auto_open = 0
g:simplestartify_session_dir = TEMP .. '/sessions'
g:simplestartify_mru_persist = 0
g:simplestartify_recent_count = 9
g:simplestartify_session_count = 3
# A string type, a spec Vim has no section for, and the three-of-four shapes
# every documented section option accepts.
g:simplestartify_lists = ['files', {type: 'bogus'}, {type: 'sessions'},
  {type: 'bookmarks'}, {type: 'commands'}, {type: 'special'}]
g:simplestartify_bookmarks = [PIN, {'c': MARKS}, {'d': PIN}]
g:simplestartify_commands = ['TestHit', ['bump twice', ':TestHit'],
  {'u': ['keyed bump', 'TestHit']}]
execute 'source ' .. fnameescape(ROOT .. '/plugin/simplestartify.vim')

g:hits = 0
command! -nargs=0 TestHit g:hits += 1

def Ids(): list<string>
  return mapnew(get(b:, 'simplestartify_model', {sections: []}).sections,
    (_, section) => section.id)
enddef

def Section(id: string): dict<any>
  for section in get(b:, 'simplestartify_model', {sections: []}).sections
    if section.id ==# id
      return section
    endif
  endfor
  return {}
enddef

def Paths(id: string): list<string>
  return mapnew(get(Section(id), 'entries', []), (_, entry) => get(entry, 'path', ''))
enddef

def KeyFor(kind: string, label: string): string
  for action in values(get(b:, 'simplestartify_actions', {}))
    if get(action, 'kind', '') ==# kind && get(action, 'label', '') ==# label
      return get(action, 'key', '')
    endif
  endfor
  return ''
enddef

# Normalization happens once, at plugin load, and turns every accepted shape
# into one canonical entry the renderer can consume without re-parsing.
assert_equal([{type: 'files'}, {type: 'sessions'}, {type: 'bookmarks'},
  {type: 'commands'}, {type: 'special'}], g:simplestartify_lists)
assert_equal([{key: '', path: PIN}, {key: 'c', path: MARKS},
  {key: '', path: PIN}], g:simplestartify_bookmarks)
assert_equal([
  {key: '', command: 'TestHit', label: 'TestHit'},
  {key: '', command: 'TestHit', label: 'bump twice'},
  {key: 'u', command: 'TestHit', label: 'keyed bump'},
], g:simplestartify_commands)

execute 'edit ' .. fnameescape(ONE)
execute 'edit ' .. fnameescape(TWO)
execute 'edit ' .. fnameescape(THREE)

# .git/COMMIT_EDITMSG is readable, and readable used to be the only test a
# recent file had to pass, so it ate a shortcut every time a commit was made.
execute 'edit ' .. fnameescape(COMMIT)
assert_equal(-1, index(simplestartify#mru#List(), COMMIT))
assert_true(simplestartify#mru#Skipped(COMMIT))
assert_false(simplestartify#mru#Skipped(ONE))

execute 'lcd ' .. fnameescape(TEMP .. '/project/deep')
SimpleStartify minimal
assert_equal(['files', 'sessions', 'bookmarks', 'commands', 'special'], Ids())
assert_equal([THREE, TWO, ONE], Paths('files'))
assert_equal([PIN, MARKS, PIN], Paths('bookmarks'))

# An explicitly pinned key is removed from the automatic pool before anything
# is handed out, so no session can also be given "c".
var session_keys = mapnew(Section('sessions').entries, (_, entry) => entry.key)
assert_equal(['a', 'b', 'e'], session_keys)
var bookmark_keys = mapnew(Section('bookmarks').entries, (_, entry) => entry.key)
assert_equal('c', bookmark_keys[1])

# A key the dashboard already owns is refused during normalization and the
# entry gets an ordinary automatic one: an entry mapping is installed last and
# would otherwise silently replace session deletion.
assert_match('simplestartify#DeleteCurrentSession', maparg('d', 'n'))
for key in bookmark_keys
  assert_true(!empty(key) && key !=# 'd' && index(session_keys, key) < 0, key)
endfor
# A directory bookmark is displayed as a directory rather than as a file.
assert_match('[\\/]$', Section('bookmarks').entries[1].label)

# Commands are entries like any other, and running one is what a command entry
# is for.
assert_equal(3, len(Section('commands').entries))
var command_key = KeyFor('command', 'keyed bump')
assert_equal('u', command_key)
simplestartify#ActivateKey(command_key)
assert_equal(1, g:hits)

# A command that fails must not throw out of the mapping and leave the user
# staring at a Vim error stack on the dashboard.
SimpleStartify minimal
add(g:simplestartify_commands, {key: 'x', command: 'NoSuchCommandHere',
  label: 'broken'})
SimpleStartifyRefresh
var noise = execute('call simplestartify#ActivateKey("x")')
assert_match('command failed', noise)
assert_equal('startify', &filetype)
remove(g:simplestartify_commands, -1)

# A bookmark opens its target.
SimpleStartify minimal
simplestartify#ActivateKey(Section('bookmarks').entries[0].key)
assert_equal(PIN, expand('%:p'))

# Sections narrowed to the working directory and to the project root, with the
# global list keeping only what they did not already show.
g:simplestartify_lists = [{type: 'dir'}, {type: 'project'}, {type: 'files'},
  {type: 'special'}]
execute 'lcd ' .. fnameescape(TEMP .. '/project/deep')
SimpleStartify minimal
assert_equal(['dir', 'project', 'files', 'special'], Ids())
assert_equal([TWO], Paths('dir'))
assert_equal([ONE], Paths('project'))
assert_equal([PIN, THREE], Paths('files'))

# Outside a repository the project section falls back to the working
# directory rather than showing everything on the machine.  Skipped when the
# machine happens to have a .git above the temporary directory, which would
# make this a test of that repository instead.
execute 'lcd ' .. fnameescape(TEMP .. '/elsewhere')
if empty(finddir('.git', getcwd() .. ';')) && empty(findfile('.git', getcwd() .. ';'))
  SimpleStartifyRefresh
  assert_equal([THREE], Paths('dir'))
  assert_equal([], Paths('project'))
endif

# A custom skiplist replaces the default one and applies to paths that were
# recorded before it was set, not only to new visits.
execute 'lcd ' .. fnameescape(TEMP .. '/project/deep')
g:simplestartify_skiplist = ['two\.txt$', 'pin\.txt$']
SimpleStartifyRefresh
assert_equal([], Paths('dir'))
assert_equal([THREE], Paths('files'))
g:simplestartify_skiplist = []

# Per-section header and limit overrides.
g:simplestartify_lists = [{type: 'files', header: 'MY FILES', limit: 1},
  {type: 'special'}]
execute 'lcd ' .. fnameescape(TEMP .. '/project')
SimpleStartify minimal
assert_equal(1, len(Section('files').entries))
assert_match('MY FILES', join(getline(1, '$'), "\n"))
assert_notmatch('RECENT FILES', join(getline(1, '$'), "\n"))

# A configurable section nobody filled in is left out; the three built-in ones
# are drawn even when empty, because "(none yet)" answers a question the user
# asked by configuring them.
g:simplestartify_bookmarks = []
g:simplestartify_commands = []
g:simplestartify_lists = [{type: 'files'}, {type: 'bookmarks'},
  {type: 'commands'}, {type: 'sessions'}, {type: 'special'}]
g:simplestartify_recent_count = 0
SimpleStartify minimal
assert_equal(['files', 'sessions', 'special'], Ids())
assert_match('(none yet)', join(getline(1, '$'), "\n"))

# Health names every drawn section with its entry count, and says which
# configured section is missing because it is empty - the one question the
# dashboard itself cannot answer.
var report = join(simplestartify#Health().report, "\n")
assert_match('SECTIONS', report)
assert_match('\[OK\].*sessions: 3 entries', report)
assert_match('\[WARN\].*bookmarks: configured but empty', report)
assert_match('\[WARN\].*commands: configured but empty', report)

# A list that leaves nothing usable falls back to the built-in sections rather
# than drawing an empty dashboard.
g:simplestartify_lists = [{type: 'nonsense'}]
SimpleStartifyRefresh
assert_equal(['files', 'sessions', 'special'], Ids())

# Filtering narrows the cached model in place.  It is driven one keystroke at
# a time so this can be tested without a blocking read; the interactive loop
# is the same state machine with getcharstr() in front of it.
g:simplestartify_lists = [{type: 'files'}, {type: 'sessions'}, {type: 'special'}]
g:simplestartify_recent_count = 9
execute 'lcd ' .. fnameescape(TEMP)
SimpleStartify minimal
var everything = len(b:simplestartify_actions)
assert_true(everything >= 6)
for char in split('two', '\zs')
  assert_true(simplestartify#FilterKey(char))
endfor
assert_equal('two', b:simplestartify_query)
# The cached model is left whole - that is what makes backspacing free - and
# only what is drawn narrows.
assert_equal(['files', 'sessions', 'special'], Ids())
assert_equal(1, len(b:simplestartify_actions))
assert_equal([TWO], mapnew(values(b:simplestartify_actions),
  (_, action) => get(action, 'path', '')))
var screen = join(getline(1, '$'), "\n")
assert_notmatch('SESSIONS', screen)
# The query is visible in the buffer, not only on the command line, which is
# gone the moment anything else echoes.
assert_match('filter: two', screen)

# Backspace narrows back out, and matching covers the path behind the label as
# well as sessions and actions.
assert_true(simplestartify#FilterKey("\<BS>"))
assert_equal('tw', b:simplestartify_query)
assert_true(simplestartify#FilterKey("\<BS>"))
assert_true(simplestartify#FilterKey("\<BS>"))
assert_equal('', b:simplestartify_query)
assert_equal(everything, len(b:simplestartify_actions))
for char in split('alph', '\zs')
  assert_true(simplestartify#FilterKey(char))
endfor
assert_equal(['alpha'], mapnew(values(b:simplestartify_actions),
  (_, action) => get(action, 'name', '')))
assert_notmatch('RECENT FILES', join(getline(1, '$'), "\n"))

# An unhandled key keeps what has been typed instead of throwing it away.
assert_true(simplestartify#FilterKey("\<Left>"))
assert_equal('alph', b:simplestartify_query)

# Escape clears the filter and ends the mode; the full dashboard comes back.
assert_false(simplestartify#FilterKey("\<Esc>"))
assert_equal('', b:simplestartify_query)
assert_equal(everything, len(b:simplestartify_actions))
assert_notmatch('filter:', join(getline(1, '$'), "\n"))

# <CR> opens the single remaining match, which is the point of the exercise:
# an entry past the nine digit shortcuts is one typed word away.
for char in split('one', '\zs')
  assert_true(simplestartify#FilterKey(char))
endfor
assert_equal(1, len(b:simplestartify_actions))
assert_false(simplestartify#FilterKey("\<CR>"))
assert_equal(ONE, expand('%:p'))

execute 'lcd ' .. fnameescape(ROOT)
delete(TEMP, 'rf')
if !empty(v:errors)
  writefile(v:errors, '/dev/stderr')
  cquit 1
endif
qall!
