vim9script

set nocompatible
set nomore
set hidden

const ROOT = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
const TEMP = tempname()
mkdir(TEMP, 'p')
execute 'set runtimepath^=' .. fnameescape(ROOT)
g:simplestartify_auto_open = 0
g:simplestartify_session_dir = TEMP .. '/sessions'
g:simplestartify_mru_persist = 0
g:simplestartify_session_persistence = 1
execute 'source ' .. fnameescape(ROOT .. '/plugin/simplestartify.vim')

assert_equal('', simplestartify#session#Path('../escape'))
assert_equal('', simplestartify#session#Path('/absolute'))
assert_equal('', simplestartify#session#Path('bad/name'))
assert_equal('', simplestartify#session#Path('.simplestartify-private'))

var file = TEMP .. '/note.txt'
writefile(['hello'], file)
execute 'edit ' .. fnameescape(file)
mkdir(TEMP .. '/sessions', 'p')
var collision = $'{TEMP}/sessions/work.simplestartify-tmp-{getpid()}'
writefile(['do not delete'], collision)
assert_true(simplestartify#session#Save(true, 'work'))
assert_equal(['do not delete'], readfile(collision))
delete(collision)
var session_path = TEMP .. '/sessions/work'
assert_true(filereadable(session_path))
assert_equal(session_path, v:this_session)
assert_equal(['work'], simplestartify#session#List())
assert_false(simplestartify#session#Save(false, 'work'))

# :SSave, :SLoad and :SDelete all complete from List(), so every <Tab> used to
# glob the session directory and stat every file in it - 3.8 ms per keypress at
# 500 sessions, and far worse on a network home.  The answer is now reused
# until the directory itself changes, which is what these assertions defend:
# the reused answer has to be a copy, because Complete() filters the list it is
# handed and would otherwise delete every non-matching name from the cache; and
# a session created or deleted has to be visible to the very next completion.
#
# The scan deliberately refuses to remember an answer whose directory
# timestamp is from the current second - directory mtimes have one-second
# resolution, so a second write inside that second would leave the stored
# timestamp equal and unnoticed - and the wait is what puts the assertions
# below on the reusing path at all instead of measuring the fresh one twice.
sleep 1100m
assert_equal(['work'], simplestartify#session#Complete('wor', '', 0))
assert_equal([], simplestartify#session#Complete('zzz', '', 0))
assert_equal(['work'], simplestartify#session#Complete('wor', '', 0))
assert_equal(['work'], simplestartify#session#List())

writefile(['" fresh'], TEMP .. '/sessions/zzz-fresh')
assert_equal(['zzz-fresh'], simplestartify#session#Complete('zzz', '', 0))
delete(TEMP .. '/sessions/zzz-fresh')
assert_equal([], simplestartify#session#Complete('zzz', '', 0))

# A directory has a perfectly good modification time of its own, so "the
# timestamp says it exists" is not the same question as "this is a session":
# one pass over the directory still has to ask what the entry is, not only when
# it changed.
mkdir(TEMP .. '/sessions/notes', 'p')
assert_equal(['work'], simplestartify#session#List())
delete(TEMP .. '/sessions/notes', 'd')

var marker_session = TEMP .. '/sessions/marker'
writefile(['let g:simplestartify_test_session_loaded = 1'], marker_session)
writefile(['legacy'], TEMP .. '/sessions/__LAST__')
assert_false(index(simplestartify#session#List(), '__LAST__') >= 0)
# Loading never silently drops an unsaved buffer.
setline(1, 'unsaved')
assert_false(simplestartify#session#Load(false, 'marker'))
assert_equal('unsaved', getline(1))
assert_equal(file, expand('%:p'))
execute 'edit! ' .. fnameescape(file)

# A syntactically valid session that throws is rolled back to the previous
# editor layout instead of leaving an empty workspace.
var broken_session = TEMP .. '/sessions/broken'
writefile(["throw 'broken session'"], broken_session)
assert_false(simplestartify#session#Load(false, 'broken'))
assert_equal(file, expand('%:p'))
assert_equal(session_path, v:this_session)

assert_true(simplestartify#session#Load(false, 'marker'))
assert_equal(1, get(g:, 'simplestartify_test_session_loaded', 0))
assert_equal(marker_session, v:this_session)

enew!
setline(1, 'keep this')
var modified_buffer = bufnr()
simplestartify#session#Close(false)
assert_true(bufexists(modified_buffer))
assert_equal('keep this', getbufline(modified_buffer, 1)[0])
# Explicit :SClose persists an active managed session even when automatic
# persistence is disabled.  It also aborts if that managed file disappeared.
g:simplestartify_session_persistence = 0
delete(marker_session)
simplestartify#session#Close(true)
assert_true(bufloaded(modified_buffer))
assert_equal(marker_session, v:this_session)
writefile(["throw 'stale marker'"], marker_session)
SClose!
assert_false(bufloaded(modified_buffer))
assert_equal('startify', &filetype)
assert_equal('', v:this_session)
assert_notmatch('stale marker', join(readfile(marker_session), "\n"))

# vim-startify compatibility: bare :SLoad! restores the recorded last session
# without prompting, while __LAST__ remains hidden from the dashboard list.
SLoad!
assert_equal(marker_session, v:this_session)

# Save hooks and saved state.  The extra lines go into the temporary before
# the rename, so a session carrying variables is still replaced in one step.
g:hooks = []
augroup SimpleStartifyHookTest
  autocmd!
  autocmd User SimpleStartifySessionSavePre add(g:hooks, 'save-pre')
  autocmd User SimpleStartifySessionSavePost add(g:hooks, 'save-post')
  autocmd User SimpleStartifySessionLoadPre add(g:hooks, 'load-pre')
  autocmd User SimpleStartifySessionLoadPost add(g:hooks, 'load-post')
augroup END
g:kept_state = {'window': 'left', 'count': 3}
# A capital is required for a Funcref in a global, and a Funcref is the point:
# it cannot be written as text that sources back.
g:DroppedState = function('empty')
g:simplestartify_session_savevars = ['g:kept_state', 'g:DroppedState',
  'g:missing_state']
g:simplestartify_session_savecmds = ['let g:from_savecmds = 1']
execute 'edit! ' .. fnameescape(file)
assert_true(simplestartify#session#Save(true, 'stateful'))
assert_equal(['save-pre', 'save-post'], g:hooks)
var stateful = join(readfile(TEMP .. '/sessions/stateful'), "\n")
assert_match("let g:kept_state = {'window': 'left', 'count': 3}", stateful)
assert_match('let g:from_savecmds = 1', stateful)
# A Funcref cannot be written as sourceable text, and a name that is not set
# has nothing to write; neither may reach the session file.
assert_notmatch('g:DroppedState', stateful)
assert_notmatch('g:missing_state', stateful)
unlet g:kept_state
g:hooks = []
assert_true(simplestartify#session#Load(false, 'stateful'))
assert_equal(['load-pre', 'load-post'], g:hooks)
assert_equal({'window': 'left', 'count': 3}, g:kept_state)
assert_equal(1, g:from_savecmds)

# A save hook that throws fails the save.  The temporary is removed and the
# previous session file is left exactly as it was, rather than being replaced
# by half a workspace.
augroup SimpleStartifyHookTest
  autocmd! User SimpleStartifySessionSavePre
  autocmd User SimpleStartifySessionSavePre throw 'hook refused'
augroup END
var intact = readfile(TEMP .. '/sessions/stateful')
assert_false(simplestartify#session#Save(true, 'stateful'))
assert_equal(intact, readfile(TEMP .. '/sessions/stateful'))
assert_equal([], simplestartify#session#TempLeftovers())
augroup SimpleStartifyHookTest
  autocmd! User SimpleStartifySessionSavePre
augroup END

g:simplestartify_session_savevars = []
g:simplestartify_session_savecmds = []

# A project session is a Session.vim in the working directory.  It is loaded
# through the ordinary path, so it cannot skip the modified-buffer refusal,
# and it is never recorded as the last session: bare :SLoad! must not resolve
# to a file this plugin does not manage.
mkdir(TEMP .. '/workspace', 'p')
writefile(['let g:workspace_loaded = 1'], TEMP .. '/workspace/Session.vim')
execute 'lcd ' .. fnameescape(TEMP .. '/workspace')
v:this_session = ''
g:simplestartify_session_autoload = 0
assert_false(simplestartify#session#Autoload())
assert_equal(0, get(g:, 'workspace_loaded', 0))

g:simplestartify_session_autoload = 1
enew!
setline(1, 'unsaved work')
assert_false(simplestartify#session#Autoload())
assert_equal(0, get(g:, 'workspace_loaded', 0))
bwipeout!

# A managed session that happens to share the project session's basename is
# what makes the pointer assertion below discriminating.  RecordLast() ignores
# a name with no readable file behind it, so without this decoy the pointer
# stays put whether or not the loader checks that what it sourced is a session
# this plugin manages - and dropping that check repoints a bare :SLoad! at this
# unrelated file.
writefile(['let g:decoy_loaded = 1'], TEMP .. '/sessions/Session.vim')
var pointer_before = readfile(TEMP .. '/sessions/.simplestartify-last')
assert_notequal(['Session.vim'], pointer_before)
assert_true(simplestartify#session#Autoload())
assert_equal(1, g:workspace_loaded)
assert_equal(0, get(g:, 'decoy_loaded', 0))
assert_equal(fnamemodify(TEMP .. '/workspace/Session.vim', ':p'), v:this_session)
assert_equal(pointer_before, readfile(TEMP .. '/sessions/.simplestartify-last'))

# An active session is the user's current answer to "what am I working on",
# so a second autoload - the DirChanged case - leaves it alone.
g:workspace_loaded = 0
assert_false(simplestartify#session#Autoload())
assert_equal(0, g:workspace_loaded)
v:this_session = ''
g:simplestartify_session_autoload = 0
execute 'lcd ' .. fnameescape(ROOT)
autocmd! SimpleStartifyHookTest

assert_false(simplestartify#session#Delete(false, 'work'))
assert_true(simplestartify#session#Delete(true, 'work'))
assert_false(filereadable(session_path))

g:simplestartify_session_persistence = 0
v:this_session = ''
delete(TEMP, 'rf')
if !empty(v:errors)
  writefile(v:errors, '/dev/stderr')
  cquit 1
endif
qall!
