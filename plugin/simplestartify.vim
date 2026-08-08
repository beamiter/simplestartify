vim9script

if exists('g:loaded_simplestartify')
  finish
endif
g:loaded_simplestartify = 1

if v:version < 901
  echohl WarningMsg
  echomsg '[SimpleStartify] Vim 9.1 or newer is required.'
  echohl None
  finish
endif

def Legacy(name: string, fallback: any): any
  var current = 'simplestartify_' .. name
  if has_key(g:, current)
    return get(g:, current)
  endif
  return get(g:, 'startify_' .. name, fallback)
enddef

def Flag(value: any, fallback: number): number
  if type(value) == v:t_bool
    return value ? 1 : 0
  endif
  if type(value) == v:t_number
    return value == 0 ? 0 : 1
  endif
  return fallback
enddef

def Clamp(value: any, fallback: number, minimum: number, maximum: number): number
  return type(value) == v:t_number
        \ ? min([maximum, max([minimum, value])])
        \ : fallback
enddef

def Text(value: any, fallback: string): string
  return type(value) == v:t_string ? value : fallback
enddef

def Enum(value: any, allowed: list<string>, fallback: string): string
  return type(value) == v:t_string && index(allowed, value) >= 0
        \ ? value
        \ : fallback
enddef

# Section types the dashboard knows how to fill.  "dir" and "project" are the
# same recent-files list narrowed to the working directory and to its VCS
# root, which is the one thing users of other start screens ask for most.
const SECTION_TYPES = ['files', 'dir', 'project', 'sessions', 'bookmarks',
  'commands', 'special']

# The default deck is exactly what the dashboard drew before sections existed:
# bookmarks and commands are empty out of the box and an empty configurable
# section is not rendered, so no existing screen changes shape by upgrading.
const DEFAULT_LISTS = [{type: 'files'}, {type: 'sessions'},
  {type: 'bookmarks'}, {type: 'commands'}, {type: 'special'}]

# Keys the dashboard itself owns.  An entry mapping is installed after these,
# so an explicitly requested "d" would quietly replace session deletion; such a
# request is dropped and the entry is given an ordinary automatic key instead.
const RESERVED_KEYS = ['n', 'r', 'q', 's', 't', 'v', 'j', 'k', 'd', 'D', 'R', '?']

# Paths that are readable but are never what "recently edited" means.  This
# deliberately stays short: everything here is a file some other tool wrote
# under .git, not a document, and a default that guessed at /tmp or a scheme
# prefix would hide files people really do edit.
const DEFAULT_SKIPLIST = [
  '\.git[\\/]\%(COMMIT_EDITMSG\|MERGE_MSG\|TAG_EDITMSG\|SQUASH_MSG\)$',
  '\.git[\\/]rebase-\%(merge\|apply\)[\\/]',
]

def EntryKey(value: any): string
  return type(value) == v:t_string && value =~# '^[0-9A-Za-z]$'
        \ && index(RESERVED_KEYS, value) < 0
        \ ? value
        \ : ''
enddef

def Header(value: any): string
  # vim-startify's g:startify_lists writes a header as a one-element list of
  # already-indented text, so accept that shape as well as a plain string.
  if type(value) == v:t_string
    return trim(value)
  endif
  if type(value) == v:t_list
    for item in value
      if type(item) == v:t_string && !empty(trim(item))
        return trim(item)
      endif
    endfor
  endif
  return ''
enddef

def Lists(value: any): list<dict<any>>
  if type(value) != v:t_list
    return deepcopy(DEFAULT_LISTS)
  endif
  var out: list<dict<any>> = []
  for item in value
    var spec: dict<any> = {}
    if type(item) == v:t_string
      spec = {type: item}
    elseif type(item) == v:t_dict
      spec = copy(item)
    else
      continue
    endif
    var kind = get(spec, 'type', '')
    if type(kind) != v:t_string || index(SECTION_TYPES, kind) < 0
      continue
    endif
    var normalized: dict<any> = {type: kind}
    var header = Header(get(spec, 'header', ''))
    if !empty(header)
      normalized.header = header
    endif
    if type(get(spec, 'limit', '')) == v:t_number
      normalized.limit = max([0, spec.limit])
    endif
    add(out, normalized)
  endfor
  # As with the style pool: a list that normalizes to nothing is a mistake, and
  # a dashboard with no sections at all is not a state worth offering.
  return empty(out) ? deepcopy(DEFAULT_LISTS) : out
enddef

def Bookmarks(value: any): list<dict<any>>
  if type(value) != v:t_list
    return []
  endif
  var out: list<dict<any>> = []
  for item in value
    if type(item) == v:t_string && !empty(item)
      add(out, {key: '', path: item})
    elseif type(item) == v:t_dict
      for [key, target] in items(item)
        if type(target) == v:t_string && !empty(target)
          add(out, {key: EntryKey(key), path: target})
        endif
      endfor
    endif
  endfor
  return out
enddef

def CommandText(value: any): string
  # People write commands with the colon they would type; keep both forms
  # working rather than making the leading character significant.
  return type(value) == v:t_string ? trim(substitute(value, '^\s*:\+', '', '')) : ''
enddef

def CommandEntry(key: string, value: any): dict<any>
  if type(value) == v:t_string
    var plain = CommandText(value)
    return empty(plain) ? {} : {key: key, command: plain, label: plain}
  endif
  # vim-startify's pair form is [description, command], in that order.
  if type(value) == v:t_list && len(value) == 2 && type(value[0]) == v:t_string
    var listed = CommandText(value[1])
    return empty(listed)
          \ ? {}
          \ : {key: key, command: listed,
              \ label: empty(trim(value[0])) ? listed : trim(value[0])}
  endif
  return {}
enddef

def Commands(value: any): list<dict<any>>
  if type(value) != v:t_list
    return []
  endif
  var out: list<dict<any>> = []
  for item in value
    if type(item) == v:t_dict
      for [key, target] in items(item)
        var keyed = CommandEntry(EntryKey(key), target)
        if !empty(keyed)
          add(out, keyed)
        endif
      endfor
    else
      var plain = CommandEntry('', item)
      if !empty(plain)
        add(out, plain)
      endif
    endif
  endfor
  return out
enddef

def Patterns(value: any): list<string>
  if type(value) != v:t_list
    return copy(DEFAULT_SKIPLIST)
  endif
  var out: list<string> = []
  for item in value
    if type(item) != v:t_string || empty(item)
      continue
    endif
    # An unparsable pattern would throw once per candidate path on every draw
    # and at every BufWinEnter.  Test it once here and drop it if it is broken.
    try
      if 'simplestartify' =~# item
      endif
      add(out, item)
    catch
    endtry
  endfor
  return out
enddef

def StyleList(value: any): list<string>
  if type(value) != v:t_list
    return ['minimal', 'boxed', 'centered', 'terminal']
  endif
  var out: list<string> = []
  for style in value
    if type(style) == v:t_string
          \ && index(['minimal', 'boxed', 'centered', 'terminal'], style) >= 0
          \ && index(out, style) < 0
      add(out, style)
    endif
  endfor
  return empty(out) ? ['minimal', 'boxed', 'centered', 'terminal'] : out
enddef

# Defaults follow the simple* convention: all configuration is normalized once
# in plugin/ and consumed as stable values by autoload code.
g:simplestartify_auto_open = Flag(
  Legacy('auto_open', !Flag(Legacy('disable_at_vimenter', 0), 0)), 1)
g:simplestartify_style = Text(Legacy('style', 'random'), 'random')
g:simplestartify_styles = StyleList(Legacy(
  'styles', ['minimal', 'boxed', 'centered', 'terminal']))
g:simplestartify_avoid_repeat = Flag(Legacy('avoid_repeat', 1), 1)
g:simplestartify_lists = Lists(Legacy('lists', DEFAULT_LISTS))
g:simplestartify_bookmarks = Bookmarks(Legacy('bookmarks', []))
g:simplestartify_commands = Commands(Legacy('commands', []))
# An empty list here is a real request - "skip nothing" - unlike an empty
# section list, so it is honoured rather than replaced by the default.
g:simplestartify_skiplist = Patterns(Legacy('skiplist', DEFAULT_SKIPLIST))
g:simplestartify_recent_count = Clamp(Legacy('recent_count', 7), 7, 0, 9)
g:simplestartify_session_count = Clamp(Legacy('session_count', 4), 4, 0, 13)
g:simplestartify_session_dir = Text(
  Legacy('session_dir', '~/.vim/session'), '~/.vim/session')
g:simplestartify_session_persistence = Flag(
  Legacy('session_persistence', 0), 0)
g:simplestartify_change_to_vcs_root = Flag(
  Legacy('change_to_vcs_root', 0), 0)
g:simplestartify_change_to_dir = Flag(Legacy('change_to_dir', 0), 0)
g:simplestartify_open_action = Enum(Legacy('open_action', 'edit'),
  ['edit', 'split', 'vsplit', 'tabedit'], 'edit')

def DefaultMruFile(): string
  # XDG when the user has opted into it, otherwise beside the session
  # directory so everything this plugin stores lives in one familiar place.
  return empty($XDG_STATE_HOME)
        \ ? '~/.vim/simplestartify-mru'
        \ : $XDG_STATE_HOME .. '/simplestartify/mru'
enddef

g:simplestartify_mru_persist = Flag(Legacy('mru_persist', 1), 1)
g:simplestartify_mru_max = Clamp(Legacy('mru_max', 200), 200, 0, 5000)
g:simplestartify_mru_file = Text(
  Legacy('mru_file', DefaultMruFile()), DefaultMruFile())

# Prevent vim-startify from double-registering its VimEnter hook if both
# plugins happen to be present on runtimepath during a migration.
g:loaded_startify = 1

# The dashboard replaces the intro screen, and suppressing it here rather than
# at VimEnter avoids a flash of the built-in message first.  A user who turned
# automatic opening off asked for ordinary Vim, though, and used to lose their
# intro anyway - so follow the same switch unless told otherwise.
g:simplestartify_hide_intro = Flag(
  Legacy('hide_intro', g:simplestartify_auto_open), g:simplestartify_auto_open)
if g:simplestartify_hide_intro
  set shortmess+=I
endif

command! -nargs=? -bar -complete=customlist,simplestartify#CompleteStyle
      \ SimpleStartify call simplestartify#Open(<q-args>)
command! -nargs=0 -bar SimpleStartifyRefresh call simplestartify#Refresh()
command! -nargs=0 -bar SimpleStartifyNextStyle call simplestartify#NextStyle()
command! -nargs=0 -bar SimpleStartifyHealth call simplestartify#HealthReport()
command! -nargs=0 -bar SimpleStartifyClean call simplestartify#CleanSessions()
command! -nargs=? -bar -complete=file
      \ SimpleStartifyForget call simplestartify#ForgetRecent(<q-args>)

# vim-startify compatible command surface.
command! -nargs=0 -bar Startify call simplestartify#Open()
command! -nargs=? -bar -bang -complete=customlist,simplestartify#session#Complete
      \ SSave call simplestartify#session#Save(<bang>0, <q-args>)
command! -nargs=? -bar -bang -complete=customlist,simplestartify#session#Complete
      \ SLoad call simplestartify#session#Load(<bang>0, <q-args>)
command! -nargs=? -bar -bang -complete=customlist,simplestartify#session#Complete
      \ SDelete call simplestartify#session#Delete(<bang>0, <q-args>)
command! -nargs=0 -bar -bang SClose call simplestartify#session#Close(<bang>0)

nnoremap <silent> <Plug>(simplestartify-open) <Cmd>SimpleStartify<CR>
nnoremap <silent> <Plug>(simplestartify-refresh) <Cmd>SimpleStartifyRefresh<CR>
nnoremap <silent> <Plug>(simplestartify-next-style) <Cmd>SimpleStartifyNextStyle<CR>
nnoremap <silent> <Plug>(simplestartify-forget) <Cmd>SimpleStartifyForget<CR>
nnoremap <silent> <Plug>(simplestartify-help) <Cmd>call simplestartify#Help()<CR>

simplestartify#SetupHighlights()

augroup SimpleStartify
  autocmd!
  autocmd VimEnter * call simplestartify#AutoOpen()
  autocmd BufWinEnter,BufWritePost * call simplestartify#mru#Touch()
  # Registered before the session hook so a failing recent-files write can
  # never cost the user their session; mru#Save() swallows its own errors.
  autocmd VimLeavePre * call simplestartify#mru#Save()
  autocmd VimLeavePre * call simplestartify#session#Persist()
  autocmd VimResized * call simplestartify#Reflow()
  if exists('##WinResized')
    autocmd WinResized * call simplestartify#Reflow()
  endif
  # WinResized is only delivered once Vim reaches its main loop, so a script
  # that splits and resizes in one go - and any Vim old enough to lack the
  # event - still needs the window-entry hooks.  Reflow is gated on the stored
  # width, so a firing that changed nothing costs one getwininfo().
  autocmd WinEnter,BufWinEnter * call simplestartify#Reflow()
  autocmd ColorScheme * call simplestartify#SetupHighlights()
augroup END
