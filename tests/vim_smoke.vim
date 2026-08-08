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
g:simplestartify_mru_file = TEMP .. '/mru'
execute 'source ' .. fnameescape(ROOT .. '/plugin/simplestartify.vim')

# Turning the dashboard off must not still take the intro screen away: this
# script sets g:simplestartify_auto_open = 0 above.
assert_equal(0, g:simplestartify_hide_intro)
assert_notmatch('I', &shortmess)

for command_name in ['SimpleStartify', 'SimpleStartifyRefresh',
    'SimpleStartifyNextStyle', 'SimpleStartifyHealth', 'SimpleStartifyForget',
    'SimpleStartifyClean', 'Startify',
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
assert_match('simplestartify#Help', maparg('?', 'n'))

# The key reference is built from the live actions, so it always names the
# session letters that are currently shadowing normal-mode commands.
var help = join(simplestartify#HelpLines(), "\n")
assert_match('open it in a vertical split', help)
for action in values(b:simplestartify_actions)
  assert_match('\V\n  ' .. escape(action.key, '\\') .. ' ', help)
endfor
assert_match('SESSIONS', help)

# A refresh must give up the shortcut letters it no longer owns.  A stale
# buffer-local mapping resolves to no action and returns silently, so the
# shadowed normal-mode motion is a dead key for the life of the buffer.
var session_keys = mapnew(
  filter(values(b:simplestartify_actions),
    (_, action) => get(action, 'kind', '') ==# 'session'),
  (_, action) => action.key)
assert_equal(13, len(session_keys))
for index in range(2, 12)
  delete($'{TEMP}/sessions/session-{index}')
endfor
SimpleStartifyRefresh
var live_keys = mapnew(values(b:simplestartify_actions), (_, action) => action.key)
assert_equal(2, len(filter(copy(live_keys), (_, key) => index(session_keys, key) >= 0)))
for key in session_keys
  if index(live_keys, key) < 0
    assert_equal('', maparg(key, 'n'), 'stale mapping for ' .. key)
  endif
endfor
for key in live_keys
  assert_match('simplestartify#ActivateKey', maparg(key, 'n'), 'live key ' .. key)
endfor

SimpleStartify boxed
assert_equal('boxed', b:simplestartify_style)
# Splits change winwidth without changing &columns, and the window that
# shrinks is usually not the focused one.  Assert from the *other* window: the
# dashboard is 'nowrap', so a missed reflow chops every line mid-glyph.
var dashboard = bufnr()
vertical new
vertical resize 62
var dashboard_width = getwininfo(bufwinid(dashboard))[0].width
assert_true(dashboard_width > 0 && dashboard_width < 40, 'width ' .. dashboard_width)
var before_reflow = getbufvar(dashboard, 'changedtick')
# WinResized is only delivered at the main loop, which an -es script never
# reaches, so drive the autocmd's entry point directly.  It used to test the
# *current* buffer and therefore did nothing at all from here.
simplestartify#Reflow()
assert_notequal(before_reflow, getbufvar(dashboard, 'changedtick'))
assert_true(max(mapnew(getbufline(dashboard, 1, '$'),
      \ (_, text) => strdisplaywidth(text))) <= dashboard_width)
wincmd p
only
# An unchanged width must not redraw: reflow exists for resizes, not to
# rebuild the whole model on every window entry.
simplestartify#Reflow()
var settled_ticks = b:changedtick
simplestartify#Reflow()
assert_equal(settled_ticks, b:changedtick)
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
# root without involving a shell command.  Files this session touched outrank
# v:oldfiles, which Vim froze at startup and never updates.
insert(v:oldfiles, TEMP .. '/project/note.txt', 0)
g:simplestartify_change_to_vcs_root = 1
SimpleStartify minimal
assert_equal('file', get(get(b:simplestartify_actions, '5', {}), 'kind', ''))
assert_equal(fnamemodify(TEMP .. '/origin-b.txt', ':p'),
  get(get(b:simplestartify_actions, '5', {}), 'path', ''))
var note_key = ''
for action in values(b:simplestartify_actions)
  if get(action, 'path', '') ==# fnamemodify(TEMP .. '/project/note.txt', ':p')
    note_key = action.key
  endif
endfor
assert_notequal('', note_key)
simplestartify#ActivateKey(note_key)
assert_equal(fnamemodify(TEMP .. '/project/note.txt', ':p'), expand('%:p'))
assert_equal(fnamemodify(TEMP .. '/project', ':p')->substitute('[\\/]\+$', '', ''), getcwd())

# An entry opens in a split, a vertical split or a tab on demand, and the
# dashboard stays in its own window so several files can be opened in a row.
only
enew!
SimpleStartify minimal
var open_key = ''
for action in values(b:simplestartify_actions)
  if get(action, 'kind', '') ==# 'file'
    open_key = action.key
  endif
endfor
assert_notequal('', open_key)
for [verb, windows, tabs] in [['split', 2, 1], ['vsplit', 2, 1], ['tabedit', 1, 2]]
  only
  if tabpagenr('$') > 1
    tabonly
  endif
  enew!
  SimpleStartify minimal
  assert_equal(1, winnr('$'), verb)
  simplestartify#ActivateKey(open_key, verb)
  assert_equal(windows, winnr('$'), verb)
  assert_equal(tabs, tabpagenr('$'), verb)
  assert_notequal('startify', &filetype, verb)
endfor
only
tabonly
enew!

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
