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
