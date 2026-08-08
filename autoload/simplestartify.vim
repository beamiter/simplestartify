vim9script

const RECENT_KEYS = split('123456789', '\zs')
# s, t and v are deliberately absent: they are the split/tab/vsplit verbs on
# the dashboard, and a session letter that silently stole one of them would be
# a collision nobody could see.
const SESSION_KEYS = split('abcefghilmopuwxyz', '\zs')

# How each entry kind is opened per verb.  Sessions are missing on purpose:
# loading one replaces the whole layout, so "in a split" has no meaning.
const OPEN_VERBS = {
  edit: {file: 'edit', new: 'enew'},
  split: {file: 'split', new: 'new'},
  vsplit: {file: 'vsplit', new: 'vnew'},
  tabedit: {file: 'tabedit', new: 'tabnew'},
}
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

# Stat'ing is the expensive part of building the model, and only nine entries
# can ever carry a digit shortcut, so there is no point walking a thousand-line
# v:oldfiles.  A section narrowed to one directory still wants headroom, hence
# a bound well above what any section can display rather than the section
# limit itself.
const CANDIDATE_SCAN = 100

def RecentCandidates(): list<string>
  var out: list<string> = []
  var seen: dict<bool> = {}
  # The in-session record comes first: v:oldfiles is frozen at startup, so a
  # file opened since then exists only there, and it is by definition more
  # recent than anything viminfo remembers.
  var candidates: list<any> = simplestartify#mru#List()
  if exists('v:oldfiles') && type(v:oldfiles) == v:t_list
    extend(candidates, v:oldfiles)
  endif
  for candidate in candidates
    if type(candidate) != v:t_string || empty(candidate)
      continue
    endif
    var path = fnamemodify(candidate, ':p')
    if has_key(seen, path) || simplestartify#mru#Skipped(path)
          \ || !filereadable(path)
      continue
    endif
    seen[path] = true
    add(out, path)
    if len(out) >= CANDIDATE_SCAN
      break
    endif
  endfor
  return out
enddef

# Both sides are compared as forward-slash paths so a Windows drive path and a
# root recorded with the other separator still match.
def Under(path: string, root: string): bool
  if empty(root)
    return false
  endif
  var directory = substitute(substitute(root, '[\\/]\+$', '', ''), '\\', '/', 'g')
  return stridx(substitute(path, '\\', '/', 'g'), directory .. '/') == 0
enddef

def TakeKey(pool: list<string>): string
  # An exhausted pool is not an error: the entry renders without a marker and
  # stays reachable with the cursor and <CR>.
  return empty(pool) ? '' : remove(pool, 0)
enddef

def FileEntries(
    candidates: list<string>,
    root: string,
    limit: number,
    used: dict<bool>,
    digits: list<string>): list<dict<any>>
  var out: list<dict<any>> = []
  if limit <= 0
    return out
  endif
  for path in candidates
    # A file already shown by an earlier, narrower section is not repeated: a
    # project list followed by the global list would otherwise say everything
    # twice and burn two shortcuts on it.
    if has_key(used, path) || (!empty(root) && !Under(path, root))
      continue
    endif
    used[path] = true
    add(out, {
      key: TakeKey(digits),
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

def SessionEntries(limit: number, letters: list<string>): list<dict<any>>
  var out: list<dict<any>> = []
  if limit <= 0
    return out
  endif
  for name in simplestartify#session#List()
    add(out, {
      key: TakeKey(letters),
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

def Configured(name: string): list<dict<any>>
  var value = get(g:, name, [])
  if type(value) != v:t_list
    return []
  endif
  return filter(copy(value), (_, item) => type(item) == v:t_dict)
enddef

def BookmarkEntries(limit: number, letters: list<string>): list<dict<any>>
  var out: list<dict<any>> = []
  for item in Configured('simplestartify_bookmarks')
    if len(out) >= limit
      break
    endif
    var target = get(item, 'path', '')
    if type(target) != v:t_string || empty(target)
      continue
    endif
    # A bookmark is shown whether or not the target exists yet: it is a place
    # the user asked to keep, and opening a missing one creates the buffer.
    var path = substitute(fnamemodify(expand(target), ':p'), '[\\/]\+$', '', '')
    var key = get(item, 'key', '')
    add(out, {
      key: type(key) == v:t_string && !empty(key) ? key : TakeKey(letters),
      kind: 'bookmark',
      label: DisplayPath(path),
      path: path,
    })
  endfor
  return out
enddef

def CommandEntries(limit: number, letters: list<string>): list<dict<any>>
  var out: list<dict<any>> = []
  for item in Configured('simplestartify_commands')
    if len(out) >= limit
      break
    endif
    var command = get(item, 'command', '')
    if type(command) != v:t_string || empty(command)
      continue
    endif
    var key = get(item, 'key', '')
    add(out, {
      key: type(key) == v:t_string && !empty(key) ? key : TakeKey(letters),
      kind: 'command',
      label: CleanLabel(get(item, 'label', command)),
      command: command,
    })
  endfor
  return out
enddef

# Degrade by width tier rather than letting Fit() ellipsize a long line down
# to nothing: on a narrow window the only thing worth spending columns on is
# the pointer to the full list.
def Footer(width: number): string
  if width >= 72
    return '<CR> open  s/v/t split  j/k move  r restyle  R refresh  ? keys'
  elseif width >= 26
    return '<CR> open   ? keys'
  endif
  return '?'
enddef

const SPECIAL_ENTRIES = [
  {key: 'n', kind: 'new', label: 'new empty buffer'},
  {key: 'r', kind: 'restyle', label: 'roll another UI style'},
  {key: 'q', kind: 'quit', label: 'quit'},
]

# Three names per section because the four layouts address the reader
# differently: minimal spells the heading out, boxed and centered want it
# short enough to survive a frame, and terminal pretends to be a shell
# transcript.  The built-in values are the exact strings the fixed sections
# used before they became configurable.
const SECTION_NAMES = {
  files: {title: 'recent files', short: 'recent', command: 'recent'},
  dir: {title: 'in this directory', short: 'here', command: 'recent --dir'},
  project: {title: 'in this project', short: 'project',
    command: 'recent --project'},
  sessions: {title: 'sessions', short: 'sessions', command: 'session list'},
  bookmarks: {title: 'bookmarks', short: 'bookmarks', command: 'bookmarks'},
  commands: {title: 'commands', short: 'commands', command: 'commands'},
  special: {title: 'actions', short: 'actions', command: 'help --actions'},
}

# These three are the dashboard itself and are drawn even when they have
# nothing in them, because "(none yet)" is the answer to a question the user
# asked.  A bookmarks or commands section nobody configured is not, so an
# empty one is left out rather than adding a row of placeholders.
const ALWAYS_SHOWN = ['files', 'sessions', 'special']
const FILE_SECTIONS = ['files', 'dir', 'project']

const FALLBACK_LISTS = [{type: 'files'}, {type: 'sessions'}, {type: 'special'}]

def Lists(): list<dict<any>>
  var value = get(g:, 'simplestartify_lists', [])
  if type(value) != v:t_list
    return deepcopy(FALLBACK_LISTS)
  endif
  var specs = filter(copy(value), (_, spec) => type(spec) == v:t_dict
        \ && has_key(SECTION_NAMES, get(spec, 'type', '')))
  # plugin/ restores the defaults for a list that normalizes to nothing, but a
  # value assigned after startup skips that; a dashboard with no sections at
  # all is never what the assignment meant.
  return empty(specs) ? deepcopy(FALLBACK_LISTS) : specs
enddef

def ClaimedKeys(): dict<bool>
  var out: dict<bool> = {}
  for item in Configured('simplestartify_bookmarks')
        \ + Configured('simplestartify_commands')
    var key = get(item, 'key', '')
    if type(key) == v:t_string && !empty(key)
      out[key] = true
    endif
  endfor
  return out
enddef

def SectionLimit(spec: dict<any>, fallback: number): number
  var value = get(spec, 'limit', -1)
  return type(value) == v:t_number && value >= 0 ? value : fallback
enddef

def SectionNames(spec: dict<any>, kind: string, entries: list<dict<any>>): dict<string>
  var names = copy(get(SECTION_NAMES, kind, {title: kind, short: kind, command: kind}))
  var header = get(spec, 'header', '')
  if type(header) == v:t_string && !empty(header)
    names = {title: header, short: header, command: header}
  elseif index(FILE_SECTIONS, kind) >= 0
    # The terminal layout is a transcript, so its recent-file line has always
    # shown the limit it was invoked with.
    names.command ..= ' --limit=' .. len(entries)
  endif
  return names
enddef

def Model(): dict<any>
  var digits = copy(RECENT_KEYS)
  var letters = copy(SESSION_KEYS)
  # Keys the user pinned to a bookmark or a command are taken out of both
  # pools first, so an automatic assignment can never land on one of them and
  # leave two entries fighting over the same buffer-local mapping.
  var claimed = ClaimedKeys()
  filter(digits, (_, key) => !has_key(claimed, key))
  filter(letters, (_, key) => !has_key(claimed, key))

  var specs = Lists()
  # Only pay for the recent-files scan when a section actually consumes it.
  var wants_files = !empty(filter(mapnew(specs, (_, spec) => spec.type),
    (_, kind) => index(FILE_SECTIONS, kind) >= 0))
  var candidates: list<string> = wants_files ? RecentCandidates() : []
  var used: dict<bool> = {}
  var recent_limit = Count('simplestartify_recent_count', 7, len(RECENT_KEYS))
  var session_limit = Count('simplestartify_session_count', 4, len(SESSION_KEYS))

  var sections: list<dict<any>> = []
  for spec in specs
    var kind: string = spec.type
    var entries: list<dict<any>> = []
    if kind ==# 'files'
      entries = FileEntries(candidates, '',
        SectionLimit(spec, recent_limit), used, digits)
    elseif kind ==# 'dir'
      entries = FileEntries(candidates, getcwd(),
        SectionLimit(spec, recent_limit), used, digits)
    elseif kind ==# 'project'
      var root = ProjectRoot(getcwd())
      entries = FileEntries(candidates, empty(root) ? getcwd() : root,
        SectionLimit(spec, recent_limit), used, digits)
    elseif kind ==# 'sessions'
      entries = SessionEntries(SectionLimit(spec, session_limit), letters)
    elseif kind ==# 'bookmarks'
      entries = BookmarkEntries(SectionLimit(spec, len(SESSION_KEYS)), letters)
    elseif kind ==# 'commands'
      entries = CommandEntries(SectionLimit(spec, len(SESSION_KEYS)), letters)
    elseif kind ==# 'special'
      var limit = SectionLimit(spec, len(SPECIAL_ENTRIES))
      entries = limit <= 0 ? [] : deepcopy(SPECIAL_ENTRIES)[0 : limit - 1]
    endif
    if empty(entries) && index(ALWAYS_SHOWN, kind) < 0
      continue
    endif
    add(sections, extend({id: kind, entries: entries},
      SectionNames(spec, kind, entries)))
  endfor

  return {
    cwd: CleanLabel(fnamemodify(getcwd(), ':~')),
    sections: sections,
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

# The narrowest window showing the buffer wins: the same lines are on screen
# in all of them, so anything wider would overflow somewhere.
def BufferWidth(buffer: number): number
  var width = 0
  for info in getwininfo()
    if info.bufnr == buffer
      var candidate = max([1, info.width])
      width = width == 0 ? candidate : min([width, candidate])
    endif
  endfor
  return width
enddef

def DashboardWidth(): number
  if IsDashboard()
    var width = BufferWidth(bufnr())
    if width > 0
      return width
    endif
  endif
  return max([1, winwidth(0)])
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

const MUTED_TEXT = '(none yet)'

const LINE_GROUPS = ['SimpleStartifyHeader', 'SimpleStartifyHeaderMinimal',
  'SimpleStartifyHeaderBoxed', 'SimpleStartifyHeaderCentered',
  'SimpleStartifyHeaderTerminal', 'SimpleStartifySection',
  'SimpleStartifyEntry', 'SimpleStartifyFooter']

# Text properties are exact and cannot mis-prioritize.  The syntax approach
# below them could not express "this key marker, inside this whole-line match"
# without a contained item, and it rebuilt roughly forty regex rules per draw.
def EnsurePropTypes()
  for group in LINE_GROUPS + ['SimpleStartifyKey', 'SimpleStartifyMuted']
    if empty(prop_type_get(group))
      # The key marker sits inside the entry span, so it needs to win.
      prop_type_add(group, {
        highlight: group,
        priority: group ==# 'SimpleStartifyKey' ? 10 : 0,
      })
    endif
  endfor
enddef

def PropLines(group: string, lines: list<number>)
  for lnum in lines
    if lnum >= 1 && lnum <= line('$')
      var length = strlen(getline(lnum))
      if length > 0
        prop_add(lnum, 1, {type: group, length: length})
      endif
    endif
  endfor
enddef

def PropSpan(group: string, lnum: number, needle: string)
  var offset = stridx(getline(lnum), needle)
  if offset >= 0
    prop_add(lnum, offset + 1, {type: group, length: strlen(needle)})
  endif
enddef

def ApplyProps(layout: dict<any>, style: string)
  EnsurePropTypes()
  prop_clear(1, line('$'))
  PropLines(get(STYLE_GROUPS, style, 'SimpleStartifyHeader'),
    get(layout, 'header_lines', []))
  PropLines('SimpleStartifySection', get(layout, 'section_lines', []))
  PropLines('SimpleStartifyEntry', get(layout, 'entry_lines', []))
  PropLines('SimpleStartifyFooter', get(layout, 'footer_lines', []))
  # Fit() may have truncated the marker away on a very narrow window, so look
  # for where it actually landed rather than assuming a column.
  for [lnum, action] in items(get(layout, 'actions', {}))
    var key = get(action, 'key', '')
    if type(key) == v:t_string && !empty(key)
      PropSpan('SimpleStartifyKey', str2nr(lnum), '[' .. key .. ']')
    endif
  endfor
  for lnum in range(1, line('$'))
    PropSpan('SimpleStartifyMuted', lnum, MUTED_TEXT)
  endfor
enddef

def HighlightLines(group: string, lines: list<number>)
  for lnum in lines
    if lnum >= 1 && lnum <= line('$')
      execute $'syntax match {group} /\%{lnum}l.*/ contains=SimpleStartifyKey'
    endif
  endfor
enddef

def ApplySyntax(layout: dict<any>, style: string)
  syntax clear
  # "contained" is what the original was missing: an unrestricted whole-line
  # match starts at column 1 and wins Vim's earlier-start priority, so the
  # documented SimpleStartifyKey group could never render.
  syntax match SimpleStartifyKey /\[[0-9A-Za-z]\]/ contained
  execute $'syntax match SimpleStartifyMuted /{MUTED_TEXT}/'
  HighlightLines('SimpleStartifyEntry', get(layout, 'entry_lines', []))
  HighlightLines(get(STYLE_GROUPS, style, 'SimpleStartifyHeader'),
    get(layout, 'header_lines', []))
  HighlightLines('SimpleStartifySection', get(layout, 'section_lines', []))
  HighlightLines('SimpleStartifyFooter', get(layout, 'footer_lines', []))
enddef

def ApplyHighlights(layout: dict<any>, style: string)
  if has('textprop')
    ApplyProps(layout, style)
  else
    ApplySyntax(layout, style)
  endif
enddef

def InstallMappings(actions: dict<any>)
  # Entry shortcuts are data: a session deleted or a style with fewer entries
  # means a letter this buffer used to own is now unclaimed.  Installing the
  # survivors is not enough - the dropped letters stay mapped to a lookup that
  # finds nothing and returns silently, so motions like `e` and `c` become
  # dead keys for the life of the buffer.  Remove exactly the keys we
  # installed, never a plain `mapclear <buffer>`, so a user's own
  # `FileType startify` mapping is left alone.
  for stale in get(b:, 'simplestartify_keys', [])
    silent! execute 'nunmap <buffer> ' .. stale
  endfor
  b:simplestartify_keys = []

  nnoremap <buffer><silent> <CR> <ScriptCmd>simplestartify#Activate()<CR>
  nnoremap <buffer><silent> <2-LeftMouse> <LeftMouse><ScriptCmd>simplestartify#Activate()<CR>
  # Both the vim-startify letters and the fzf/telescope control keys, because
  # muscle memory comes from whichever one the user arrived from.
  nnoremap <buffer><silent> s <ScriptCmd>simplestartify#Activate('split')<CR>
  nnoremap <buffer><silent> <C-x> <ScriptCmd>simplestartify#Activate('split')<CR>
  nnoremap <buffer><silent> v <ScriptCmd>simplestartify#Activate('vsplit')<CR>
  nnoremap <buffer><silent> <C-v> <ScriptCmd>simplestartify#Activate('vsplit')<CR>
  nnoremap <buffer><silent> t <ScriptCmd>simplestartify#Activate('tabedit')<CR>
  nnoremap <buffer><silent> <C-t> <ScriptCmd>simplestartify#Activate('tabedit')<CR>
  nnoremap <buffer><silent> j <ScriptCmd>simplestartify#Move(1)<CR>
  nnoremap <buffer><silent> k <ScriptCmd>simplestartify#Move(-1)<CR>
  nnoremap <buffer><silent> <Tab> <ScriptCmd>simplestartify#Move(1)<CR>
  nnoremap <buffer><silent> <S-Tab> <ScriptCmd>simplestartify#Move(-1)<CR>
  nnoremap <buffer><silent> R <ScriptCmd>simplestartify#Refresh()<CR>
  nnoremap <buffer><silent> d <ScriptCmd>simplestartify#DeleteCurrentSession()<CR>
  nnoremap <buffer><silent> D <ScriptCmd>simplestartify#ForgetRecent()<CR>
  nnoremap <buffer><silent> ? <ScriptCmd>simplestartify#Help()<CR>
  nnoremap <buffer><silent> g? <ScriptCmd>simplestartify#Help()<CR>
  var installed: list<string> = []
  for action in values(actions)
    var key = get(action, 'key', '')
    if type(key) == v:t_string && key =~# '^[0-9A-Za-z]$'
      execute $'nnoremap <buffer><silent> {key} '
            \ .. $'<ScriptCmd>simplestartify#ActivateKey({string(key)})<CR>'
      add(installed, key)
    endif
  endfor
  b:simplestartify_keys = installed
enddef

def Rebuild(): dict<any>
  b:simplestartify_model = Model()
  return b:simplestartify_model
enddef

# Re-render from the cached model.  Everything expensive - stat'ing every
# recent file, globbing and mtime-sorting the session directory - lives in
# Model(); a resize changes none of it, so a resize must not pay for it.
def Layout(style: string, selected_key: string = '')
  var model: dict<any> = get(b:, 'simplestartify_model', {})
  if empty(model)
    model = Rebuild()
  endif
  var width = DashboardWidth()
  # The footer is the one part of the model that depends on the width, so it
  # is resolved here rather than baked into the cache.
  var layout = simplestartify#ui#Build(
    extend(copy(model), {footer: Footer(width)}), style, width)
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
  b:simplestartify_width = width
  b:simplestartify_actions = get(layout, 'actions', {})
  ApplyHighlights(layout, style)
  setlocal nomodifiable
  setlocal nomodified
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

def Render(style: string, selected_key: string = '')
  Rebuild()
  Layout(style, selected_key)
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

# The VimEnter entry point.  A project session takes precedence over the
# dashboard: someone who asked for their workspace back does not want a start
# screen drawn over it first.
export def Start()
  if simplestartify#session#Autoload()
    return
  endif
  AutoOpen()
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
  # Only the deal changed, not the data, so re-lay out the cached model.
  Layout(style, selected)
enddef

export def Relayout()
  if IsDashboard()
    Layout(get(b:, 'simplestartify_style', 'minimal'), CurrentKey())
  endif
enddef

export def Reflow()
  # Two things were wrong with checking the *current* buffer here.  A dashboard
  # resized while focus is elsewhere never re-rendered at all, so its 'nowrap'
  # lines were silently chopped mid-glyph; and entering the dashboard window
  # re-ran Model() - a filereadable() per recent file plus a globbed,
  # mtime-sorted scan of the session directory - even though nothing had
  # changed.  Walk the windows instead, and do the work only when the width
  # actually moved.
  var handled: dict<bool> = {}
  for info in getwininfo()
    var buffer = string(info.bufnr)
    if getbufvar(info.bufnr, 'simplestartify', 0) != 1 || has_key(handled, buffer)
      continue
    endif
    handled[buffer] = true
    if BufferWidth(info.bufnr) == getbufvar(info.bufnr, 'simplestartify_width', -1)
      continue
    endif
    win_execute(info.winid, 'call simplestartify#Relayout()')
  endfor
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

def Verb(requested: string): string
  if has_key(OPEN_VERBS, requested)
    return requested
  endif
  if !empty(requested)
    return 'edit'
  endif
  var configured = get(g:, 'simplestartify_open_action', 'edit')
  return type(configured) == v:t_string && has_key(OPEN_VERBS, configured)
        \ ? configured
        \ : 'edit'
enddef

def OpenFile(path: string, verb: string)
  if !filereadable(path)
    Notify('file is no longer readable: ' .. path, true)
    Refresh()
    return
  endif
  execute OPEN_VERBS[verb].file .. ' ' .. fnameescape(path)
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

def OpenBookmark(path: string, verb: string)
  if empty(path)
    return
  endif
  if filereadable(path)
    OpenFile(path, verb)
    return
  endif
  # A directory bookmark opens the directory (netrw or whatever else handles
  # it), and a bookmark to a file that does not exist yet opens an empty
  # buffer for that name - both are things the user asked to keep, so neither
  # is treated as the "this file went away" error a recent entry would raise.
  execute OPEN_VERBS[verb].file .. ' ' .. fnameescape(path)
enddef

def RunCommand(command: string)
  if empty(command)
    return
  endif
  # A user command is arbitrary code running from inside a mapping: without
  # this, a typo in g:simplestartify_commands aborts the mapping with a raw
  # Vim error stack on the dashboard.
  try
    execute command
  catch
    Notify('command failed: ' .. v:exception, true)
  endtry
enddef

def Run(action: dict<any>, verb: string)
  var kind = get(action, 'kind', '')
  if kind ==# 'file'
    OpenFile(get(action, 'path', ''), verb)
  elseif kind ==# 'bookmark'
    OpenBookmark(get(action, 'path', ''), verb)
  elseif kind ==# 'command'
    RunCommand(get(action, 'command', ''))
  elseif kind ==# 'session'
    simplestartify#session#Load(false, get(action, 'name', ''))
  elseif kind ==# 'new'
    execute OPEN_VERBS[verb].new
  elseif kind ==# 'restyle'
    NextStyle()
  elseif kind ==# 'quit'
    quit
  endif
enddef

export def Activate(requested_verb: string = '')
  if !IsDashboard()
    return
  endif
  var verb = Verb(requested_verb)
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
    Run(action, verb)
  endif
enddef

export def ActivateKey(key: string, requested_verb: string = '')
  if !IsDashboard()
    return
  endif
  var verb = Verb(requested_verb)
  for [lnum, action] in items(get(b:, 'simplestartify_actions', {}))
    if get(action, 'key', '') ==# key
      cursor(str2nr(lnum), 1)
      Run(action, verb)
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

const FIXED_KEYS = [
  ['<CR>', 'open the selected entry'],
  ['s, CTRL-X', 'open it in a split'],
  ['v, CTRL-V', 'open it in a vertical split'],
  ['t, CTRL-T', 'open it in a new tab'],
  ['j, k', 'next / previous entry'],
  ['<Tab>, <S-Tab>', 'next / previous entry'],
  ['r', 'deal another UI style'],
  ['R', 'refresh recent files and sessions'],
  ['d', 'delete the selected session'],
  ['D', 'forget the selected recent file'],
  ['?', 'this list'],
]

const KIND_TITLES = {
  file: 'RECENT FILES',
  session: 'SESSIONS',
  bookmark: 'BOOKMARKS',
  command: 'COMMANDS',
  new: 'ACTIONS',
  restyle: 'ACTIONS',
  quit: 'ACTIONS',
}

# Built from b:simplestartify_actions rather than from a hand-written list, so
# it cannot drift from what the buffer actually has mapped - which matters
# most for the session letters, since those are the keys that change.
export def HelpLines(): list<string>
  var lines: list<string> = ['KEYS']
  for [key, description] in FIXED_KEYS
    add(lines, printf('  %-16s %s', key, description))
  endfor
  var actions = get(b:, 'simplestartify_actions', {})
  var ordered = sort(mapnew(keys(actions), (_, lnum) => str2nr(lnum)), 'n')
  var title = ''
  for lnum in ordered
    var action = actions[string(lnum)]
    var section = get(KIND_TITLES, get(action, 'kind', ''), 'ENTRIES')
    if section !=# title
      title = section
      add(lines, '')
      add(lines, title)
    endif
    var key = get(action, 'key', '')
    # An entry past the end of the shortcut alphabet has no key of its own and
    # is reached with the cursor; say so rather than printing a fake one.
    add(lines, printf('  %-16s %s',
      empty(key) ? '<CR> only' : key, get(action, 'label', '')))
  endfor
  add(lines, '')
  add(lines, 'Entry keys replace the normal-mode command of the same letter')
  add(lines, 'while this buffer is open.')
  return lines
enddef

export def Help()
  if !IsDashboard()
    return
  endif
  var lines = HelpLines()
  if exists('*popup_create')
    popup_create(lines, {
      title: ' SimpleStartify ',
      border: [],
      padding: [0, 1, 0, 1],
      moved: 'any',
      close: 'click',
      maxheight: max([5, &lines - 4]),
    })
    return
  endif
  # No popup support: the command line is the only place left.
  for line in lines
    echomsg line
  endfor
enddef

export def ForgetRecent(requested: string = '')
  var path = requested
  if empty(path)
    if !IsDashboard()
      Notify('name a file to forget, or run this on the dashboard', true)
      return
    endif
    var action = get(get(b:, 'simplestartify_actions', {}), string(line('.')), {})
    if get(action, 'kind', '') !=# 'file'
      Notify('select a recent file first', true)
      return
    endif
    path = get(action, 'path', '')
  endif
  var absolute = fnamemodify(expand(path), ':p')
  if !simplestartify#mru#Forget(absolute)
    Notify('not a recent file: ' .. DisplayPath(absolute), true)
    return
  endif
  Notify('forgotten: ' .. DisplayPath(absolute))
  if IsDashboard()
    Refresh()
  endif
enddef

def Say(report: list<string>, level: string, fact: string, remedy: string = '')
  add(report, $'[{level}] {fact}' .. (empty(remedy) ? '' : ' — ' .. remedy))
enddef

def CheckEnvironment(report: list<string>): bool
  add(report, 'ENVIRONMENT')
  var ok = v:version >= 901
  Say(report, ok ? 'OK' : 'ERROR',
    printf('Vim %d.%d', v:version / 100, v:version % 100),
    ok ? '' : 'SimpleStartify needs Vim 9.1 or newer')
  Say(report, has('textprop') ? 'OK' : 'WARN',
    has('textprop') ? '+textprop' : '-textprop',
    has('textprop') ? '' : 'entry highlighting falls back to syntax matches')
  add(report, '')
  return ok
enddef

def CheckStyles(report: list<string>, styles: list<string>, width: number): bool
  add(report, 'STYLES')
  var configured = ConfiguredStyle()
  var known = configured ==# 'random'
        \ || index(simplestartify#ui#Styles(), configured) >= 0
  # An unknown name is reported once here instead of only as an error message
  # on every single draw, which is where it surfaces today.
  Say(report, known ? 'OK' : 'ERROR', 'g:simplestartify_style = ' .. configured,
    known ? '' : 'not a known style; every draw falls back to random')
  var pool = get(g:, 'simplestartify_styles', simplestartify#ui#Styles())
  Say(report, empty(styles) ? 'ERROR' : 'OK',
    $'eligible at {width} columns: ' .. join(styles, ', '))
  if type(pool) == v:t_list && len(styles) < len(pool)
    Say(report, 'WARN',
      'some configured styles need a wider window than ' .. width,
      'widen the window or drop them from g:simplestartify_styles')
  endif
  add(report, '')
  return known && !empty(styles)
enddef

# "My bookmarks are not showing up" has exactly three causes - the section is
# not in the list, it normalized to nothing, or it is empty and therefore not
# drawn - and none of them is visible from the dashboard itself.
def CheckSections(report: list<string>, result: dict<any>): bool
  add(report, 'SECTIONS')
  var drawn = mapnew(result.sections, (_, section) => section.id)
  for section in result.sections
    var keyless = len(filter(copy(section.entries),
      (_, entry) => empty(get(entry, 'key', ''))))
    Say(report, 'OK', printf('%s: %d entr%s', section.id,
      len(section.entries), len(section.entries) == 1 ? 'y' : 'ies'),
      keyless == 0 ? '' : printf('%d past the end of the shortcut alphabet; '
        .. 'reach them with j/k and <CR>', keyless))
  endfor
  for kind in result.configured
    if index(drawn, kind) < 0
      Say(report, 'WARN', kind .. ': configured but empty',
        'an empty configurable section is not drawn')
    endif
  endfor
  add(report, '')
  return true
enddef

def CheckRecent(report: list<string>, result: dict<any>): bool
  add(report, 'RECENT FILES')
  var ok = true
  Say(report, result.mru_count > 0 || result.oldfiles_count > 0 ? 'OK' : 'WARN',
    printf('%d tracked this session, %d from v:oldfiles',
      result.mru_count, result.oldfiles_count),
    result.mru_count > 0 || result.oldfiles_count > 0
      ? '' : 'open a file and the section fills in immediately')
  # By far the most common "why is this section empty" answer, and the one
  # thing the old health check could not say.
  if exists('+viminfofile') && &viminfofile ==# 'NONE'
    Say(report, 'WARN', "'viminfofile' is NONE",
      'v:oldfiles cannot survive a restart; the in-session record still can')
  elseif &viminfo !~# "'\\d"
    Say(report, 'WARN', "'viminfo' has no ' entry: " .. string(&viminfo),
      'v:oldfiles will stay empty; the in-session record still works')
  endif
  if !result.mru_persist
    Say(report, 'WARN', 'recent-file cache disabled',
      'the list starts empty in every new Vim')
  else
    var directory = fnamemodify(result.mru_file, ':h')
    var writable = isdirectory(directory)
          \ ? filewritable(directory) == 2
          \ : true
    # An unwritable cache directory means the record can never survive a
    # restart, which is a failure and not a remark: it has to reach `ok` the
    # same way the unwritable session directory does.
    ok = writable
    Say(report, writable ? 'OK' : 'ERROR', 'cache: ' .. result.mru_file,
      writable ? '' : 'its directory is not writable')
  endif
  add(report, '')
  return ok
enddef

def CheckSessions(report: list<string>, result: dict<any>): bool
  add(report, 'SESSIONS')
  var directory = result.session_dir
  if empty(directory)
    Say(report, 'ERROR', 'no usable session directory',
      'g:simplestartify_session_dir must be an absolute path below the root')
    add(report, '')
    return false
  endif
  var ok = true
  if !isdirectory(directory)
    Say(report, 'OK', 'directory: ' .. directory,
      'not created yet; the first :SSave creates it with mode 0700')
  elseif !result.session_writable
    ok = false
    Say(report, 'ERROR', 'directory: ' .. directory, 'not writable')
  else
    Say(report, 'OK', printf('directory: %s (%d sessions)',
      directory, result.session_count))
  endif
  if !empty(result.session_leftovers)
    Say(report, 'WARN',
      printf('%d leftover .simplestartify-tmp-* file(s)',
        len(result.session_leftovers)),
      'a save was interrupted; :SimpleStartifyClean removes them')
  endif
  var pointer = simplestartify#session#LastPointerInfo()
  if empty(pointer.type)
    Say(report, 'OK', 'no last-session pointer yet')
  elseif pointer.type !=# 'file'
    ok = false
    Say(report, 'ERROR', 'last-session pointer is a ' .. pointer.type,
      'remove ' .. pointer.path .. '; SimpleStartify refuses to replace it')
  elseif empty(pointer.name)
    Say(report, 'WARN', 'last-session pointer is unreadable or invalid',
      'bare :SLoad! will report that there is no last session')
  elseif !pointer.readable
    Say(report, 'WARN', 'last-session pointer names a missing session: '
      .. pointer.name, 'it will be replaced by the next successful save')
  else
    Say(report, 'OK', 'last session: ' .. pointer.name)
  endif
  var legacy = simplestartify#session#LegacyLastType()
  if !empty(legacy)
    Say(report, 'OK', 'legacy __LAST__ present as a ' .. legacy,
      'used by bare :SLoad! only when the new pointer is unusable')
  endif
  add(report, '')
  return ok
enddef

export def Health(): dict<any>
  var width = DashboardWidth()
  var styles = simplestartify#ui#Candidates(
    get(g:, 'simplestartify_styles', simplestartify#ui#Styles()), width)
  var session_dir = simplestartify#session#Dir()
  var mru_file = simplestartify#mru#File()
  var report: list<string> = []
  var result = {
    styles: styles,
    width: width,
    sections: get(Model(), 'sections', []),
    configured: mapnew(Lists(), (_, spec) => spec.type),
    session_dir: session_dir,
    session_writable: isdirectory(session_dir) && filewritable(session_dir) == 2,
    session_count: len(simplestartify#session#List()),
    session_leftovers: simplestartify#session#TempLeftovers(),
    mru_count: simplestartify#mru#Count(),
    mru_file: mru_file,
    mru_persist: Flag('simplestartify_mru_persist', 1) && !empty(mru_file),
    oldfiles_count: exists('v:oldfiles') ? len(v:oldfiles) : 0,
  }
  # Each check appends its own section and returns whether anything it found
  # was fatal, so `ok` is the conjunction of the ERROR-level facts rather than
  # a hand-maintained expression that quietly ignored writability.
  var ok = CheckEnvironment(report)
  ok = CheckStyles(report, styles, width) && ok
  ok = CheckSections(report, result) && ok
  ok = CheckRecent(report, result) && ok
  ok = CheckSessions(report, result) && ok
  result.ok = ok
  result.report = report
  g:simplestartify_health_last = result
  return result
enddef

export def HealthReport()
  var result = Health()
  var lines = ['SimpleStartify health: ' .. (result.ok ? 'OK' : 'problems found'),
    ''] + result.report
  silent keepalt new
  silent! file [SimpleStartifyHealth]
  setlocal buftype=nofile bufhidden=wipe nobuflisted noswapfile nowrap
  setlocal modifiable
  silent! execute 'keepjumps %delete _'
  setline(1, lines)
  setlocal nomodifiable nomodified
  &l:filetype = 'simplestartifyhealth'
  cursor(1, 1)
enddef

export def CleanSessions()
  var removed = simplestartify#session#CleanTemporaries()
  Notify(removed == 0
    ? 'no leftover session temporaries'
    : printf('removed %d leftover session temporar%s',
        removed, removed == 1 ? 'y' : 'ies'))
enddef
