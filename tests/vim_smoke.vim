vim9script

set nocompatible
set nomore
set hidden

const ROOT = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
const TEMP = tempname()
mkdir(TEMP .. '/project/.git', 'p')
mkdir(TEMP .. '/sessions', 'p')
writefile(['hello'], TEMP .. '/project/note.txt')
writefile(['a'], TEMP .. '/origin-a.txt')
writefile(['b'], TEMP .. '/origin-b.txt')
for index in range(13)
  writefile([], $'{TEMP}/sessions/session-{index}')
endfor
execute 'set runtimepath^=' .. fnameescape(ROOT)
g:simplestartify_auto_open = 0
g:simplestartify_style = 'random'
g:simplestartify_avoid_repeat = 1
g:simplestartify_session_count = 13
g:simplestartify_session_dir = TEMP .. '/sessions'
execute 'source ' .. fnameescape(ROOT .. '/plugin/simplestartify.vim')

for command_name in ['SimpleStartify', 'SimpleStartifyRefresh',
    'SimpleStartifyNextStyle', 'SimpleStartifyHealth', 'Startify',
    'SSave', 'SLoad', 'SDelete', 'SClose']
  assert_equal(2, exists(':' .. command_name), command_name)
endfor

SimpleStartify minimal
assert_equal('startify', &filetype)
assert_equal('nofile', &buftype)
assert_equal('wipe', &bufhidden)
assert_false(&buflisted)
assert_false(&swapfile)
assert_false(&modifiable)
assert_equal(1, get(b:, 'simplestartify', 0))
assert_equal('minimal', b:simplestartify_style)
assert_false(empty(b:simplestartify_actions))
assert_match('simplestartify#Activate', maparg('<CR>', 'n'))
assert_match('simplestartify#DeleteCurrentSession', maparg('d', 'n'))
assert_match('simplestartify#Move', maparg('j', 'n'))
assert_match('simplestartify#Move', maparg('k', 'n'))

SimpleStartify boxed
assert_equal('boxed', b:simplestartify_style)
# Splits change winwidth without changing &columns.  Reflow immediately so
# every line remains visible in the narrow dashboard window.
vertical new
wincmd p
assert_true(max(mapnew(getline(1, '$'), (_, text) => strdisplaywidth(text)))
      \ <= winwidth(0))
only
var before = b:simplestartify_style
SimpleStartifyNextStyle
assert_notequal(before, b:simplestartify_style)
assert_true(index(simplestartify#ui#Styles(), b:simplestartify_style) >= 0)
var current = b:simplestartify_style
SimpleStartifyRefresh
assert_equal(current, b:simplestartify_style)

# Opening the dashboard must remember the actual source buffer even when that
# buffer was not the alternate buffer before :SimpleStartify.
execute 'edit ' .. fnameescape(TEMP .. '/origin-a.txt')
execute 'edit ' .. fnameescape(TEMP .. '/origin-b.txt')
assert_equal(fnamemodify(TEMP .. '/origin-a.txt', ':p'), expand('#:p'))
SimpleStartify minimal
assert_true(simplestartify#session#Save(true, 'origin-check'))
assert_equal(fnamemodify(TEMP .. '/origin-b.txt', ':p'), expand('%:p'))

# Recent entries are live actions, and opening one applies the configured VCS
# root without involving a shell command.
insert(v:oldfiles, TEMP .. '/project/note.txt', 0)
g:simplestartify_change_to_vcs_root = 1
SimpleStartify minimal
assert_equal('file', get(get(b:simplestartify_actions, '5', {}), 'kind', ''))
simplestartify#ActivateKey('1')
assert_equal(fnamemodify(TEMP .. '/project/note.txt', ':p'), expand('%:p'))
assert_equal(fnamemodify(TEMP .. '/project', ':p')->substitute('[\\/]\+$', '', ''), getcwd())

enew!
setline(1, 'do not replace me')
set modified
g:simplestartify_auto_open = 1
simplestartify#AutoOpen()
assert_equal('do not replace me', getline(1))
assert_notequal('startify', &filetype)

enew!
simplestartify#AutoOpen()
assert_equal('startify', &filetype)

var health = simplestartify#Health()
assert_true(has_key(health, 'styles'))

execute 'lcd ' .. fnameescape(ROOT)
delete(TEMP, 'rf')
if !empty(v:errors)
  writefile(v:errors, '/dev/stderr')
  cquit 1
endif
qall!
