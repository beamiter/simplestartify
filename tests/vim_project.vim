vim9script

# The project-session feature lives in two autocommands rather than in a
# function, and calling simplestartify#session#Autoload() directly - which is
# all tests/vim_session.vim does - exercises neither of them.  What went wrong
# in both cases was the same: a load runs DeleteListedBuffers(), so an autoload
# that fires when the user did not ask for a workspace silently throws away the
# buffer they did ask for.  Everything here drives the real events: VimEnter
# through a child Vim started the way a user starts one, DirChanged through an
# actual :lcd and :cd in this one.

set nocompatible
set nomore
set hidden

const ROOT = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
const TEMP = resolve(tempname())
mkdir(TEMP .. '/sessions', 'p')

# ---------------------------------------------------------------------------
# VimEnter: a file on the command line outranks a Session.vim beside it.
# ---------------------------------------------------------------------------

const PROJECT = TEMP .. '/project'
mkdir(PROJECT, 'p')
writefile(['readme'], PROJECT .. '/README.md')
writefile(['other'], PROJECT .. '/other.txt')
writefile(['edit other.txt'], PROJECT .. '/Session.vim')

const REPORT = TEMP .. '/report.txt'
const CHILD = TEMP .. '/child.vim'
# Legacy script on purpose: it is a -u file, and its only job is to load the
# plugin and report.  The probe is registered after the plugin so it runs
# after simplestartify#Start(), autocommands being executed in definition
# order regardless of group.
writefile([
  'set nocompatible',
  'set nomore',
  'let g:simplestartify_session_autoload = 1',
  'let g:simplestartify_mru_persist = 0',
  'let g:simplestartify_session_dir = ' .. string(TEMP .. '/sessions'),
  'set runtimepath^=' .. fnameescape(ROOT),
  'source ' .. fnameescape(ROOT .. '/plugin/simplestartify.vim'),
  'function! s:Probe() abort',
  '  let names = map(getbufinfo({"buflisted": 1}),',
  '        \ {_, info -> fnamemodify(info.name, ":t")})',
  '  call writefile([string(argc()), v:this_session, join(names, ",")],',
  '        \ ' .. string(REPORT) .. ')',
  '  qall!',
  'endfunction',
  'autocmd VimEnter * call s:Probe()',
  ], CHILD)

def RunChild(arguments: string): list<string>
  delete(REPORT)
  var command = printf('cd %s && %s -Nu %s -n -i NONE -es %s',
    shellescape(PROJECT), shellescape(v:progpath), shellescape(CHILD),
    arguments)
  var output = system(command)
  assert_true(filereadable(REPORT),
    'child Vim wrote no report: ' .. command .. ' -> ' .. output)
  return filereadable(REPORT) ? readfile(REPORT) : ['', '', '']
enddef

# With no arguments the workspace is restored, which is the whole point of
# g:simplestartify_session_autoload and has to keep working.
var bare = RunChild('')
assert_equal('0', bare[0])
assert_match('Session\.vim$', bare[1])
assert_equal('other.txt', bare[2])

# With a file named on the command line the session must not run at all: it
# would delete the argument buffer on its way in.
var named = RunChild(shellescape('README.md'))
assert_equal('1', named[0])
assert_equal('', named[1])
assert_equal('README.md', named[2])

# ---------------------------------------------------------------------------
# DirChanged: the plugin's own :lcd is not the user entering a project.
# ---------------------------------------------------------------------------

const REPO = TEMP .. '/repo'
mkdir(REPO .. '/.git', 'p')
const WANTED = REPO .. '/wanted.txt'
writefile(['wanted'], WANTED)
writefile(['session buffer'], REPO .. '/sessionbuf.txt')
writefile(['let g:project_loaded = 1', 'edit sessionbuf.txt'],
  REPO .. '/Session.vim')

execute 'set runtimepath^=' .. fnameescape(ROOT)
g:simplestartify_auto_open = 0
g:simplestartify_mru_persist = 0
g:simplestartify_session_dir = TEMP .. '/sessions'
g:simplestartify_session_autoload = 1
g:simplestartify_change_to_vcs_root = 1
g:simplestartify_bookmarks = [WANTED]
g:project_loaded = 0
execute 'source ' .. fnameescape(ROOT .. '/plugin/simplestartify.vim')

execute 'lcd ' .. fnameescape(REPO)
v:this_session = ''
enew!

def BookmarkLine(): number
  for [lnum, action] in items(get(b:, 'simplestartify_actions', {}))
    if get(action, 'kind', '') ==# 'bookmark'
          \ && get(action, 'path', '') ==# WANTED
      return str2nr(lnum)
    endif
  endfor
  return 0
enddef

SimpleStartify
var bookmark = BookmarkLine()
assert_notequal(0, bookmark)
cursor(bookmark, 1)
simplestartify#Activate()
# The :lcd to the Git root happens inside Activate().  Before the DirChanged
# hook was narrowed to the global scope it re-entered the session loader here,
# and wanted.txt was gone by the time the user saw the screen.
assert_equal(REPO, getcwd())
assert_equal(WANTED, expand('%:p'))
assert_equal('', v:this_session)
assert_equal(0, g:project_loaded)
assert_equal([WANTED], mapnew(getbufinfo({buflisted: 1}),
  (_, info) => info.name))

# A global :cd is the user saying "I am working on this now", and that still
# restores the workspace.
execute 'cd ' .. fnameescape(TEMP)
execute 'cd ' .. fnameescape(REPO)
assert_equal(1, g:project_loaded)
assert_equal(fnamemodify(REPO .. '/Session.vim', ':p'), v:this_session)
assert_equal('sessionbuf.txt', fnamemodify(expand('%:p'), ':t'))

g:simplestartify_session_autoload = 0
v:this_session = ''
execute 'cd ' .. fnameescape(ROOT)
delete(TEMP, 'rf')
if !empty(v:errors)
  writefile(v:errors, '/dev/stderr')
  cquit 1
endif
qall!
