vim9script

# Window management: where :SimpleStartify puts the dashboard, what the quit
# entry means when the dashboard is one window among several, and whether
# closing the last file leaves you on a blank buffer or back on the start
# screen.

set nocompatible
set nomore
set hidden

const ROOT = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
const TEMP = resolve(tempname())
mkdir(TEMP .. '/sessions', 'p')
const NOTE = TEMP .. '/note.txt'
writefile(['hello'], NOTE)

execute 'set runtimepath^=' .. fnameescape(ROOT)
g:simplestartify_auto_open = 0
g:simplestartify_session_dir = TEMP .. '/sessions'
g:simplestartify_mru_persist = 0
execute 'source ' .. fnameescape(ROOT .. '/plugin/simplestartify.vim')

def ActionKey(kind: string): string
  for action in values(get(b:, 'simplestartify_actions', {}))
    if get(action, 'kind', '') ==# kind
      return get(action, 'key', '')
    endif
  endfor
  return ''
enddef

def WipeAll()
  for info in getbufinfo({buflisted: 1})
    execute 'silent! bwipeout! ' .. info.bufnr
  endfor
enddef

assert_equal('auto', g:simplestartify_quit_action)
assert_equal(0, g:simplestartify_reopen_on_empty)

# Without a modifier the dashboard still takes the current window, which is
# what every existing mapping and autocmd expects.
only
enew!
SimpleStartify minimal
assert_equal(1, winnr('$'))
assert_equal('startify', &filetype)

# A placement modifier opens the dashboard beside the work instead of over it,
# and the origin is the buffer the split came from, not the dashboard.
only
execute 'edit ' .. fnameescape(NOTE)
var note_buffer = bufnr()
vertical SimpleStartify minimal
assert_equal(2, winnr('$'))
assert_equal('startify', &filetype)
assert_equal(note_buffer, b:simplestartify_origin)
wincmd p
assert_equal(fnamemodify(NOTE, ':p'), expand('%:p'))

# :tab SimpleStartify is the other half of the same request.
only
execute 'edit ' .. fnameescape(NOTE)
tab SimpleStartify minimal
assert_equal(2, tabpagenr('$'))
assert_equal(1, winnr('$'))
assert_equal('startify', &filetype)
tabclose
assert_equal(1, tabpagenr('$'))

# The vim-startify command name honours modifiers too.
only
enew!
botright SimpleStartify minimal
assert_equal(2, winnr('$'))
only
enew!
vertical Startify
assert_equal(2, winnr('$'))
assert_equal('startify', &filetype)

# A modifier that is not about window placement is dropped rather than handed
# to :new - `noautocmd` would suppress the FileType event the highlighting
# rides on, and `silent` would swallow the refusals Open() reports.
only
enew!
silent SimpleStartify minimal
assert_equal(1, winnr('$'))
assert_equal('startify', &filetype)

# The quit entry in a split closes that window.  It used to run a bare :quit,
# which is the same thing here but means "leave Vim" the moment the dashboard
# is alone - and the entry is offered as a way out of the dashboard.
only
execute 'edit ' .. fnameescape(NOTE)
vertical SimpleStartify minimal
var dashboard = bufnr()
var quit_key = ActionKey('quit')
assert_notequal('', quit_key)
simplestartify#ActivateKey(quit_key)
assert_equal(1, winnr('$'))
assert_false(bufexists(dashboard))
assert_equal(fnamemodify(NOTE, ':p'), expand('%:p'))

# g:simplestartify_quit_action = 'close' pins that meaning; the dashboard as
# the only window then has nothing to close and leaves Vim instead, which is
# checked below through the modified-buffer refusal rather than by quitting.
g:simplestartify_quit_action = 'close'
only
execute 'edit ' .. fnameescape(NOTE)
split
SimpleStartify minimal
dashboard = bufnr()
simplestartify#ActivateKey(quit_key)
assert_equal(1, winnr('$'))
assert_false(bufexists(dashboard))
g:simplestartify_quit_action = 'auto'

# Quitting the last window with unsaved work elsewhere raised E37 straight out
# of the mapping: a raw Vim error stack on a screen whose job is to be
# friendly, and no hint about which buffer was in the way.
only
execute 'edit ' .. fnameescape(NOTE)
setline(1, 'unsaved change')
SimpleStartify minimal
assert_equal(1, winnr('$'))
assert_equal(1, tabpagenr('$'))
var refusal = execute('call simplestartify#ActivateKey("' .. quit_key .. '")')
assert_match('modified buffers would be lost', refusal)
assert_match('note.txt', refusal)
assert_equal('startify', &filetype)

# ... and the same refusal covers :qall, so the option cannot be used to lose
# work either.
g:simplestartify_quit_action = 'qall'
refusal = execute('call simplestartify#ActivateKey("' .. quit_key .. '")')
assert_match('qall!', refusal)
assert_equal('startify', &filetype)
g:simplestartify_quit_action = 'auto'

WipeAll()

# Closing the last file drops Vim on a blank [No Name] buffer.  Opt in and the
# dashboard comes back instead.  The real path runs from a timer, because
# BufDelete fires while the buffer is still being taken apart; -es never
# reaches the main loop, so the check itself is driven directly here.
g:simplestartify_reopen_on_empty = 1
only
execute 'edit ' .. fnameescape(NOTE)
bdelete
assert_equal('', bufname())
assert_notequal('startify', &filetype)
simplestartify#ReopenIfEmpty()
assert_equal('startify', &filetype)

# A named buffer that is merely hidden is still work in progress, so an empty
# window next to it is left alone.
WipeAll()
only
execute 'edit ' .. fnameescape(NOTE)
enew
assert_equal('', bufname())
simplestartify#ReopenIfEmpty()
assert_notequal('startify', &filetype)

# A modified scratch buffer is not "nothing to look at" either.
WipeAll()
only
enew!
setline(1, 'scratch work')
simplestartify#ReopenIfEmpty()
assert_notequal('startify', &filetype)

# And the whole thing stays off unless asked for.
WipeAll()
g:simplestartify_reopen_on_empty = 0
only
enew!
simplestartify#ReopenIfEmpty()
assert_notequal('startify', &filetype)
# Scheduling is gated on the same flag, so a Vim that never enabled it does
# not allocate a timer per buffer deletion.
var timers = len(timer_info())
simplestartify#ScheduleReopen()
assert_equal(timers, len(timer_info()))

execute 'lcd ' .. fnameescape(ROOT)
delete(TEMP, 'rf')
if !empty(v:errors)
  writefile(v:errors, '/dev/stderr')
  cquit 1
endif
qall!
