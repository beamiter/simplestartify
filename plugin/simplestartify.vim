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
set shortmess+=I

command! -nargs=? -bar -complete=customlist,simplestartify#CompleteStyle
      \ SimpleStartify call simplestartify#Open(<q-args>)
command! -nargs=0 -bar SimpleStartifyRefresh call simplestartify#Refresh()
command! -nargs=0 -bar SimpleStartifyNextStyle call simplestartify#NextStyle()
command! -nargs=0 -bar SimpleStartifyHealth call simplestartify#Health()
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
