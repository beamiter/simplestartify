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

# That bound counts accepted paths, which is only the useful half of the work.
# A candidate rejected by filereadable() - a file deleted since it was recorded,
# a checkout that moved, an unmounted drive - paid a fnamemodify, the skiplist
# regexes and a stat, then `continue`d without spending any budget at all, so a
# record full of dead paths was walked to the very end at VimEnter.  That is
# the normal state of a v:oldfiles which has been accumulating for years: 4096
# dead entries measured 13 ms of frozen editor on a warm local disk here, and
# on a network or FUSE home at a millisecond per stat it is seconds.  Rejects
# get a budget of their own, generous enough that a mostly-live record is still
# read to the end and small enough that a mostly-dead one is cheap.
const CANDIDATE_REJECT = 4 * CANDIDATE_SCAN

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
  var rejected = 0
  for candidate in candidates
    if type(candidate) != v:t_string || empty(candidate)
      continue
    endif
    var path = fnamemodify(candidate, ':p')
    # Marked before the verdict, not after it: the two lists overlap heavily -
    # the same file is usually in both - so remembering that a path has been
    # judged means a rejected one is never stat'ed a second time, and that a
    # repeat cannot spend budget a fresh candidate needs.
    if has_key(seen, path)
      continue
    endif
    seen[path] = true
    if simplestartify#mru#Skipped(path) || !filereadable(path)
      rejected += 1
      if rejected >= CANDIDATE_REJECT
        break
      endif
      continue
    endif
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

def ShortRemoteTarget(spec: dict<any>): string
  var name = get(spec, 'name', '')
  if type(name) == v:t_string && !empty(name)
    return name
  endif
  var target = substitute(get(spec, 'target', ''), '^[^@]\+@', '', '')
  return strdisplaywidth(target) > 28
    ? strcharpart(target, 0, 27) .. '…'
    : target
enddef

# The workspace SimpleRemote is connected to, or {}.  The global exists only
# while a connection is ready - it is removed before Disconnected fires - so
# its presence is the whole test, and it is read fresh on every use because a
# dashboard left open in a split outlives any one connection.
def ConnectedWorkspace(): dict<any>
  var workspace = get(g:, 'simpleremote_workspace', {})
  return type(workspace) == v:t_dict ? workspace : {}
enddef

# A specification names the connected workspace when kind and target agree
# and its root does too - or when it has no root of its own, which is what a
# profile without one looks like: whatever root was chosen at the prompt, the
# connection is that profile's.
def IsConnected(spec: dict<any>, workspace: dict<any>): bool
  if empty(workspace)
    return false
  endif
  var root = get(spec, 'root', '')
  return get(spec, 'kind', '') ==# get(workspace, 'kind', '')
        \ && get(spec, 'target', '') ==# get(workspace, 'target', '')
        \ && (empty(root) || root ==# get(workspace, 'root', ''))
enddef

# What SimpleRemote hands out is data from another plugin: a missing function,
# a call that throws, a non-list, a list holding non-dictionaries.  None of
# that may reach the model, so the answer is always a list of copied dicts.
def RemoteProvider(name: string, arguments: list<any>): list<dict<any>>
  var out: list<dict<any>> = []
  if exists('*' .. name) != 1
    return out
  endif
  var value: any = []
  try
    value = call(function(name), arguments)
  catch
    return out
  endtry
  if type(value) != v:t_list
    return out
  endif
  for item in value
    if type(item) == v:t_dict
      add(out, deepcopy(item))
    endif
  endfor
  return out
enddef

# The kind is not restricted to the two SimpleRemote knows today: its own
# providers normalize what they return, so a kind it adds later shows up here
# without an edit, and an unknown one is refused by SimpleRemote at open time
# with its own message rather than hidden silently.
def ValidRemoteSpec(spec: dict<any>, allow_empty_root: bool): bool
  var kind = get(spec, 'kind', '')
  var target = get(spec, 'target', '')
  var root = get(spec, 'root', '')
  if type(kind) != v:t_string || empty(kind)
        \ || type(target) != v:t_string || empty(target)
        \ || type(root) != v:t_string
    return false
  endif
  return root =~# '^/' || (allow_empty_root && empty(root))
enddef

def RemoteId(spec: dict<any>): string
  return join([get(spec, 'kind', ''), get(spec, 'target', ''),
    get(spec, 'root', '')], "\t")
enddef

def RemoteEntry(
    spec: dict<any>,
    letters: list<string>,
    workspace: dict<any>,
    source: string): dict<any>
  var root = get(spec, 'root', '')
  var connected = IsConnected(spec, workspace)
  var label = toupper(get(spec, 'kind', '')) .. '  ' .. ShortRemoteTarget(spec)
  if !empty(root)
    label ..= ' · ' .. root
  endif
  var tags: list<string> = []
  if source ==# 'profile'
    add(tags, 'profile')
  endif
  if connected
    add(tags, 'connected')
  endif
  if !empty(tags)
    label ..= ' (' .. join(tags, ', ') .. ')'
  endif
  return {
    key: TakeKey(letters),
    kind: 'remote',
    label: CleanLabel(label),
    path: root,
    name: get(spec, 'name', ''),
    connected: connected,
    spec: spec,
  }
enddef

# Recent workspaces first, up to the limit, then every configured profile not
# already listed.  The limit is about history: a profile is configuration,
# and configuration is shown the way bookmarks are, whole - a profile that
# vanished because the history happened to be long would be worse than one
# more line.  A profile may have no root; SimpleRemote prompts for one when it
# is opened, so it is kept and its label simply has no root part.
def RemoteEntries(limit: number, letters: list<string>): list<dict<any>>
  var out: list<dict<any>> = []
  var seen: dict<bool> = {}
  var workspace = ConnectedWorkspace()
  if limit > 0
    for spec in RemoteProvider('g:SimpleRemoteRecentWorkspaces', [limit])
      if !ValidRemoteSpec(spec, false) || has_key(seen, RemoteId(spec))
        continue
      endif
      seen[RemoteId(spec)] = true
      add(out, RemoteEntry(spec, letters, workspace, 'recent'))
      if len(out) >= limit
        break
      endif
    endfor
  endif
  for spec in RemoteProvider('g:SimpleRemoteProfiles', [])
    if !ValidRemoteSpec(spec, true) || has_key(seen, RemoteId(spec))
      continue
    endif
    seen[RemoteId(spec)] = true
    add(out, RemoteEntry(spec, letters, workspace, 'profile'))
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

# A remote bookmark is "remote://" followed by an absolute remote path - the
# buffer name SimpleRemote gives a virtual-workspace file - and, optionally,
# the workspace it belongs to.  It is not a local path: expanding it would make
# it one, relative to whatever the working directory happens to be, so it is
# kept as written apart from trailing slashes.  The label follows the remote
# workspace entries so the two read alike, and falls back to the URI when no
# workspace was named.
def RemoteBookmarkEntry(item: dict<any>, target: string, key: string): dict<any>
  var remote = substitute(strpart(target, len('remote://')), '\(.\)/\+$', '\1', '')
  # plugin/ validated this once, but the option can be assigned after startup
  # and the model must not throw over a value it did not vet.
  var configured: any = get(item, 'workspace', {})
  var workspace: dict<any> = type(configured) == v:t_dict
        \ && ValidRemoteSpec(configured, false) ? configured : {}
  var label = empty(workspace)
        \ ? 'remote://' .. remote
        \ : toupper(get(workspace, 'kind', '')) .. '  '
          .. ShortRemoteTarget(workspace) .. ' · ' .. remote
  return {
    key: key,
    kind: 'bookmark',
    label: CleanLabel(label),
    path: 'remote://' .. remote,
    remote: remote,
    workspace: deepcopy(workspace),
  }
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
    var pinned = get(item, 'key', '')
    var key = type(pinned) == v:t_string && !empty(pinned) ? pinned : TakeKey(letters)
    # Any remote:// target, not only a well-formed remote:///absolute one: a
    # malformed URI is SimpleRemote's to refuse when the bookmark is opened,
    # and expanding it into a local path under the working directory - which
    # is what the branch below would do - is never what was meant.
    if target =~# '^remote://'
      add(out, RemoteBookmarkEntry(item, target, key))
      continue
    endif
    # A bookmark is shown whether or not the target exists yet: it is a place
    # the user asked to keep, and opening a missing one creates the buffer.
    var path = substitute(fnamemodify(expand(target), ':p'), '[\\/]\+$', '', '')
    add(out, {
      key: key,
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
    return '<CR> open  s/v/t split  / filter  r restyle  R refresh  ? keys'
  elseif width >= 26
    return '<CR> open  / filter  ? keys'
  endif
  return '?'
enddef

# The query goes in the footer, not only on the command line: the command line
# is gone the moment anything else echoes, and a dashboard showing a subset of
# its entries with no visible reason is a confusing place to be.
def FilterFooter(query: string, width: number): string
  var shown = 'filter: ' .. query
  if width >= 48
    return shown .. '   <CR> open  <BS> erase  <Esc> clear'
  endif
  return shown
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
  remote: {title: 'remote workspaces', short: 'remote', command: 'remote recent'},
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

const FALLBACK_LISTS = [
  {type: 'remote'}, {type: 'files'}, {type: 'sessions'}, {type: 'special'},
]

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

# A dynamic header cannot be a Funcref: Vim refuses to store one in a global
# whose name does not start with a capital (E704), so an option named
# g:simplestartify_custom_header can never hold one.  A string that looks like
# a function call is therefore evaluated per draw, and any other string is a
# literal line - "MY DASHBOARD" is not a call and cannot be mistaken for one.
const CALL_EXPRESSION = '^\%(\a\|_\)[[:alnum:]_#.:]*(.*)$'

def CustomLines(name: string): list<string>
  var value: any = get(g:, name, [])
  if type(value) == v:t_string
    if value !~# CALL_EXPRESSION
      return [CleanLabel(value)]
    endif
    try
      value = eval(value)
    catch
      # A broken user expression degrades to the layout's built-in banner
      # rather than taking the dashboard down with it.
      Notify($'g:{name} failed: {v:exception}', true)
      return []
    endtry
    if type(value) == v:t_string
      return [CleanLabel(value)]
    endif
  endif
  if type(value) != v:t_list
    return []
  endif
  return mapnew(filter(copy(value), (_, line) => type(line) == v:t_string),
    (_, line) => CleanLabel(line))
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
  # Not capped at the nine digits any more: entries past the alphabet render
  # without a marker and are reached with the cursor or the filter.
  var remote_limit = Count('simplestartify_remote_count', 3, 12)
  var recent_limit = Count('simplestartify_recent_count', 7, CANDIDATE_SCAN)
  var session_limit = Count('simplestartify_session_count', 4, len(SESSION_KEYS))

  var sections: list<dict<any>> = []
  for spec in specs
    var kind: string = spec.type
    var entries: list<dict<any>> = []
    if kind ==# 'remote'
      entries = RemoteEntries(SectionLimit(spec, remote_limit), letters)
    elseif kind ==# 'files'
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
    # Everything configured is shown by default: a pinned entry that silently
    # vanished once the list outgrew the shortcut alphabet would be worse than
    # one drawn without a marker, which is now a state entries can be in.
    elseif kind ==# 'bookmarks'
      entries = BookmarkEntries(SectionLimit(spec, CANDIDATE_SCAN), letters)
    elseif kind ==# 'commands'
      entries = CommandEntries(SectionLimit(spec, CANDIDATE_SCAN), letters)
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
    header: CustomLines('simplestartify_custom_header'),
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
  b:simplestartify_query = ''
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
  # Searching a generated scratch buffer is not a thing anyone wants to do, so
  # "/" is worth more as the filter, the way mini.starter and telescope use it.
  nnoremap <buffer><silent> / <ScriptCmd>simplestartify#Filter()<CR>
  nnoremap <buffer><silent> <C-f> <ScriptCmd>simplestartify#Filter()<CR>
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
# The filter prompt always wins the footer: while a query is active it is the
# only thing down there worth the columns, and a custom footer would otherwise
# hide the reason half the dashboard disappeared.
def FooterLines(query: string, width: number): list<string>
  if !empty(query)
    return [FilterFooter(query, width)]
  endif
  var custom = CustomLines('simplestartify_custom_footer')
  return empty(custom) ? [Footer(width)] : custom
enddef

def Matches(entry: dict<any>, needle: string): bool
  # Substring, over everything the entry is addressed by: what a user types is
  # a piece of the name they can see, or a piece of the path behind it.
  var haystack = tolower(join([get(entry, 'label', ''), get(entry, 'path', ''),
    get(entry, 'name', ''), get(entry, 'command', '')], ' '))
  return stridx(haystack, tolower(needle)) >= 0
enddef

# Filtering is a pure transform of the cached model, so narrowing costs one
# pass over a list already in memory - no stat, no glob - which is what makes
# it usable on every keystroke.
def Filtered(model: dict<any>, query: string): dict<any>
  if empty(query)
    return model
  endif
  var sections: list<dict<any>> = []
  for section in get(model, 'sections', [])
    var entries = filter(copy(get(section, 'entries', [])),
      (_, entry) => Matches(entry, query))
    # A section with no match disappears entirely while filtering: "(none
    # yet)" is an answer about the section, not about the query.
    if !empty(entries)
      add(sections, extend(copy(section), {entries: entries}))
    endif
  endfor
  return extend(copy(model), {sections: sections})
enddef

def Layout(style: string, selected_key: string = '')
  var model: dict<any> = get(b:, 'simplestartify_model', {})
  if empty(model)
    model = Rebuild()
  endif
  var width = DashboardWidth()
  var query = get(b:, 'simplestartify_query', '')
  # The footer is the one part of the model that depends on the width, so it
  # is resolved here rather than baked into the cache.
  var layout = simplestartify#ui#Build(
    extend(Filtered(model, query), {footer: FooterLines(query, width)}),
    style, width)
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

# Command modifiers that say *where* a window goes.  <mods> also carries
# things the dashboard must not inherit - `noautocmd` would suppress the
# FileType event its highlighting rides on, `silent` would swallow the
# messages Open() uses to explain a refusal - so the placement words are kept
# and everything else is dropped rather than passed through blind.
const PLACEMENT_MODS = ['aboveleft', 'belowright', 'botright', 'horizontal',
  'leftabove', 'rightbelow', 'tab', 'topleft', 'vertical']

def Placement(mods: string): string
  return join(filter(split(mods, '\s\+'),
    (_, word) => index(PLACEMENT_MODS, word) >= 0))
enddef

export def Open(requested: string = '', mods: string = '')
  # A placement modifier asks for a *new* window, so the current buffer is not
  # about to be abandoned and there is nothing to refuse - and an explicit
  # `:vertical SimpleStartify` from inside the dashboard means a second one,
  # not a redraw of the first.
  var placement = Placement(mods)
  if empty(placement) && &modified && !&hidden && !IsDashboard()
    Notify('save the current buffer before opening the dashboard', true)
    return
  endif
  if !empty(placement)
    var origin = bufnr()
    try
      execute placement .. ' new'
    catch
      # E36: no room left to split.  Say so instead of leaving the user with a
      # command that appeared to do nothing.
      Notify('cannot open a window there: ' .. v:exception, true)
      return
    endtry
    ConfigureBuffer(origin)
  elseif !IsDashboard()
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
# screen drawn over it first.  A file named on the command line outranks both,
# and for the session that is not a matter of taste: loading one goes through
# DeleteListedBuffers(), so an unguarded autoload would `bdelete!` the very
# buffer `vim README.md` asked for.  It is the rule AutoOpen() already applies.
export def Start()
  if argc() == 0 && simplestartify#session#Autoload()
    return
  endif
  AutoOpen()
enddef

# "This window holds nothing the user would miss."  Shared by the startup path
# and the reopen-on-empty path so the two can never drift apart on what counts
# as a window worth drawing over.
def Vacant(): bool
  return !&insertmode
        \ && &modifiable
        \ && !&modified
        \ && &buftype ==# ''
        \ && empty(bufname())
        \ && line('$') == 1
        \ && getline(1) ==# ''
enddef

export def AutoOpen()
  if !Flag('simplestartify_auto_open', 1) || argc() != 0 || !Vacant()
    return
  endif
  Open()
enddef

# Closing your last file drops you on a blank [No Name] buffer, which is the
# one place the dashboard is unambiguously more useful than what Vim leaves
# behind.  Opt-in, because it is a real change in what :bd does.
export def ReopenIfEmpty()
  if !Flag('simplestartify_reopen_on_empty', 0) || IsDashboard() || !Vacant()
    return
  endif
  # A listed buffer with a name is a file the user still has open somewhere,
  # even if it is not on screen; only the truly empty Vim gets the dashboard.
  for info in getbufinfo({buflisted: 1})
    if !empty(info.name)
      return
    endif
  endfor
  Open()
enddef

# BufDelete fires while the buffer is still being taken apart, and opening a
# buffer from inside that is how plugins corrupt window state.  Hand the work
# to the main loop instead; a Vim without +timers simply does not get this.
export def ScheduleReopen()
  if !Flag('simplestartify_reopen_on_empty', 0) || !exists('*timer_start')
    return
  endif
  timer_start(0, (_) => ReopenIfEmpty())
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

# Redraw every visible dashboard, and open none.  This is what a SimpleRemote
# connection change calls: the remote section marks the connected workspace
# and the connection may come or go while a dashboard sits in a split, but a
# user who has no dashboard on screen did not ask for one, which is exactly
# what Refresh() would give them.
export def RefreshIfDashboard()
  var handled: dict<bool> = {}
  for info in getwininfo()
    var buffer = string(info.bufnr)
    # The 'filetype' is part of what a dashboard is, and it is what Refresh()
    # checks before opening one: a window holding the marker without it would
    # otherwise be answered with a brand-new dashboard.
    if getbufvar(info.bufnr, 'simplestartify', 0) != 1
          || getbufvar(info.bufnr, '&filetype') !=# 'startify'
          || has_key(handled, buffer)
      continue
    endif
    handled[buffer] = true
    win_execute(info.winid, 'call simplestartify#Refresh()')
  endfor
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

# One keystroke of filter mode, kept apart from the loop below so the state
# machine can be driven directly - by a test, or by any other input source -
# without a blocking read.  Returns whether filtering continues.
export def FilterKey(char: string): bool
  if !IsDashboard() || empty(char)
    return false
  endif
  var query = get(b:, 'simplestartify_query', '')
  if char ==# "\<Esc>" || char ==# "\<C-c>"
    b:simplestartify_query = ''
    Relayout()
    return false
  endif
  if char ==# "\<CR>" || char ==# "\<NL>"
    # Filter mode ends here whatever the entry turns out to do.  The query is
    # cleared first - not after, and not by Relayout alone - because an entry
    # that leaves the dashboard on screen (a command, a restyle, a session
    # load refused by the modified-buffer check) would otherwise strand it
    # narrowed to one line, with a footer offering <BS> and <Esc> that no
    # longer read anything, and Refresh() re-reads the query so even R could
    # not undo it.  Activate() still sees the filtered actions, so it opens
    # what was on screen; the re-layout happens afterwards, and only if the
    # dashboard is still the current buffer.
    b:simplestartify_query = ''
    Activate()
    Relayout()
    return false
  endif
  if char ==# "\<BS>" || char ==# "\<C-h>" || char2nr(char) == 127
    b:simplestartify_query = strcharpart(query, 0, max([0, strchars(query) - 1]))
  elseif strchars(char) == 1 && char2nr(char) >= 32
    b:simplestartify_query = query .. char
  else
    # An unhandled key is ignored rather than ending the filter: a stray
    # arrow key should not throw away what has been typed.
    return true
  endif
  Relayout()
  return true
enddef

# Nine digits was a hard ceiling on how many recent files could be reached at
# all.  Typing narrows the model instead, so the tenth file is one character
# away rather than unreachable.
export def Filter()
  if !IsDashboard()
    return
  endif
  b:simplestartify_query = ''
  Relayout()
  while true
    echohl ModeMsg
    echo '/' .. get(b:, 'simplestartify_query', '')
    echohl None
    var char = ''
    try
      char = getcharstr()
    catch /^Vim:Interrupt$/
      char = "\<Esc>"
    endtry
    if !FilterKey(char)
      break
    endif
  endwhile
  echo ''
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
  # Both of these are a window-local :lcd, which is why the project-session
  # hook is registered for the "global" DirChanged scope only: this cd is the
  # tail of opening the file above, not the user entering a project, and
  # loading a Session.vim here would delete the buffer just opened.
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

# Leaving Vim with unsaved work is E37, a raw error thrown out of a mapping on
# a screen whose whole job is to be friendly.  Name the buffers instead.
def QuitVim(all: bool)
  var modified = simplestartify#session#ModifiedBuffers()
  if !empty(modified)
    Notify(printf('modified buffers would be lost; save them or use :%s!: %s',
      all ? 'qall' : 'quit', join(modified, ', ')), true)
    return
  endif
  execute all ? 'qall' : 'quit'
enddef

def Quit()
  var action = get(g:, 'simplestartify_quit_action', 'auto')
  if type(action) != v:t_string
    action = 'auto'
  endif
  # A dashboard in a split is a window the user opened next to their work, so
  # "quit" there means that window - closing the whole editor because the
  # start screen happened to be focused is not what the entry offers.
  var split = winnr('$') > 1 || tabpagenr('$') > 1
  if action ==# 'qall'
    QuitVim(true)
  elseif action ==# 'close' || (action ==# 'auto' && split)
    if split
      close
    else
      QuitVim(false)
    endif
  else
    QuitVim(false)
  endif
enddef

# Leave the dashboard the way the verb says - the same enew/new/vnew/tabnew a
# "new buffer" entry uses - so a workspace can be started in a split or a tab
# rather than always over the dashboard.  Both branches do it before calling
# into SimpleRemote, whose tree opens beside the current window.
def OpenRemoteWorkspace(action: dict<any>, verb: string)
  var spec = get(action, 'spec', {})
  # The model said "connected" when it was built; the connection may be gone
  # by the time the key is pressed, so ask again rather than trusting a label.
  if get(action, 'connected', false)
        \ && IsConnected(spec, ConnectedWorkspace())
        \ && exists('*g:SimpleRemoteTreeSetRoot') == 1
    # Already there: re-root the workspace tree at the workspace and show it,
    # instead of tearing the connection down to build the same one again.
    var root = get(ConnectedWorkspace(), 'root', get(spec, 'root', ''))
    try
      execute 'silent keepalt ' .. OPEN_VERBS[verb].new
      call(function('g:SimpleRemoteTreeSetRoot'), [root])
      if exists(':SimpleRemoteWorkspace') == 2
        execute 'SimpleRemoteWorkspace'
      endif
    catch
      Notify('remote workspace failed: ' .. v:exception, true)
    endtry
    return
  endif
  if exists('*g:SimpleRemoteOpenWorkspace') != 1
    Notify('SimpleRemote is not available', true)
    return
  endif
  var Opener = function('g:SimpleRemoteOpenWorkspace')
  try
    execute 'silent keepalt ' .. OPEN_VERBS[verb].new
    call(Opener, [deepcopy(spec)])
  catch
    Notify('remote workspace failed: ' .. v:exception, true)
  endtry
enddef

# Open a remote path in the connected workspace: the local projection when
# the workspace has one (an sshfs or bind mount, so the buffer is the same
# file the tree would open), the remote:// buffer otherwise.  {winid} is the
# window the user was in when the connection was asked for; if it is gone the
# current one serves.
def EditRemotePath(remote: string, verb: string, winid: number = 0)
  if winid > 0 && win_id2win(winid) > 0
    win_gotoid(winid)
  endif
  var target = 'remote://' .. remote
  if exists('*g:SimpleRemoteLocalPath') == 1
    var local: any = ''
    try
      local = call(function('g:SimpleRemoteLocalPath'), [remote])
    catch
      local = ''
    endtry
    if type(local) == v:t_string && !empty(local)
      target = local
    endif
  endif
  try
    execute OPEN_VERBS[verb].file .. ' ' .. fnameescape(target)
  catch
    Notify('cannot open ' .. target .. ': ' .. v:exception, true)
  endtry
enddef

# The remote bookmark whose workspace is being connected for it, if any.
# One at a time is the whole design: a second remote bookmark activated
# before the first connection is ready replaces it, exactly as the second
# connection replaces the first.
var pending_bookmark: dict<any> = {}

def OpenRemoteBookmark(action: dict<any>, verb: string)
  var remote = get(action, 'remote', '')
  var workspace = get(action, 'workspace', {})
  var connected = ConnectedWorkspace()
  if !empty(connected) && (empty(workspace) || IsConnected(workspace, connected))
    EditRemotePath(remote, verb)
    return
  endif
  if empty(workspace)
    Notify('connect a SimpleRemote workspace first: remote://' .. remote, true)
    return
  endif
  if exists('*g:SimpleRemoteOpenWorkspace') != 1
    Notify('SimpleRemote is not available', true)
    return
  endif
  # Connect first; the file is opened once SimpleRemote says the workspace is
  # ready.  The verb is spent now, on leaving the dashboard, and the file
  # then goes into that window - a split asked for is a split delivered even
  # though the edit itself happens later.
  try
    execute 'silent keepalt ' .. OPEN_VERBS[verb].new
  catch
    Notify('cannot open a window there: ' .. v:exception, true)
    return
  endtry
  pending_bookmark = {remote: remote, workspace: deepcopy(workspace),
    winid: win_getid()}
  augroup SimpleStartifyRemoteBookmark
    autocmd!
    autocmd User SimpleRemoteConnected ++once call simplestartify#OpenPendingRemoteBookmark()
  augroup END
  try
    call(function('g:SimpleRemoteOpenWorkspace'), [deepcopy(workspace)])
  catch
    pending_bookmark = {}
    autocmd! SimpleStartifyRemoteBookmark
    Notify('remote workspace failed: ' .. v:exception, true)
  endtry
enddef

# Runs on the SimpleRemoteConnected that follows a remote bookmark.  The
# connection that arrived has to be the one asked for: a connect that failed
# leaves the one-shot autocmd armed, and the next workspace the user opens by
# hand must not have a stranger's file opened into it.  The edit is deferred
# past the autocmd, because a BufReadCmd - which is what actually fetches a
# remote:// buffer - does not fire from inside another autocmd.
export def OpenPendingRemoteBookmark()
  var pending = pending_bookmark
  pending_bookmark = {}
  if empty(pending) || !IsConnected(pending.workspace, ConnectedWorkspace())
    return
  endif
  timer_start(0, (_) => EditRemotePath(pending.remote, 'edit', pending.winid))
enddef

def Run(action: dict<any>, verb: string)
  var kind = get(action, 'kind', '')
  if kind ==# 'remote'
    OpenRemoteWorkspace(action, verb)
  elseif kind ==# 'file'
    OpenFile(get(action, 'path', ''), verb)
  elseif kind ==# 'bookmark' && has_key(action, 'remote')
    OpenRemoteBookmark(action, verb)
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
    Quit()
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
  ['/, CTRL-F', 'filter entries as you type'],
  ['j, k', 'next / previous entry'],
  ['<Tab>, <S-Tab>', 'next / previous entry'],
  ['r', 'deal another UI style'],
  ['R', 'refresh recent files and sessions'],
  ['d', 'delete the selected session'],
  ['D', 'forget the selected recent file'],
  ['?', 'this list'],
]

const KIND_TITLES = {
  remote: 'REMOTE WORKSPACES',
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
    # The remote section is empty whenever SimpleRemote is not installed or
    # has nothing to list yet, which is the normal state and not a warning;
    # CheckRemote says which it is.
    if index(drawn, kind) < 0 && kind !=# 'remote'
      Say(report, 'WARN', kind .. ': configured but empty',
        'an empty configurable section is not drawn')
    endif
  endfor
  add(report, '')
  return true
enddef

# Whether SimpleRemote is there at all, and what it is connected to: the two
# facts behind "why is there no remote section" and "why is nothing marked
# connected", neither of which the dashboard can show.
def CheckRemote(report: list<string>, result: dict<any>): bool
  add(report, 'REMOTE WORKSPACES')
  if !result.remote_installed
    Say(report, 'OK', 'SimpleRemote is not installed',
      'the remote section is left out and remote bookmarks cannot connect')
    add(report, '')
    return true
  endif
  Say(report, 'OK', 'SimpleRemote status: ' .. result.remote_status)
  var drawn = 0
  for section in result.sections
    if section.id ==# 'remote'
      drawn = len(section.entries)
    endif
  endfor
  if index(result.configured, 'remote') < 0
    Say(report, 'OK', 'remote section not in g:simplestartify_lists')
  elseif drawn == 0
    Say(report, 'OK', 'remote: no recent workspaces or profiles yet',
      'the section appears after the first connection, or with '
      .. 'g:simpleremote_profiles')
  endif
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

def RemoteStatus(): string
  var status = get(g:, 'simpleremote_status', 'disconnected')
  return type(status) == v:t_string && !empty(status) ? status : 'disconnected'
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
    remote_installed: exists('*g:SimpleRemoteRecentWorkspaces') == 1
      || exists('*g:SimpleRemoteProfiles') == 1,
    remote_status: RemoteStatus(),
  }
  # Each check appends its own section and returns whether anything it found
  # was fatal, so `ok` is the conjunction of the ERROR-level facts rather than
  # a hand-maintained expression that quietly ignored writability.
  var ok = CheckEnvironment(report)
  ok = CheckStyles(report, styles, width) && ok
  ok = CheckSections(report, result) && ok
  ok = CheckRemote(report, result) && ok
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
