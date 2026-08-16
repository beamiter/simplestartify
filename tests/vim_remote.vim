vim9script

# The SimpleRemote integration, exercised without SimpleRemote: every call the
# dashboard makes into it is feature-detected, so the whole surface is driven
# here through stub g:SimpleRemote* functions and by firing its User events by
# hand.  The first block runs before any stub exists, because a Vim without
# SimpleRemote is the common case and must be silent about it.

set nocompatible
set nomore
set hidden

const ROOT = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
const TEMP = tempname()
mkdir(TEMP .. '/sessions', 'p')
mkdir(TEMP .. '/mount', 'p')
const LOCAL = TEMP .. '/local.txt'
const MOUNTED = TEMP .. '/mount/README.md'
writefile(['local'], LOCAL)
writefile(['mounted'], MOUNTED)

execute 'set runtimepath^=' .. fnameescape(ROOT)
g:simplestartify_auto_open = 0
g:simplestartify_session_dir = TEMP .. '/sessions'
g:simplestartify_mru_persist = 0
g:simplestartify_lists = [{type: 'remote'}, {type: 'bookmarks'}, {type: 'special'}]
g:simplestartify_bookmarks = [
  {path: 'remote:///srv/app/README.md', key: 'w',
    workspace: {kind: 'ssh', target: 'devbox', root: '/srv/app', name: 'dev'}},
  {path: 'remote:///srv/other/notes.md/'},
  # A workspace without an absolute root cannot be reconnected, so it is
  # dropped at normalization while the bookmark itself is kept.
  {path: 'remote:///srv/app/x', workspace: {kind: 'ssh', target: 'devbox'}},
  # The explicit form is not only for remote paths.
  {path: LOCAL, key: 'l'},
  # A remote URI that is not "remote://" plus an absolute path is still a
  # remote URI: SimpleRemote refuses it when it is opened, and it is never
  # turned into a path under the working directory.
  'remote://relative',
  # A dictionary carrying anything besides path/key/workspace is
  # vim-startify's {key: path} pair form, whose keys may be named anything -
  # including "path".
  {'m': '/srv/pair-one', 'path': '/srv/pair-two'},
]
execute 'source ' .. fnameescape(ROOT .. '/plugin/simplestartify.vim')

def Ids(): list<string>
  return mapnew(get(b:, 'simplestartify_model', {sections: []}).sections,
    (_, section) => section.id)
enddef

def Section(id: string): dict<any>
  for section in get(b:, 'simplestartify_model', {sections: []}).sections
    if section.id ==# id
      return section
    endif
  endfor
  return {}
enddef

def Labels(id: string): list<string>
  return mapnew(get(Section(id), 'entries', []), (_, entry) => entry.label)
enddef

def Keys(id: string): list<string>
  return mapnew(get(Section(id), 'entries', []), (_, entry) => entry.key)
enddef

def KeyFor(id: string, label: string): string
  for entry in get(Section(id), 'entries', [])
    if entry.label ==# label
      return entry.key
    endif
  endfor
  return ''
enddef

def Screen(): string
  return join(getline(1, '$'), "\n")
enddef

# The labels another buffer's model marks as connected.  A dashboard in a
# split is too narrow to read the marker off the screen, and the model is
# what the marker is drawn from.
def ConnectedLabels(buffer: number): list<string>
  var model: any = getbufvar(buffer, 'simplestartify_model', {})
  if type(model) != v:t_dict
    return []
  endif
  var out: list<string> = []
  for section in get(model, 'sections', [])
    for entry in get(section, 'entries', [])
      if get(entry, 'connected', false)
        add(out, entry.label)
      endif
    endfor
  endfor
  return out
enddef

def Report(): string
  return join(simplestartify#Health().report, "\n")
enddef

def WaitFor(Condition: func(): bool, limit: number = 200): bool
  var waited = 0
  while !Condition() && waited < limit
    sleep 10m
    waited += 1
  endwhile
  return Condition()
enddef

def DashboardWindows(): number
  return len(filter(getwininfo(),
    (_, info) => getbufvar(info.bufnr, 'simplestartify', 0) == 1))
enddef

# Normalization: the explicit bookmark form keeps its workspace only when the
# workspace can be reconnected, and SimpleRemote's session provider is the
# default without anyone configuring it.
assert_equal([
  {key: 'w', path: 'remote:///srv/app/README.md',
    workspace: {kind: 'ssh', target: 'devbox', root: '/srv/app', name: 'dev'}},
  {key: '', path: 'remote:///srv/other/notes.md/'},
  {key: '', path: 'remote:///srv/app/x'},
  {key: 'l', path: LOCAL},
  {key: '', path: 'remote://relative'},
], g:simplestartify_bookmarks[0 : 4])
# The pair form yields one bookmark per member, in whatever order the
# dictionary hands them over.
var pairs = filter(copy(g:simplestartify_bookmarks),
  (_, item) => item.path =~# '^/srv/pair-')
assert_equal(['/srv/pair-one', '/srv/pair-two'],
  sort(mapnew(pairs, (_, item) => item.path)))
assert_equal(['', 'm'], sort(mapnew(pairs, (_, item) => item.key)))
assert_equal(['g:SimpleRemoteSessionLines'], g:simplestartify_session_line_providers)

# Without SimpleRemote: no remote section, no complaint about it - the health
# check says the plugin is missing instead of warning that a default section
# is empty - and a remote bookmark explains why it cannot open.
SimpleStartify minimal
assert_equal(['bookmarks', 'special'], Ids())
var health = simplestartify#Health()
assert_false(health.remote_installed)
assert_notmatch('remote: configured but empty', Report())
assert_match('REMOTE WORKSPACES', Report())
assert_match('\[OK\].*SimpleRemote is not installed', Report())
assert_equal([
  'SSH  dev · /srv/app/README.md',
  'remote:///srv/other/notes.md',
  'remote:///srv/app/x',
  fnamemodify(LOCAL, ':~'),
  'remote://relative',
], Labels('bookmarks')[0 : 4])
assert_equal(['/srv/pair-one', '/srv/pair-two'],
  sort(Labels('bookmarks')[5 : ]))
var noise = execute('call simplestartify#ActivateKey("w")')
assert_match('SimpleRemote is not available', noise)
assert_equal('startify', &filetype)
noise = execute('call simplestartify#ActivateKey("'
  .. KeyFor('bookmarks', 'remote:///srv/other/notes.md') .. '")')
assert_match('connect a SimpleRemote workspace first', noise)
assert_equal('startify', &filetype)
# The explicit form opens a local path like any other bookmark.
simplestartify#ActivateKey('l')
assert_equal(LOCAL, expand('%:p'))

# --- SimpleRemote stubs -----------------------------------------------------
g:remote_calls = []
g:remote_opened = []
g:remote_roots = []
g:remote_tree_opens = []
g:remote_local_paths = {}
g:remote_session_lines = []
g:remote_recent = [
  {name: '', kind: 'ssh', target: 'me@devbox.example.com', root: '/srv/app',
    local_root: ''},
  {name: 'api', kind: 'docker', target: 'api-container', root: '/workspace/api',
    local_root: ''},
  {kind: 'ssh', target: 'user@a-very-long-host-name-that-goes-on-forever.example.org',
    root: '/home/u'},
  {kind: 'ssh', target: '', root: '/x'},
  {kind: 'ssh', target: 'h', root: 'relative'},
  'garbage',
  {kind: '', target: 'h', root: '/x'},
  {kind: 'ssh', target: 'fourth', root: '/four'},
]
g:remote_profiles = [
  {name: 'devbox', kind: 'ssh', target: 'me@devbox.example.com', root: '/srv/app',
    local_root: '', source: 'profile'},
  {name: 'staging', kind: 'ssh', target: 'staging.example.com', root: '',
    local_root: '', source: 'profile'},
  {name: 'db', kind: 'docker', target: 'db', root: '/var/lib/db', source: 'profile'},
  {name: 'bad', kind: 'ssh', target: 'x', root: 'nope', source: 'profile'},
]

def g:SimpleRemoteRecentWorkspaces(limit: number = -1): list<any>
  add(g:remote_calls, limit)
  # Deliberately ignores the limit, so the dashboard's own cap is exercised.
  return deepcopy(g:remote_recent)
enddef
def g:SimpleRemoteProfiles(): list<dict<any>>
  return deepcopy(g:remote_profiles)
enddef
def g:SimpleRemoteOpenWorkspace(workspace: dict<any>)
  add(g:remote_opened, workspace)
enddef
def g:SimpleRemoteTreeSetRoot(path: string): bool
  add(g:remote_roots, path)
  return true
enddef
command! -nargs=? SimpleRemoteWorkspace call add(g:remote_tree_opens, <q-args>)
def g:SimpleRemoteLocalPath(remote: string): string
  return get(g:remote_local_paths, remote, '')
enddef
def g:SimpleRemoteSessionLines(): list<string>
  return copy(g:remote_session_lines)
enddef

# The section: recent history first, then the configured profiles that are
# not already there.  Labels prefer a profile name, strip user@, truncate a
# long host, and drop the root part for a profile that has none; every
# malformed item is skipped without a word; the fourth recent entry is beyond
# the count even though the provider returned it.
g:simplestartify_remote_count = 3
SimpleStartify minimal
assert_equal(['remote', 'bookmarks', 'special'], Ids())
assert_equal([
  'SSH  devbox.example.com · /srv/app',
  'DOCKER  api · /workspace/api',
  'SSH  a-very-long-host-name-that-… · /home/u',
  'SSH  staging (profile)',
  'DOCKER  db · /var/lib/db (profile)',
], Labels('remote'))
assert_equal(3, g:remote_calls[-1])
# Letters come from the shared pool, minus the keys pinned to bookmarks.
assert_equal(['a', 'b', 'c', 'e', 'f'], Keys('remote'))
assert_equal(['w', 'g', 'h', 'l', 'i'], Keys('bookmarks')[0 : 4])
assert_match('REMOTE WORKSPACES', Screen())
assert_match('REMOTE WORKSPACES', join(simplestartify#HelpLines(), "\n"))
# The whole specification travels with the entry: a profile keeps its source,
# which is what lets SimpleRemote accept its empty root.
assert_equal('profile', Section('remote').entries[3].spec.source)
assert_false(Section('remote').entries[0].connected)

# A per-section limit caps the history, and a zero count hides the history
# without touching the profiles - they are configuration, not history.
g:simplestartify_lists = [{type: 'remote', limit: 1}, {type: 'special'}]
SimpleStartifyRefresh
assert_equal(['SSH  devbox.example.com · /srv/app', 'SSH  staging (profile)',
  'DOCKER  db · /var/lib/db (profile)'], Labels('remote'))
assert_equal(1, g:remote_calls[-1])
var calls = len(g:remote_calls)
g:simplestartify_lists = [{type: 'remote'}, {type: 'special'}]
g:simplestartify_remote_count = 0
SimpleStartifyRefresh
# Nothing was asked of the history, so the profile that shadows its first
# entry is no longer a duplicate of anything and is listed like the rest.
assert_equal(['SSH  devbox · /srv/app (profile)', 'SSH  staging (profile)',
  'DOCKER  db · /var/lib/db (profile)'], Labels('remote'))
assert_equal(calls, len(g:remote_calls))
g:simplestartify_remote_count = 3
g:simplestartify_lists = [{type: 'remote'}, {type: 'bookmarks'}, {type: 'special'}]

# Health with SimpleRemote present: the status is stated, and an empty section
# is explained rather than warned about.
var recent_before = g:remote_recent
var profiles_before = g:remote_profiles
g:remote_recent = []
g:remote_profiles = []
health = simplestartify#Health()
assert_true(health.remote_installed)
assert_equal('disconnected', health.remote_status)
assert_match('\[OK\].*SimpleRemote status: disconnected', Report())
assert_match('\[OK\].*remote: no recent workspaces or profiles yet', Report())
assert_notmatch('\[WARN\].*remote', Report())
g:simpleremote_status = 'ssh:devbox'
assert_match('SimpleRemote status: ssh:devbox', Report())
unlet g:simpleremote_status
# A deck without the section at all is a choice, not a fault.
var lists_before = g:simplestartify_lists
g:simplestartify_lists = [{type: 'special'}]
assert_match('remote section not in g:simplestartify_lists', Report())
g:simplestartify_lists = lists_before
g:remote_recent = recent_before
g:remote_profiles = profiles_before

# Selecting a workspace hands SimpleRemote a copy of the specification and
# leaves the dashboard; the verb decides where.
SimpleStartify minimal
simplestartify#ActivateKey('a')
assert_equal(1, len(g:remote_opened))
assert_equal('ssh', g:remote_opened[0].kind)
assert_equal('me@devbox.example.com', g:remote_opened[0].target)
assert_equal('/srv/app', g:remote_opened[0].root)
assert_notequal('startify', &filetype)
assert_equal('', bufname())
SimpleStartify minimal
simplestartify#ActivateKey('e')
assert_equal('profile', g:remote_opened[-1].source)
assert_equal('', g:remote_opened[-1].root)

SimpleStartify minimal
var windows = winnr('$')
simplestartify#ActivateKey('b', 'split')
assert_equal(windows + 1, winnr('$'))
assert_equal('docker', g:remote_opened[-1].kind)
assert_equal(1, DashboardWindows())
close
assert_equal('startify', &filetype)
var tabs = tabpagenr('$')
simplestartify#ActivateKey('b', 'tabedit')
assert_equal(tabs + 1, tabpagenr('$'))
assert_notequal('startify', &filetype)
tabclose
assert_equal('startify', &filetype)

# The connected workspace is marked, and selecting it does not reconnect: the
# tree is re-rooted at the workspace and shown.
g:simpleremote_workspace = {id: 1, kind: 'ssh', target: 'me@devbox.example.com',
  root: '/srv/app', mode: 'virtual', local_root: ''}
SimpleStartify minimal
assert_equal('SSH  devbox.example.com · /srv/app (connected)', Labels('remote')[0])
assert_true(Section('remote').entries[0].connected)
assert_false(Section('remote').entries[1].connected)
var opened = len(g:remote_opened)
simplestartify#ActivateKey('a')
assert_equal(opened, len(g:remote_opened))
assert_equal(['/srv/app'], g:remote_roots)
assert_equal([''], g:remote_tree_opens)
assert_notequal('startify', &filetype)
# A profile without a root is that connection whatever root was chosen.
g:simpleremote_workspace = {id: 2, kind: 'ssh', target: 'staging.example.com',
  root: '/opt/stage', mode: 'virtual', local_root: ''}
SimpleStartify minimal
assert_equal('SSH  staging (profile, connected)', Labels('remote')[3])
simplestartify#ActivateKey('e')
assert_equal(opened, len(g:remote_opened))
assert_equal(['/srv/app', '/opt/stage'], g:remote_roots)
# The label was true when drawn; the key is pressed after the connection went
# away, so the entry connects again rather than re-rooting nothing.
SimpleStartify minimal
assert_true(Section('remote').entries[3].connected)
unlet g:simpleremote_workspace
simplestartify#ActivateKey('e')
assert_equal(opened + 1, len(g:remote_opened))
assert_equal(2, len(g:remote_roots))

# Connection events redraw a dashboard that is on screen and open none when
# there is not one.
enew!
vertical SimpleStartify minimal
var dashboard = bufnr()
assert_equal(1, DashboardWindows())
wincmd p
assert_notequal(dashboard, bufnr())
assert_equal([], ConnectedLabels(dashboard))
g:simpleremote_workspace = {id: 3, kind: 'docker', target: 'api-container',
  root: '/workspace/api', mode: 'virtual', local_root: ''}
g:simpleremote_event = {event: 'SimpleRemoteConnected', status: 'docker:api-container'}
doautocmd <nomodeline> User SimpleRemoteConnected
assert_equal(['DOCKER  api · /workspace/api (connected)'],
  ConnectedLabels(dashboard))
assert_notequal(dashboard, bufnr())
unlet g:simpleremote_workspace
g:simpleremote_event = {event: 'SimpleRemoteDisconnected', reason: 'disconnect'}
doautocmd <nomodeline> User SimpleRemoteDisconnected
assert_equal([], ConnectedLabels(dashboard))
execute 'bwipeout! ' .. dashboard
assert_equal(0, DashboardWindows())
doautocmd <nomodeline> User SimpleRemoteConnected
assert_equal(0, DashboardWindows())
assert_notequal('startify', &filetype)

# A remote bookmark with a workspace connects first and opens the file once
# SimpleRemote reports that connection.
SimpleStartify minimal
opened = len(g:remote_opened)
simplestartify#ActivateKey('w')
assert_equal(opened + 1, len(g:remote_opened))
assert_equal({kind: 'ssh', target: 'devbox', root: '/srv/app', name: 'dev'},
  g:remote_opened[-1])
assert_notequal('startify', &filetype)
assert_equal('', bufname())
g:simpleremote_workspace = {id: 4, kind: 'ssh', target: 'devbox', root: '/srv/app',
  mode: 'virtual', local_root: ''}
g:simpleremote_event = {event: 'SimpleRemoteConnected', status: 'ssh:devbox'}
doautocmd <nomodeline> User SimpleRemoteConnected
assert_true(WaitFor(() => bufname() ==# 'remote:///srv/app/README.md'), bufname())
# The wait is spent: a later connection opens nothing more.
enew!
doautocmd <nomodeline> User SimpleRemoteConnected
sleep 50m
assert_equal('', bufname())
# A connection to somewhere else - the asked-for one failed and the user
# moved on - must not have the bookmark opened into it, and it ends the wait
# rather than leaving a file to appear in a workspace nobody asked it for.
unlet g:simpleremote_workspace
SimpleStartify minimal
opened = len(g:remote_opened)
simplestartify#ActivateKey('w')
assert_equal(opened + 1, len(g:remote_opened))
assert_equal('', bufname())
g:simpleremote_workspace = {id: 5, kind: 'ssh', target: 'elsewhere',
  root: '/srv/app', mode: 'virtual', local_root: ''}
doautocmd <nomodeline> User SimpleRemoteConnected
sleep 50m
assert_equal('', bufname())
# Even the workspace it was waiting for opens nothing now: the wait ended
# with the connection that was not it.
g:simpleremote_workspace = {id: 6, kind: 'ssh', target: 'devbox', root: '/srv/app',
  mode: 'virtual', local_root: ''}
doautocmd <nomodeline> User SimpleRemoteConnected
sleep 50m
assert_equal('', bufname())

# Already connected to that workspace: the file opens at once, through the
# local projection when the workspace has one.
SimpleStartify minimal
opened = len(g:remote_opened)
simplestartify#ActivateKey('w')
assert_equal(opened, len(g:remote_opened))
assert_equal('remote:///srv/app/README.md', bufname())
g:remote_local_paths = {'/srv/app/README.md': MOUNTED}
SimpleStartify minimal
simplestartify#ActivateKey('w')
assert_equal(MOUNTED, expand('%:p'))
g:remote_local_paths = {}
# A bookmark without a workspace opens in whatever workspace is connected, its
# trailing slash gone.
SimpleStartify minimal
simplestartify#ActivateKey(KeyFor('bookmarks', 'remote:///srv/other/notes.md'))
assert_equal('remote:///srv/other/notes.md', bufname())
# Connected somewhere else, with a workspace of its own: reconnect first.
g:simpleremote_workspace = {id: 7, kind: 'docker', target: 'db', root: '/var/lib/db',
  mode: 'virtual', local_root: ''}
SimpleStartify minimal
opened = len(g:remote_opened)
simplestartify#ActivateKey('w')
assert_equal(opened + 1, len(g:remote_opened))
assert_equal('devbox', g:remote_opened[-1].target)
unlet g:simpleremote_workspace

# A SimpleRemote too old to have the profile function: the section is drawn
# from the history alone, and nothing reports a missing function.
delfunction g:SimpleRemoteProfiles
SimpleStartify minimal
assert_equal([
  'SSH  devbox.example.com · /srv/app',
  'DOCKER  api · /workspace/api',
  'SSH  a-very-long-host-name-that-… · /home/u',
], Labels('remote'))
assert_true(simplestartify#Health().remote_installed)

# Session line providers: SimpleRemote's lines land in the session file and
# source back; a provider that throws, one that returns something other than
# a list and one that does not exist cost a message each and never the save.
g:remote_session_lines = ['let g:remote_session_marker = 42']
g:simplestartify_session_savevars = ['g:remote_saved_var']
g:simplestartify_session_savecmds = ['echo "after the rest"']
g:remote_saved_var = 'kept'
execute 'edit! ' .. fnameescape(LOCAL)
assert_true(simplestartify#session#Save(true, 'remote'))
var written = join(readfile(TEMP .. '/sessions/remote'), "\n")
assert_match('let g:remote_session_marker = 42', written)
# Variables, then the providers, then the user's own commands: a savecmd can
# rely on everything the two lists before it restored.
var session_lines = readfile(TEMP .. '/sessions/remote')
var at_var = index(session_lines, "let g:remote_saved_var = 'kept'")
var at_provided = index(session_lines, 'let g:remote_session_marker = 42')
var at_command = index(session_lines, 'echo "after the rest"')
assert_true(at_var >= 0 && at_provided > at_var && at_command > at_provided,
  string([at_var, at_provided, at_command]))
g:simplestartify_session_savevars = []
g:simplestartify_session_savecmds = []
def g:ThrowingProvider(): list<string>
  throw 'provider refused'
enddef
def g:ListlessProvider(): string
  return 'not a list'
enddef
g:simplestartify_session_line_providers = ['g:ThrowingProvider', 'g:ListlessProvider',
  'g:NoSuchProvider', 'g:SimpleRemoteSessionLines']
noise = execute('call simplestartify#session#Save(true, "remote")')
assert_match('session line provider g:ThrowingProvider failed', noise)
assert_match('session line provider g:ListlessProvider did not return a list', noise)
assert_notmatch('g:NoSuchProvider', noise)
assert_match('session saved: remote', noise)
written = join(readfile(TEMP .. '/sessions/remote'), "\n")
assert_match('let g:remote_session_marker = 42', written)
assert_notmatch('not a list', written)
g:simplestartify_session_line_providers = ['g:SimpleRemoteSessionLines']
# A provider without SimpleRemote's lines - it returns [] when disconnected -
# adds nothing.
g:remote_session_lines = []
assert_true(simplestartify#session#Save(true, 'plain'))
assert_notmatch('remote_session_marker', join(readfile(TEMP .. '/sessions/plain'), "\n"))

# Loading brings the marker back, and the post-load events fire after the
# load is final: a hook that throws is reported, not turned into a rollback.
g:hooks = []
augroup RemoteSessionHooks
  autocmd!
  autocmd User SimpleStartifySessionLoaded add(g:hooks, 'loaded')
  autocmd User SimpleStartifySessionLoadPost add(g:hooks, 'post') | throw 'hook broke'
augroup END
unlet! g:remote_session_marker
noise = execute('call simplestartify#session#Load(false, "remote")')
assert_equal(42, get(g:, 'remote_session_marker', 0))
assert_equal(TEMP .. '/sessions/remote', v:this_session)
assert_equal(['loaded', 'post'], g:hooks)
assert_match('session load hook failed', noise)
assert_notmatch('session load failed', noise)
# A load that fails is rolled back and fires neither event.
g:hooks = []
writefile(["throw 'broken session'"], TEMP .. '/sessions/broken')
assert_false(simplestartify#session#Load(false, 'broken'))
assert_equal([], g:hooks)
autocmd! RemoteSessionHooks

v:this_session = ''
delete(TEMP, 'rf')
if !empty(v:errors)
  writefile(v:errors, '/dev/stderr')
  cquit 1
endif
qall!
