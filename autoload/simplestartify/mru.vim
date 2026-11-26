vim9script

# Vim fills v:oldfiles once, from viminfo, while it starts up and never
# touches it again.  A dashboard reopened mid-session - which :SClose does on
# purpose - would therefore list only files from *previous* sessions, and a
# Vim run with `-i NONE`, `set viminfo=`, a fresh container image or simply a
# first-ever launch would list nothing at all, forever.  So the plugin keeps
# its own recent-files record: this file is that record.
#
# The store is a list of {path, time, seq} newest-first.  `time` is wall clock
# because it has to survive a restart and merge sensibly with what a *sibling*
# Vim instance wrote; `seq` is an in-process counter that breaks ties inside
# the same second, which wall time alone cannot do.

var entries: list<dict<any>> = []
var sequence = 0
var disk_marks: dict<dict<any>> = {}
var effective_marks: dict<dict<any>> = {}
var order_stamp = -1
var order_ok = true
var saving = false
var loaded = false
var active_file = ''

# Only outstanding local actions may change the shared cache. Entries read from
# disk are an observation, not a source of writes: if a sibling removed a path,
# carrying over the previous snapshot would silently resurrect it on exit.
# Keep the latest operation per path; compare its action time, not flush time.
var changes: dict<dict<any>> = {}
# Cap-zero opens still clear a sibling's matching Forget if seen at save.
# Keep only a short bounded window for opens not known to be revivals yet.
const ZERO_VISIT_WINDOW = 32
var zero_visits: list<string> = []

# A session-local filter over Vim's fallback history. Do not edit v:oldfiles:
# it is shared with other Vim commands/plugins, and writing it cannot remove a
# mark from viminfo on restart. Remember all successful Forgets in case native
# history is reloaded later. A real visit restores the path without changing it.
var hidden_oldfiles: dict<bool> = {}

# The cache used to be written in exactly one place, at VimLeavePre.  Anything
# that ends Vim without running it - SIGKILL, the OOM killer, `pkill vim`, a
# container torn down, a battery that runs out - therefore threw away the whole
# session's record, which is precisely what this file exists to keep when
# viminfo cannot.  Store() re-reads, merges, sorts and rewrites the entire
# file, so it is far too heavy to run per BufWinEnter; instead the first change
# after a clean state arms a one-shot timer and every change inside that window
# rides along with it.  Staleness is bounded by the delay however busy the
# session is, an idle Vim arms nothing at all, and a Vim that never opens a
# file never pays for any of it.
const FLUSH_DELAY = 5000
var dirty = false
var pending = 0

# The cache's modification time as of the last read, or -1 for "read it again".
# Sync() uses it to notice a sibling Vim's write, and the guard has to be a
# stat rather than an unconditional re-read: parsing and re-sorting the file
# costs 1 ms at the default cap and 18 ms at the maximum - the sort calls a
# script-level comparator per comparison - which is far too much to spend on
# every draw for a file that has usually not changed.
var disk_stamp = -1
var disk_path = ''
var disk_maximum = -1

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

# plugin/ normalizes g:simplestartify_mru_max into 0..5000 and the read in
# FromDisk() has to agree with it.  It did not: the cache was read 4096 lines
# at a time, so a configured 4097..5000 was not merely unreachable but lossy -
# Store() rewrites whatever FromDisk() managed to read, so the tail past 4096
# was destroyed on the way out.  One limit, in one place, and the read below
# takes it from here.  The ceiling is repeated rather than read from plugin/
# because a value assigned after startup never passes through it, and an
# unbounded read of a corrupt or hand-written file is not something a cache
# should attempt.
const CEILING = 5000
# Marks are never evicted: a viminfo copy or a delayed legacy writer may
# still have a forgotten path. Stop admitting more durable marks at the cap.
const MARK_LIMIT = 5000
const ORDER_HEADER = 'SimpleStartify MRU order 1'
const ORDERED = exists('*sha256') && exists('*reltimefloat')

def MarkKey(path: string): string
  return ORDERED ? sha256(path) : path
enddef
const ORDER_MAX_BYTES = 64 * 1024 * 1024

def Action(path: string, forget: bool): dict<any>
  sequence += 1
  # reltime() provides the finer, shared host clock on supported platforms.
  # The wall-clock second comes first so the record still orders across boots.
  var wall = localtime()
  var tick = exists('*reltimefloat') ? float2nr(reltimefloat(reltime()) * 1000000.0) : 0
  return {path: path, time: wall, tick: tick, pid: getpid(), seq: sequence,
    forget: forget, keep: !forget && Maximum() > 0}
enddef

def Maximum(): number
  var value = get(g:, 'simplestartify_mru_max', 200)
  return type(value) == v:t_number ? min([CEILING, max([0, value])]) : 200
enddef

export def File(): string
  var value = get(g:, 'simplestartify_mru_file', '')
  if type(value) != v:t_string || empty(value)
    return ''
  endif
  return fnamemodify(value, ':p')
enddef

# Treat a new absolute cache path as a new history. A timer armed under
# one path cannot flush its pending visits or Forgets under another, even
# when a relative setting only changed meaning after a directory change.
def EnsureScope()
  var path = File()
  # :p adds a slash for an existing directory. A failed write because the
  # existing cache temporarily is a directory is not a new user scope.
  if len(path) > 1 && path !~# '^[A-Za-z]:[\\/]$'
    path = substitute(path, has('win32') ? '[\\/]\+$' : '/\+$', '', '')
  endif
  if path ==# active_file
    return
  endif
  if pending != 0
    timer_stop(pending)
    pending = 0
  endif
  active_file = path
  entries = []
  changes = {}
  zero_visits = []
  hidden_oldfiles = {}
  dirty = false
  loaded = false
  sequence = 0
  disk_stamp = -1
  order_stamp = -1
  order_ok = true
  disk_marks = {}
  effective_marks = {}
enddef

def Persisting(): bool
  return Flag('simplestartify_mru_persist', 1) && !empty(File())
enddef

def CompareAction(left: dict<any>, right: dict<any>): number
  if left.time != right.time
    return left.time > right.time ? -1 : 1
  endif
  if left.tick != right.tick
    return left.tick > right.tick ? -1 : 1
  endif
  if left.pid != right.pid
    return left.pid > right.pid ? -1 : 1
  endif
  if left.seq != right.seq
    return left.seq > right.seq ? -1 : 1
  endif
  return 0
enddef

def Newest(left: dict<any>, right: dict<any>): number
  var order = CompareAction(left, right)
  return order != 0 ? order : (left.path ==# right.path ? 0 : (left.path <# right.path ? -1 : 1))
enddef

def Capped(items: list<dict<any>>): list<dict<any>>
  # The cap counts kept paths, and plugin/ normalizes it into 0..5000, so 0 is
  # a configured value meaning "keep none".  Treating it as "no cap" inverted
  # the smallest request into an unbounded one: neither `entries` nor the cache
  # written at VimLeavePre would ever be truncated again.
  var maximum = Maximum()
  if maximum <= 0
    return []
  endif
  return len(items) > maximum ? items[0 : maximum - 1] : items
enddef

def LegacyRows(): list<dict<any>>
  var out: list<dict<any>> = []
  var path = File()
  disk_path = path
  disk_maximum = Maximum()
  disk_stamp = -1
  if !Persisting() || !filereadable(path)
    return out
  endif
  # Stamped before the read, never after: a sibling Vim that replaces the file
  # between the two would otherwise leave us holding its new timestamp and the
  # old contents.  And a stamp from the current second is not remembered at
  # all, for the same reason session.vim does not remember one: file times have
  # one-second resolution, so a write later in this same second would leave the
  # stored value equal and go unnoticed.
  var stamp = getftime(path)
  # One entry per line as "<epoch><TAB><absolute path>".  A line that does not
  # parse is dropped rather than fatal: this is a cache, not a database, and a
  # truncated or hand-edited file must never break the dashboard.
  #
  # Exactly Maximum() lines: fewer silently truncates a cache the user asked
  # for and loses its tail at the next write, more would be read only to be
  # thrown away by Capped().  readfile() reads nothing at a {max} of zero,
  # which is what a cap of zero - "keep none" - asks for anyway.
  for line in readfile(path, '', disk_maximum)
    var tab = stridx(line, "\t")
    if tab <= 0
      continue
    endif
    var when = str2nr(strpart(line, 0, tab))
    var candidate = strpart(line, tab + 1)
    if when <= 0 || empty(candidate) || candidate !~# '^\%(/\|[A-Za-z]:[\\/]\)'
      continue
    endif
    # Preserve persisted order within the same second. A new local touch in
    # that second still outranks all prior records.
    add(out, {path: candidate, time: when, tick: 0, pid: 0, seq: -len(out), forget: false, keep: true})
  endfor
  disk_stamp = stamp < localtime() ? stamp : -1
  return out
enddef

# Preserve the original cache as a compatibility projection. The sidecar
# survives an older Vim rewriting that cache; its ordered rows can restore a
# genuine re-open, and its tombstones hide stale native history as well.
def FromDisk(): list<dict<any>>
  var rows = LegacyRows()
  order_stamp = -1
  order_ok = true
  disk_marks = {}
  if !Persisting() || !ORDERED
    order_stamp = -2
    return rows
  endif
  var sidecar = active_file .. '.order'
  var kind = getftype(sidecar)
  if empty(kind)
    order_stamp = -2
    return rows
  endif
  if kind !=# 'file' || getfsize(sidecar) > ORDER_MAX_BYTES
    order_ok = false
    return rows
  endif
  var stamp = getftime(sidecar)
  var lines = readfile(sidecar, '', 2 + CEILING + MARK_LIMIT)
  if empty(lines) || lines[0] !=# ORDER_HEADER || len(lines) > 1 + CEILING + MARK_LIMIT
    order_ok = false
    return rows
  endif
  var saved: list<dict<any>> = []
  var restored_marks: dict<dict<any>> = {}
  for line in lines[1 :]
    var fields = split(line, "\t", true)
    if len(fields) != 6 || fields[0] !~# '^[RBF]$'
        || fields[1] !~# '^\d\+$' || fields[2] !~# '^\d\+$'
        || fields[3] !~# '^\d\+$' || fields[4] !~# '^-\?\d\+$'
        || (fields[0] ==# 'R' ? fields[5] !~# '^\%(/\|[A-Za-z]:[\\/]\)'
          : fields[5] !~# '^[0-9a-f]\{64}$')
      order_ok = false
      return rows
    endif
    var op = {path: fields[0] ==# 'R' ? fields[5] : '', time: str2nr(fields[1]), tick: str2nr(fields[2]),
      pid: str2nr(fields[3]), seq: str2nr(fields[4]), forget: fields[0] ==# 'F',
      keep: fields[0] ==# 'R'}
    if op.time <= 0 || (fields[0] !=# 'R' && has_key(restored_marks, fields[5]))
      order_ok = false
      return rows
    endif
    if fields[0] ==# 'R'
      add(saved, op)
    else
      restored_marks[fields[5]] = op
    endif
  endfor
  if len(saved) > CEILING || len(restored_marks) > MARK_LIMIT
    order_ok = false
    return rows
  endif
  order_stamp = stamp < localtime() ? stamp : -1
  disk_marks = restored_marks
  # The ordered rows can recover entries erased by a delayed older writer.
  # Import unrelated legacy visits as well; they have no precise action time.
  return saved + rows
enddef

def OrderCurrent(): bool
  var sidecar = active_file .. '.order'
  return !ORDERED || (order_stamp == -2 ? empty(getftype(sidecar))
    : order_stamp >= 0 && getftime(sidecar) == order_stamp)
enddef

def Encode(op: dict<any>, kind: string, key: string): string
  return join([kind, op.time, op.tick, op.pid, op.seq, key], "\t")
enddef

# Most refreshes have no local changes, and a single file visit is a common
# flush. A plugin-written cache is already in order except for that one key.
# Check the remaining rows before relying on the ordering: hand-edited rows and
# duplicate keys can otherwise leave a winner at the wrong position.
def OrderMerged(merged: list<dict<any>>)
  if len(changes) > 1
    sort(merged, Newest)
    return
  endif
  var changed = empty(changes) ? '' : keys(changes)[0]
  var moved = -1
  var previous = -1
  for i in range(len(merged))
    var current = merged[i]
    if current.path ==# changed
      moved = i
      continue
    endif
    if previous >= 0 && Newest(merged[previous], current) > 0
      sort(merged, Newest)
      return
    endif
    previous = i
  endfor
  if moved < 0
    return
  endif
  var entry = remove(merged, moved)
  var left = 0
  var right = len(merged)
  while left < right
    var mid = (left + right) / 2
    if Newest(merged[mid], entry) < 0
      left = mid + 1
    else
      right = mid
    endif
  endwhile
  insert(merged, entry, left)
enddef

def ApplyChanges(disk: list<dict<any>>)
  var index: dict<number> = {}
  var merged: list<dict<any>> = []
  effective_marks = copy(disk_marks)
  for op in values(changes)
    var key = MarkKey(op.path)
    if op.forget || has_key(disk_marks, key)
      var old = get(effective_marks, key, {})
      if empty(old) || CompareAction(op, old) < 0
        effective_marks[key] = op
      endif
    endif
  endfor
  # A recent recorded visit can predate the *write* of a competing Forget
  # even when it followed the user's action. Recover that ordering from its
  # sidecar timestamp rather than requiring the visit to have seen a mark.
  if !empty(effective_marks)
    for entry in disk
      if !entry.forget && entry.pid != 0
        var key = MarkKey(entry.path)
        if has_key(effective_marks, key) && CompareAction(entry, effective_marks[key]) < 0
          effective_marks[key] = entry
        endif
      endif
    endfor
  endif
  for entry in disk + values(changes)
    var mark = empty(effective_marks) ? {} : get(effective_marks, MarkKey(entry.path), {})
    # An older Vim's rows carry no action order and cannot clear a mark or
    # revive a row evicted by the cap. Its unrelated visits still import.
    if entry.forget || !entry.keep || (!empty(mark)
        && (mark.forget || entry.pid == 0 || CompareAction(entry, mark) > 0))
      continue
    endif
    if has_key(index, entry.path)
      var known = merged[index[entry.path]]
      if Newest(entry, known) < 0
        merged[index[entry.path]] = entry
      endif
      continue
    endif
    index[entry.path] = len(merged)
    add(merged, entry)
  endfor
  OrderMerged(merged)
  entries = Capped(merged)
enddef

# Reading the file is deferred until something actually needs the list, so a
# Vim that never opens the dashboard pays nothing for this feature at startup.
export def Load()
  EnsureScope()
  if loaded
    return
  endif
  loaded = true
  ApplyChanges(FromDisk())
enddef

# Read updates from a sibling when drawing, but do not resubmit an old copy
# of the cache. The file plus still-pending local actions is the whole view.
def Sync()
  EnsureScope()
  if !loaded
    Load()
    return
  endif
  var path = File()
  if !Persisting() || (path ==# disk_path && Maximum() == disk_maximum
        && disk_stamp >= 0 && getftime(path) == disk_stamp && OrderCurrent())
    return
  endif
  ApplyChanges(FromDisk())
enddef

# Arm the flush window.  Deliberately not re-armed while one is already open:
# restarting the timer on every recorded file would let a busy session put the
# write off indefinitely, which is the failure this whole mechanism exists to
# prevent.  A Vim without +timers, or one that cannot allocate another, keeps
# exactly the VimLeavePre write it always had - a cache is never worth an error
# in the user's face.
def Arm()
  if pending != 0 || !Persisting() || !exists('*timer_start')
    return
  endif
  var armed = 0
  try
    armed = timer_start(FLUSH_DELAY, (_) => Flush())
  catch
    armed = -1
  endtry
  # timer_start() answers -1 rather than throwing when it cannot allocate one,
  # and inside a |sandbox| it does throw.  Either way the id must not be kept:
  # a negative one in `pending` reads as "a window is already open" and would
  # stop this Vim from ever arming a real one again.
  pending = armed > 0 ? armed : 0
enddef

# Exported because the dashboard has to apply the same rule to v:oldfiles and
# to entries recorded before the option was set: one implementation, one
# answer, whichever side of the record the path arrived from.
export def Skipped(path: string): bool
  var patterns = get(g:, 'simplestartify_skiplist', [])
  if type(patterns) != v:t_list
    return false
  endif
  # plugin/ drops unparsable patterns at startup, but nothing stops a user
  # assigning the variable afterwards, and a throw here would fire at every
  # BufWinEnter.  A broken pattern must cost the filter, never the editor.
  for pattern in patterns
    try
      if type(pattern) == v:t_string && !empty(pattern) && path =~# pattern
        return true
      endif
    catch
      # Ignore this invalid rule, not the valid exclusions that follow it.
    endtry
  endfor
  return false
enddef

def Skip(path: string): bool
  if empty(path) || path =~# '[\t\r\n]'
    return true
  endif
  # Session files are the plugin's own bookkeeping; loading one must not make
  # it look like a recently edited document.
  var directory = simplestartify#session#Dir()
  if !empty(directory) && fnamemodify(path, ':h') ==# directory
    return true
  endif
  return Skipped(path)
enddef

def Find(path: string): number
  # This runs at every BufWinEnter and every BufWritePost - so at every
  # quickfix jump - and it used to be index(mapnew(entries, ...)), which builds
  # a throwaway copy of every path in the record just to look at one of them.
  # A plain scan reads the same dicts without allocating anything and is three
  # to seven times quicker at a raised cap; a {path -> index} dict beside
  # `entries` would be quicker still in theory and is not worth it in practice,
  # because every insert and every Capped() shifts the indexes it stores.
  var position = 0
  for entry in entries
    if entry.path ==# path
      return position
    endif
    position += 1
  endfor
  return -1
enddef

def Record(path: string)
  Load()
  if has_key(hidden_oldfiles, path)
    remove(hidden_oldfiles, path)
  endif
  var key = empty(effective_marks) ? '' : MarkKey(path)
  var preserving_mark = has_key(effective_marks, key) ||
    (has_key(changes, path) && changes[path].forget)
  var found = Find(path)
  if found >= 0
    remove(entries, found)
  endif
  var entry = Action(path, false)
  if preserving_mark
    effective_marks[empty(key) ? MarkKey(path) : key] = entry
  endif
  insert(entries, entry, 0)
  changes[path] = entry
  # A rapid sequence of visits must not queue more additions than can fit.
  # Keep Forget operations until a successful write, never infer them from
  # an entry merely falling below this session's limit.
  var maximum = Maximum()
  while len(entries) > maximum
    var evicted = remove(entries, -1).path
    if has_key(changes, evicted) && !changes[evicted].forget
      if has_key(effective_marks, MarkKey(evicted))
        changes[evicted].keep = false
      elseif maximum == 0 && evicted ==# path && Persisting()
        var previous = index(zero_visits, path)
        if previous >= 0
          remove(zero_visits, previous)
        endif
        add(zero_visits, path)
        changes[path].keep = false
        if len(zero_visits) > ZERO_VISIT_WINDOW
          var oldest = remove(zero_visits, 0)
          if has_key(changes, oldest) && !changes[oldest].forget && !changes[oldest].keep
              && !has_key(effective_marks, MarkKey(oldest))
            remove(changes, oldest)
          endif
        endif
      else
        remove(changes, evicted)
      endif
    endif
  endwhile
  dirty = true
  Arm()
enddef

export def Touch()
  # Only real, listed, on-disk files: scratch buffers, help, quickfix,
  # terminals and the dashboard itself all carry a non-empty 'buftype', and an
  # unwritten new file is not something anyone means by "recent".
  if &buftype !=# '' || !&buflisted || &previewwindow
    return
  endif
  var path = expand('%:p')
  if Skip(path) || !filereadable(path)
    return
  endif
  Record(path)
enddef

export def HiddenOldfile(path: string): bool
  var mark = empty(effective_marks) ? {} : get(effective_marks, MarkKey(path), {})
  return !empty(mark) ? mark.forget : has_key(hidden_oldfiles, path)
enddef

def HasVisibleOldfile(path: string): bool
  if HiddenOldfile(path) || !exists('v:oldfiles') || type(v:oldfiles) != v:t_list
    return false
  endif
  for oldfile in v:oldfiles
    if type(oldfile) == v:t_string && !empty(oldfile) && fnamemodify(oldfile, ':p') ==# path
      return true
    endif
  endfor
  return false
enddef

export def Forget(requested: string): bool
  # Sync() rather than Load(): a path that only a sibling Vim has recorded is
  # still a path the user can see on the dashboard and ask to forget. Track
  # the request until it is written, not for the whole remaining Vim process.
  Sync()
  if empty(requested)
    return false
  endif
  # No expand() on a file name, for the same reason ForgetRecent() does not
  # use one: it is a wildcard, environment-variable, %/#-special and backtick
  # expander, so a recorded file called `lit$HOME.txt` resolved to a path that
  # is in no record and stayed on the dashboard forever, and one whose name
  # contains backticks ran the enclosed text through the shell.  Record() and
  # Touch() store what expand('%:p') gave them, verbatim; fnamemodify(':p')
  # resolves '~' and relative names and matches that.
  var path = fnamemodify(requested, ':p')
  var dropped = Find(path) >= 0
  var oldfile = HasVisibleOldfile(path)
  # Only a forget that actually removed something leaves a tombstone, so a
  # mistyped path stays the no-op it reports itself to be.
  if dropped || oldfile
    var key = MarkKey(path)
    if Persisting() && ORDERED && !has_key(effective_marks, key) && len(effective_marks) >= MARK_LIMIT
      return false
    endif
    filter(entries, (_, entry) => entry.path !=# path)
    hidden_oldfiles[path] = true
    var op = Action(path, true)
    changes[path] = op
    effective_marks[key] = op
    dirty = true
    Arm()
  endif
  return oldfile || dropped
enddef

export def List(): list<string>
  Sync()
  return mapnew(entries, (_, entry) => entry.path)
enddef

export def Count(): number
  Sync()
  return len(entries)
enddef

def Store(): bool
  var path = active_file
  var directory = fnamemodify(path, ':h')
  if !isdirectory(directory)
    # Another writer may have created the directory after the check.
    try
      mkdir(directory, 'p', 0o700)
    catch /^Vim\%((\a\+)\)\=:E739:/
      if !isdirectory(directory)
        return false
      endif
    endtry
  endif
  var lock = path .. '.order.lock'
  # Only a timer or exit save acquires the lock, never a file-open hook.
  # Give a concurrent writer a short window, but never steal its lock.
  var locked = false
  for attempt in range(26)
    if empty(getftype(lock))
      try
        locked = mkdir(lock, '', 0o700) == 1
      catch /^Vim\%((\a\+)\)\=:E739:/
        # Another process won the mkdir race; try again.
      endtry
      if locked
        break
      endif
    endif
    if attempt < 25
      sleep 10m
    endif
  endfor
  if !locked
    return false
  endif
  try
    EnsureScope()
    if path !=# active_file
      return false
    endif
    ApplyChanges(FromDisk())
    var legacy_kind = getftype(path)
    if !order_ok || (!empty(legacy_kind) && legacy_kind !=# 'file')
        || len(effective_marks) > MARK_LIMIT
      return false
    endif
    if empty(entries) && empty(effective_marks) && empty(legacy_kind)
      return true
    endif
    var lines = [ORDER_HEADER]
    extend(lines, mapnew(entries, (_, entry) => Encode(entry, 'R', entry.path)))
    for [key, mark] in items(effective_marks)
      add(lines, Encode(mark, mark.forget ? 'F' : 'B', key))
    endfor
    # Publish the authoritative state first. If updating the old projection
    # fails, retry without losing the operation or clobbering an invalid path.
    if (ORDERED && !simplestartify#atomic#Replace(lines, path .. '.order'))
        || !simplestartify#atomic#Replace(mapnew(entries, (_, entry) => entry.time .. "\t" .. entry.path), path)
      return false
    endif
    disk_stamp = -1
    order_stamp = -1
  finally
    delete(lock, 'd')
  endtry
  return true
enddef

# This runs at VimLeavePre, ahead of the session hook, and from the flush
# timer.  A cache is never worth aborting a quit or costing the user their
# session, so nothing here is allowed to escape as an error.
export def Save(): bool
  if saving
    return false
  endif
  # Whatever the write does below, this flush window is over.  The flag is
  # cleared before the attempt rather than after a success on purpose: a write
  # that cannot work - a full disk, a read-only home, a cache path that is now
  # a directory - would otherwise stay dirty forever and re-arm on every
  # recorded file, turning one broken path into a rewrite attempt every few
  # seconds for the rest of the session.  The next file opened arms a fresh
  # window, and VimLeavePre still makes its final attempt.
  if pending != 0
    timer_stop(pending)
    pending = 0
  endif
  try
    # Also check when nothing has drawn or opened since the setting changed.
    EnsureScope()
    var needs_write = dirty || !empty(changes)
    dirty = false
    if !needs_write || !Persisting()
      return true
    endif
    saving = true
    if !Store()
      return false
    endif
    changes = {}
    zero_visits = []
    if ORDERED
      hidden_oldfiles = {}
    endif
  catch
    return false
  finally
    saving = false
  endtry
  return true
enddef

# The timer's callback, exported because that is also the only way to drive it
# from a test: Vim in `-es` mode never reaches the main loop, so a timer there
# would never fire and the regression would be untestable.
export def Flush(): bool
  if !dirty
    # The window has to be closed even when there is nothing to write, or the
    # id of the timer that just fired would sit in `pending` forever and Arm()
    # would never open another window for the rest of the session.
    pending = 0
    return true
  endif
  # Save() closes the window itself; stopping a timer that has already fired is
  # documented as a no-op, so both exits can share one implementation.
  return Save()
enddef
