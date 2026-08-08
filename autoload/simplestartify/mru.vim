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

def Maximum(): number
  var value = get(g:, 'simplestartify_mru_max', 200)
  return type(value) == v:t_number ? max([0, value]) : 200
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
    return out
  endif
  # One entry per line as "<epoch><TAB><absolute path>".  A line that does not
  # parse is dropped rather than fatal: this is a cache, not a database, and a
  # truncated or hand-edited file must never break the dashboard.
  for line in readfile(path, '', 4096)
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

def Skip(path: string): bool
  if empty(path) || path =~# '[\t\r\n]'
    return true
  endif
  # Session files are the plugin's own bookkeeping; loading one must not make
  # it look like a recently edited document.
  var directory = simplestartify#session#Dir()
  return !empty(directory) && fnamemodify(path, ':h') ==# directory
enddef

def Record(path: string, when: number)
  Load()
  # Opening the file again is a deliberate act that outranks the earlier
  # "forget this": drop the tombstone so the entry can persist normally.
  if has_key(forgotten, path)
    remove(forgotten, path)
  endif
  sequence += 1
  var found = index(mapnew(entries, (_, entry) => entry.path), path)
  if found >= 0
    remove(entries, found)
  endif
  insert(entries, {path: path, time: when, seq: sequence}, 0)
  entries = Capped(entries)
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
  Load()
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
  endif
  return oldfile || dropped
enddef

export def List(): list<string>
  Load()
  return mapnew(entries, (_, entry) => entry.path)
enddef

export def Count(): number
  Load()
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

# This runs at VimLeavePre, ahead of the session hook.  A cache is never worth
# aborting a quit or costing the user their session, so nothing here is
# allowed to escape as an error.
export def Save(): bool
  try
    return Store()
  catch
    return false
  endtry
enddef
