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
var loaded = false

# Paths the user explicitly forgot during this session.  Removing an entry from
# `entries` alone is not enough: every merge with the on-disk cache - both the
# lazy Load() and the re-read Store() performs so a sibling Vim's work is not
# discarded - would find the path still on disk and put it straight back, so
# :SimpleStartifyForget would silently undo itself at VimLeavePre.  A merge
# therefore skips anything listed here, and only re-recording the file (opening
# it again) clears its tombstone.
var forgotten: dict<bool> = {}

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

def Maximum(): number
  var value = get(g:, 'simplestartify_mru_max', 200)
  return type(value) == v:t_number ? min([CEILING, max([0, value])]) : 200
enddef

export def File(): string
  var value = get(g:, 'simplestartify_mru_file', '')
  if type(value) != v:t_string || empty(value)
    return ''
  endif
  return fnamemodify(expand(value), ':p')
enddef

def Persisting(): bool
  return Flag('simplestartify_mru_persist', 1) && !empty(File())
enddef

def Newest(left: dict<any>, right: dict<any>): number
  if left.time != right.time
    return left.time > right.time ? -1 : 1
  endif
  if left.seq != right.seq
    return left.seq > right.seq ? -1 : 1
  endif
  return left.path ==# right.path ? 0 : (left.path <# right.path ? -1 : 1)
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

def FromDisk(): list<dict<any>>
  var out: list<dict<any>> = []
  var path = File()
  if !Persisting() || !filereadable(path)
    disk_stamp = -1
    return out
  endif
  # Stamped before the read, never after: a sibling Vim that replaces the file
  # between the two would otherwise leave us holding its new timestamp and the
  # old contents.  And a stamp from the current second is not remembered at
  # all, for the same reason session.vim does not remember one: file times have
  # one-second resolution, so a write later in this same second would leave the
  # stored value equal and go unnoticed.
  var stamp = getftime(path)
  disk_stamp = stamp < localtime() ? stamp : -1
  # One entry per line as "<epoch><TAB><absolute path>".  A line that does not
  # parse is dropped rather than fatal: this is a cache, not a database, and a
  # truncated or hand-edited file must never break the dashboard.
  #
  # Exactly Maximum() lines: fewer silently truncates a cache the user asked
  # for and loses its tail at the next write, more would be read only to be
  # thrown away by Capped().  readfile() reads nothing at a {max} of zero,
  # which is what a cap of zero - "keep none" - asks for anyway.
  for line in readfile(path, '', Maximum())
    var tab = stridx(line, "\t")
    if tab <= 0
      continue
    endif
    var when = str2nr(strpart(line, 0, tab))
    var candidate = strpart(line, tab + 1)
    if when <= 0 || empty(candidate) || candidate !~# '^\%(/\|[A-Za-z]:[\\/]\)'
      continue
    endif
    add(out, {path: candidate, time: when, seq: 0})
  endfor
  return out
enddef

def Merge(extra: list<dict<any>>)
  # Newest wins per path, so a sibling Vim that recorded the same file more
  # recently is respected instead of being overwritten by our stale copy.
  var index: dict<number> = {}
  var merged: list<dict<any>> = []
  for entry in entries + extra
    if has_key(forgotten, entry.path)
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
  sort(merged, Newest)
  entries = Capped(merged)
enddef

# Reading the file is deferred until something actually needs the list, so a
# Vim that never opens the dashboard pays nothing for this feature at startup.
export def Load()
  if loaded
    return
  endif
  loaded = true
  Merge(FromDisk())
enddef

# Load() answers "have we ever read the cache"; this answers "has it changed
# since".  A Vim open all day used to answer every dashboard draw from the list
# it read once at startup, so a sibling Vim's work stayed invisible to it
# however long both ran - and now that both of them flush on a timer, there is
# finally something there to see.  One stat per draw is what turns two records
# into a shared one.  Tombstones still win - Merge() skips anything in
# `forgotten` - so a re-read can never undo a :SimpleStartifyForget.
def Sync()
  if !loaded
    Load()
    return
  endif
  if !Persisting() || getftime(File()) == disk_stamp
    return
  endif
  Merge(FromDisk())
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
  try
    for pattern in patterns
      if type(pattern) == v:t_string && !empty(pattern) && path =~# pattern
        return true
      endif
    endfor
  catch
  endtry
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

def Record(path: string, when: number)
  Load()
  # Opening the file again is a deliberate act that outranks the earlier
  # "forget this": drop the tombstone so the entry can persist normally.
  if has_key(forgotten, path)
    remove(forgotten, path)
  endif
  sequence += 1
  var found = Find(path)
  if found >= 0
    remove(entries, found)
  endif
  insert(entries, {path: path, time: when, seq: sequence}, 0)
  entries = Capped(entries)
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
  Record(path, localtime())
enddef

def ForgetOldfile(path: string): bool
  # v:oldfiles is a plain, writable list, so dropping the entry there too
  # makes "forget this file" mean what a user expects: it does not reappear on
  # the next draw, and viminfo carries the removal into the next session.
  if !exists('v:oldfiles') || type(v:oldfiles) != v:t_list
    return false
  endif
  var removed = false
  for index in reverse(range(len(v:oldfiles)))
    if fnamemodify(v:oldfiles[index], ':p') ==# path
      remove(v:oldfiles, index)
      removed = true
    endif
  endfor
  return removed
enddef

export def Forget(requested: string): bool
  # Sync() rather than Load(): a path that only a sibling Vim has recorded is
  # still a path the user can see on the dashboard and ask to forget, and
  # without the tombstone that a successful forget leaves, the next merge with
  # the cache would put it straight back.
  Sync()
  if empty(requested)
    return false
  endif
  var path = fnamemodify(expand(requested), ':p')
  var before = len(entries)
  filter(entries, (_, entry) => entry.path !=# path)
  var dropped = len(entries) != before
  var oldfile = ForgetOldfile(path)
  # Only a forget that actually removed something leaves a tombstone, so a
  # mistyped path stays the no-op it reports itself to be.
  if dropped || oldfile
    forgotten[path] = true
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
  if !Persisting()
    return true
  endif
  loaded = true
  # Re-merge on the way out: another Vim may have written the file since we
  # read it, and a last-writer-wins overwrite would silently discard its work.
  Merge(FromDisk())
  var path = File()
  if empty(entries) && !filereadable(path)
    return true
  endif
  var directory = fnamemodify(path, ':h')
  if !isdirectory(directory)
    try
      mkdir(directory, 'p', 0o700)
    catch
      return false
    endtry
  endif
  return simplestartify#atomic#Replace(
    mapnew(entries, (_, entry) => entry.time .. "\t" .. entry.path), path)
enddef

# This runs at VimLeavePre, ahead of the session hook, and from the flush
# timer.  A cache is never worth aborting a quit or costing the user their
# session, so nothing here is allowed to escape as an error.
export def Save(): bool
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
  dirty = false
  try
    return Store()
  catch
    return false
  endtry
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
