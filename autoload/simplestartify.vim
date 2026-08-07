vim9script

const RECENT_KEYS = split('123456789', '\zs')
const SESSION_KEYS = split('abcefghilmopstuvwxyz', '\zs')
const STYLE_GROUPS = {
  minimal: 'SimpleStartifyHeaderMinimal',
  boxed: 'SimpleStartifyHeaderBoxed',
  centered: 'SimpleStartifyHeaderCentered',
  terminal: 'SimpleStartifyHeaderTerminal',
}

var random_state = srand()
var last_style = ''

def Notify(message: string, error: bool = false)
  execute error ? 'echohl ErrorMsg' : 'echohl ModeMsg'
  echomsg '[SimpleStartify] ' .. message
  echohl None
enddef

def EmitUser(name: string)
  if exists('#User#' .. name)
    execute 'doautocmd <nomodeline> User ' .. name
  endif
enddef

def Flag(name: string, fallback: number): bool
  var value = get(g:, name, fallback)
  if type(value) == v:t_bool
    return value
  endif
  if type(value) == v:t_number
    return value != 0
  endif
  return fallback != 0
enddef

def Count(name: string, fallback: number, maximum: number): number
  var value = get(g:, name, fallback)
  if type(value) != v:t_number
    return fallback
  endif
  return min([maximum, max([0, value])])
enddef

def CleanLabel(text: string): string
  return substitute(text, '[\r\n\t]', ' ', 'g')
enddef

def DisplayPath(path: string): string
  var absolute = fnamemodify(path, ':p')
  var relative = fnamemodify(absolute, ':.')
  if relative !=# absolute
        \ && relative !=# '..'
        \ && relative !~# '^\.\.[\\/]'
    return CleanLabel(relative)
  endif
  return CleanLabel(fnamemodify(absolute, ':~'))
enddef

def RecentFiles(): list<dict<any>>
  var out: list<dict<any>> = []
  var seen: dict<bool> = {}
  var limit = min([Count('simplestartify_recent_count', 7, len(RECENT_KEYS)), len(RECENT_KEYS)])
  if !exists('v:oldfiles') || limit == 0
    return out
  endif
  for candidate in v:oldfiles
    if type(candidate) != v:t_string || empty(candidate)
      continue
    endif
    var path = fnamemodify(candidate, ':p')
    if !filereadable(path) || has_key(seen, path)
      continue
    endif
    seen[path] = true
    var index = len(out)
    add(out, {
      key: RECENT_KEYS[index],
      kind: 'file',
      label: DisplayPath(path),
      path: path,
    })
    if len(out) >= limit
      break
    endif
  endfor
  return out
enddef

def Sessions(): list<dict<any>>
  var out: list<dict<any>> = []
  var limit = min([Count('simplestartify_session_count', 4, len(SESSION_KEYS)), len(SESSION_KEYS)])
  if limit == 0
    return out
  endif
  for name in simplestartify#session#List()
    var index = len(out)
    add(out, {
      key: SESSION_KEYS[index],
      kind: 'session',
      label: CleanLabel(name),
      name: name,
    })
    if len(out) >= limit
      break
    endif
  endfor
  return out
enddef

def Model(): dict<any>
  return {
    cwd: CleanLabel(fnamemodify(getcwd(), ':~')),
    recent: RecentFiles(),
    sessions: Sessions(),
    special: [
      {key: 'n', kind: 'new', label: 'new empty buffer'},
      {key: 'r', kind: 'restyle', label: 'roll another UI style'},
      {key: 'q', kind: 'quit', label: 'quit'},
    ],
    footer: '<Enter> open  j/k move  r restyle  R refresh  d delete session',
  }
enddef

def ConfiguredStyle(): string
  var value = get(g:, 'simplestartify_style', 'random')
  return type(value) == v:t_string ? value : 'random'
enddef

def ChooseStyle(requested: string = '', avoid: string = ''): string
  var choice = empty(requested) ? ConfiguredStyle() : requested
  var width = DashboardWidth()
  var candidates = simplestartify#ui#Candidates(
    get(g:, 'simplestartify_styles', simplestartify#ui#Styles()), width)
  if choice !=# 'random'
    if index(simplestartify#ui#Styles(), choice) >= 0
      return choice
    endif
    Notify('unknown style ' .. string(choice) .. '; using random', true)
  endif
  var avoid_repeat = Flag('simplestartify_avoid_repeat', 1)
  return simplestartify#ui#PickStyle(
    candidates,
    empty(avoid) ? last_style : avoid,
    rand(random_state),
    avoid_repeat)
enddef

def IsDashboard(): bool
  return get(b:, 'simplestartify', 0) == 1 && &filetype ==# 'startify'
enddef

def DashboardWidth(): number
  var width = max([1, winwidth(0)])
  if IsDashboard()
    for info in getwininfo()
      if info.bufnr == bufnr()
        width = min([width, max([1, info.width])])
      endif
    endfor
  endif
  return width
enddef

def ConfigureBuffer(origin: number)
  silent! file [SimpleStartify]
  setlocal buftype=nofile
  setlocal bufhidden=wipe
  setlocal nobuflisted
  setlocal noswapfile
  setlocal modifiable
  setlocal noreadonly
  setlocal nowrap
  setlocal nonumber
  setlocal norelativenumber
  setlocal nocursorcolumn
  setlocal cursorline
  setlocal nolist
  setlocal nospell
  setlocal colorcolumn=
  setlocal foldcolumn=0
  setlocal signcolumn=no
  setlocal textwidth=0
  setlocal statusline=\ SimpleStartify
  &l:filetype = 'startify'
  b:simplestartify = 1
  b:simplestartify_origin = origin
enddef

def HighlightLines(group: string, lines: list<number>)
  for lnum in lines
    if lnum >= 1 && lnum <= line('$')
      execute $'syntax match {group} /\%{lnum}l.*/'
    endif
  endfor
enddef

def ApplyHighlights(layout: dict<any>, style: string)
  syntax clear
  HighlightLines('SimpleStartifyEntry', get(layout, 'entry_lines', []))
  syntax match SimpleStartifyKey /\[[0-9A-Za-z]\]/
  syntax match SimpleStartifyMuted /(none yet)/
  HighlightLines(get(STYLE_GROUPS, style, 'SimpleStartifyHeader'),
    get(layout, 'header_lines', []))
  HighlightLines('SimpleStartifySection', get(layout, 'section_lines', []))
  HighlightLines('SimpleStartifyFooter', get(layout, 'footer_lines', []))
enddef

def InstallMappings(actions: dict<any>)
  nnoremap <buffer><silent> <CR> <ScriptCmd>simplestartify#Activate()<CR>
  nnoremap <buffer><silent> <2-LeftMouse> <LeftMouse><ScriptCmd>simplestartify#Activate()<CR>
  nnoremap <buffer><silent> j <ScriptCmd>simplestartify#Move(1)<CR>
  nnoremap <buffer><silent> k <ScriptCmd>simplestartify#Move(-1)<CR>
  nnoremap <buffer><silent> <Tab> <ScriptCmd>simplestartify#Move(1)<CR>
  nnoremap <buffer><silent> <S-Tab> <ScriptCmd>simplestartify#Move(-1)<CR>
  nnoremap <buffer><silent> R <ScriptCmd>simplestartify#Refresh()<CR>
  nnoremap <buffer><silent> d <ScriptCmd>simplestartify#DeleteCurrentSession()<CR>
  for action in values(actions)
    var key = get(action, 'key', '')
    if type(key) == v:t_string && key =~# '^[0-9A-Za-z]$'
      execute $'nnoremap <buffer><silent> {key} '
            \ .. $'<ScriptCmd>simplestartify#ActivateKey({string(key)})<CR>'
    endif
  endfor
enddef

def Render(style: string, selected_key: string = '')
  var layout = simplestartify#ui#Build(Model(), style, DashboardWidth())
  setlocal modifiable
  silent! execute 'keepjumps %delete _'
  var lines = get(layout, 'lines', [''])
  if empty(lines)
    lines = ['']
  endif
  setline(1, lines)
  if line('$') > len(lines)
    execute $':{len(lines) + 1},$delete _'
  endif
  b:simplestartify_style = style
  b:simplestartify_actions = get(layout, 'actions', {})
  setlocal nomodifiable
  setlocal nomodified
  ApplyHighlights(layout, style)
  InstallMappings(b:simplestartify_actions)

  var target = get(layout, 'cursor', 1)
  if !empty(selected_key)
    for [lnum, action] in items(b:simplestartify_actions)
      if get(action, 'key', '') ==# selected_key
        target = str2nr(lnum)
        break
      endif
    endfor
  endif
  cursor(target, 1)
  normal! zz
enddef

def CurrentKey(): string
  if !IsDashboard()
    return ''
  endif
  var action = get(get(b:, 'simplestartify_actions', {}), string(line('.')), {})
  return get(action, 'key', '')
enddef

export def SetupHighlights()
  highlight default link SimpleStartifyHeader Title
  highlight default link SimpleStartifyHeaderMinimal Identifier
  highlight default link SimpleStartifyHeaderBoxed Title
  highlight default link SimpleStartifyHeaderCentered Constant
  highlight default link SimpleStartifyHeaderTerminal String
  highlight default link SimpleStartifySection Statement
  highlight default link SimpleStartifyEntry Normal
  highlight default link SimpleStartifyKey Special
  highlight default link SimpleStartifyMuted Comment
  highlight default link SimpleStartifyFooter Comment
enddef

export def CompleteStyle(lead: string, _line: string, _position: number): list<string>
  var styles = ['random'] + simplestartify#ui#Styles()
  return filter(styles, (_, style) => stridx(style, lead) == 0)
enddef

export def Open(requested: string = '')
  if &modified && !&hidden && !IsDashboard()
    Notify('save the current buffer before opening the dashboard', true)
    return
  endif
  if !IsDashboard()
    var origin = bufnr()
    silent keepalt enew
    ConfigureBuffer(origin)
  endif
  var style = ChooseStyle(requested, get(b:, 'simplestartify_style', ''))
  last_style = style
  Render(style)
  EmitUser('SimpleStartifyReady')
  EmitUser('Startified')
  EmitUser('StartifyReady')
enddef

export def AutoOpen()
  if !Flag('simplestartify_auto_open', 1)
        \ || argc() != 0
        \ || &insertmode
        \ || !&modifiable
        \ || &modified
        \ || &buftype !=# ''
        \ || !empty(bufname())
        \ || line('$') != 1
        \ || getline(1) !=# ''
    return
  endif
  Open()
enddef

export def Refresh()
  if !IsDashboard()
    Open()
    return
  endif
  var selected = CurrentKey()
  var style = get(b:, 'simplestartify_style', '')
  if empty(style)
    style = ChooseStyle()
  endif
  Render(style, selected)
enddef

export def NextStyle()
  if !IsDashboard()
    Open()
    return
  endif
  var selected = CurrentKey()
  var style = ChooseStyle('random', get(b:, 'simplestartify_style', ''))
  last_style = style
  Render(style, selected)
enddef

export def Reflow()
  if IsDashboard()
    var selected = CurrentKey()
    Render(get(b:, 'simplestartify_style', 'minimal'), selected)
  endif
enddef

export def Move(direction: number)
  if !IsDashboard()
    return
  endif
  var action_lines = mapnew(keys(get(b:, 'simplestartify_actions', {})),
    (_, value) => str2nr(value))
  sort(action_lines, 'n')
  if empty(action_lines)
    return
  endif
  var current = index(action_lines, line('.'))
  if current < 0
    current = direction > 0 ? -1 : 0
  endif
  var target = (current + (direction >= 0 ? 1 : -1)) % len(action_lines)
  if target < 0
    target += len(action_lines)
  endif
  cursor(action_lines[target], 1)
enddef

def ProjectRoot(path: string): string
  var directory = isdirectory(path) ? path : fnamemodify(path, ':h')
  var git_dir = finddir('.git', directory .. ';')
  var git_file = findfile('.git', directory .. ';')
  var marker = !empty(git_dir) ? git_dir : git_file
  return empty(marker) ? '' : fnamemodify(marker, ':h')
enddef

def OpenFile(path: string)
  if !filereadable(path)
    Notify('file is no longer readable: ' .. path, true)
    Refresh()
    return
  endif
  execute 'edit ' .. fnameescape(path)
  if Flag('simplestartify_change_to_vcs_root', 0)
    var root = ProjectRoot(path)
    if !empty(root)
      execute 'silent lcd ' .. fnameescape(root)
      return
    endif
  endif
  if Flag('simplestartify_change_to_dir', 0)
    execute 'silent lcd ' .. fnameescape(fnamemodify(path, ':h'))
  endif
enddef

def Run(action: dict<any>)
  var kind = get(action, 'kind', '')
  if kind ==# 'file'
    OpenFile(get(action, 'path', ''))
  elseif kind ==# 'session'
    simplestartify#session#Load(false, get(action, 'name', ''))
  elseif kind ==# 'new'
    enew
  elseif kind ==# 'restyle'
    NextStyle()
  elseif kind ==# 'quit'
    quit
  endif
enddef

export def Activate()
  if !IsDashboard()
    return
  endif
  var actions = get(b:, 'simplestartify_actions', {})
  var action = get(actions, string(line('.')), {})
  if empty(action)
    var nearest = 0
    var distance = 0x7fffffff
    for lnum in keys(actions)
      var delta = abs(str2nr(lnum) - line('.'))
      if delta < distance
        nearest = str2nr(lnum)
        distance = delta
      endif
    endfor
    if nearest > 0
      cursor(nearest, 1)
      action = get(actions, string(nearest), {})
    endif
  endif
  if !empty(action)
    Run(action)
  endif
enddef

export def ActivateKey(key: string)
  if !IsDashboard()
    return
  endif
  for [lnum, action] in items(get(b:, 'simplestartify_actions', {}))
    if get(action, 'key', '') ==# key
      cursor(str2nr(lnum), 1)
      Run(action)
      return
    endif
  endfor
enddef

export def DeleteCurrentSession()
  if !IsDashboard()
    return
  endif
  var action = get(get(b:, 'simplestartify_actions', {}), string(line('.')), {})
  if get(action, 'kind', '') !=# 'session'
    Notify('select a session first', true)
    return
  endif
  var name = get(action, 'name', '')
  if confirm('Delete session ' .. name .. '?', "&Delete\n&Cancel", 2) == 1
        \ && simplestartify#session#Delete(true, name)
    Refresh()
  endif
enddef

export def Health(): dict<any>
  var width = DashboardWidth()
  var styles = simplestartify#ui#Candidates(
    get(g:, 'simplestartify_styles', simplestartify#ui#Styles()), width)
  var session_dir = simplestartify#session#Dir()
  var result = {
    ok: !empty(styles) && !empty(session_dir),
    styles: styles,
    session_dir: session_dir,
    session_writable: isdirectory(session_dir) && filewritable(session_dir) == 2,
  }
  g:simplestartify_health_last = result
  echomsg '[SimpleStartify] styles: ' .. join(styles, ', ')
  echomsg '[SimpleStartify] session directory: ' .. session_dir
  return result
enddef
