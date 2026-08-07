vim9script

# Session handling is intentionally small and fail-closed.  Names are always
# basenames inside the configured directory; neither command arguments nor a
# crafted completion value can escape it.

var session_random = srand()

def Notify(message: string, error: bool = false)
  execute error ? 'echohl ErrorMsg' : 'echohl ModeMsg'
  echomsg '[SimpleStartify] ' .. message
  echohl None
enddef

export def Dir(): string
  var configured = get(g:, 'simplestartify_session_dir', '')
  if type(configured) != v:t_string || empty(configured)
    configured = get(g:, 'startify_session_dir', '~/.vim/session')
  endif
  if type(configured) != v:t_string || empty(configured)
    return ''
  endif
  var path = fnamemodify(expand(configured), ':p')
  path = substitute(path, '[\\/]\+$', '', '')
  if empty(path) || path ==# '/' || path !~# '^\%(/\|[A-Za-z]:[\\/]\)'
    return ''
  endif
  return path
enddef

def SafeName(name: string): bool
  return !empty(name)
        \ && name !=# '.'
        \ && name !=# '..'
        \ && name !~# '^\.simplestartify-'
        \ && name !~# '[/\\\r\n]'
        \ && fnamemodify(name, ':t') ==# name
enddef

export def Path(name: string): string
  if !SafeName(name)
    return ''
  endif
  var directory = Dir()
  if empty(directory)
    return ''
  endif
  var path = fnamemodify(directory .. '/' .. name, ':p')
  return fnamemodify(path, ':h') ==# directory ? path : ''
enddef

def ByNewest(left: string, right: string): number
  var left_time = getftime(left)
  var right_time = getftime(right)
  if left_time == right_time
    return left ==# right ? 0 : (left <# right ? -1 : 1)
  endif
  return left_time > right_time ? -1 : 1
enddef

export def List(): list<string>
  var directory = Dir()
  if empty(directory) || !isdirectory(directory)
    return []
  endif
  var paths = globpath(directory, '*', false, true)
  filter(paths, (_, path) => getftype(path) ==# 'file' && filereadable(path)
        \ && fnamemodify(path, ':t') !=# '__LAST__'
        \ && fnamemodify(path, ':t') !~# '^\.simplestartify-')
  sort(paths, ByNewest)
  return mapnew(paths, (_, path) => fnamemodify(path, ':t'))
enddef

export def Complete(lead: string, _line: string, _position: number): list<string>
  return filter(List(), (_, name) => stridx(name, lead) == 0)
enddef

def EnsureDir(): bool
  var directory = Dir()
  if empty(directory)
    Notify('invalid session directory', true)
    return false
  endif
  if !isdirectory(directory)
    try
      mkdir(directory, 'p', 0o700)
    catch
      Notify('cannot create session directory: ' .. directory, true)
      return false
    endtry
  endif
  if filewritable(directory) != 2
    Notify('session directory is not writable: ' .. directory, true)
    return false
  endif
  return true
enddef

def HiddenTemporary(directory: string): string
  for attempt in range(64)
    var candidate = $'{directory}/.simplestartify-tmp-{getpid()}-'
          \ .. $'{localtime()}-{rand(session_random)}-{attempt}'
    if empty(getftype(candidate))
      return candidate
    endif
  endfor
  return ''
enddef

def LastPointer(): string
  var directory = Dir()
  return empty(directory) ? '' : directory .. '/.simplestartify-last'
enddef

def LastSessionName(): string
  var pointer = LastPointer()
  if getftype(pointer) ==# 'file' && filereadable(pointer)
    var lines = readfile(pointer, '', 1)
    if !empty(lines) && SafeName(lines[0]) && filereadable(Path(lines[0]))
      return lines[0]
    endif
  endif

  # Migrate vim-startify's historical __LAST__ symlink/file without exposing
  # it as a normal dashboard entry.
  var legacy = Path('__LAST__')
  if filereadable(legacy)
    var resolved = resolve(legacy)
    if getftype(legacy) ==# 'link'
          \ && fnamemodify(resolved, ':h') ==# Dir()
          \ && getftype(resolved) ==# 'file'
          \ && filereadable(resolved)
      return fnamemodify(resolved, ':t')
    endif
    return getftype(legacy) ==# 'file' ? '__LAST__' : ''
  endif
  return ''
enddef

def RecordLast(name: string)
  if !SafeName(name) || name ==# '__LAST__' || !filereadable(Path(name))
    return
  endif
  var pointer = LastPointer()
  var pointer_type = getftype(pointer)
  if !empty(pointer_type) && pointer_type !=# 'file'
    Notify('last-session pointer is not a regular file: ' .. pointer, true)
    return
  endif
  var temporary = HiddenTemporary(Dir())
  if empty(temporary)
    Notify('could not allocate last-session pointer', true)
    return
  endif
  if writefile([name], temporary, 's') != 0 || rename(temporary, pointer) != 0
    delete(temporary)
    Notify('could not update last-session pointer', true)
  endif
enddef

def LeaveDashboard()
  if get(b:, 'simplestartify', 0) != 1
    return
  endif
  var origin = get(b:, 'simplestartify_origin', -1)
  var alternate = bufnr('#')
  var target = origin > 0 && origin != bufnr() && bufexists(origin)
        \ ? origin
        \ : alternate
  if target > 0 && target != bufnr() && bufexists(target)
    execute 'silent keepalt buffer ' .. target
  else
    silent keepalt enew
  endif
enddef

def ModifiedBuffers(): list<string>
  var names: list<string> = []
  for info in getbufinfo({buflisted: 1})
    if getbufvar(info.bufnr, '&modified')
      var name = bufname(info.bufnr)
      add(names, empty(name) ? '[No Name]' : fnamemodify(name, ':~:.'))
    endif
  endfor
  return names
enddef

def DeleteListedBuffers()
  # :%bdelete uses a line range, not a reliable "all buffers" selector.  Take
  # an explicit snapshot so deleting the current buffer cannot perturb the
  # iteration.
  var numbers = mapnew(getbufinfo({buflisted: 1}), (_, info) => info.bufnr)
  for number in numbers
    if bufexists(number)
      execute 'silent! bdelete! ' .. number
    endif
  endfor
enddef

def Snapshot(): string
  var path = tempname() .. '.vim'
  var old_options = &sessionoptions
  var old_session = v:this_session
  try
    set sessionoptions-=options
    execute 'silent mksession! ' .. fnameescape(path)
    v:this_session = old_session
    return path
  catch
    v:this_session = old_session
    delete(path)
    Notify('could not prepare session rollback: ' .. v:exception, true)
    return ''
  finally
    &sessionoptions = old_options
  endtry
  return ''
enddef

def WritePath(path: string): bool
  if empty(path) || !EnsureDir()
    return false
  endif
  LeaveDashboard()
  var temporary = HiddenTemporary(Dir())
  if empty(temporary)
    Notify('could not allocate a session temporary file', true)
    return false
  endif
  var old_options = &sessionoptions
  var old_session = v:this_session
  try
    set sessionoptions-=options
    execute 'silent mksession! ' .. fnameescape(temporary)
    if rename(temporary, path) != 0
      throw 'cannot replace ' .. path
    endif
    v:this_session = path
    return true
  catch
    v:this_session = old_session
    delete(temporary)
    Notify('session save failed: ' .. v:exception, true)
    return false
  finally
    &sessionoptions = old_options
  endtry
  return false
enddef

export def Save(bang: bool = false, requested: string = ''): bool
  var name = requested
  if empty(name)
    inputsave()
    try
      name = input('Save session as: ', fnamemodify(v:this_session, ':t'))
    finally
      inputrestore()
    endtry
  endif
  var path = Path(name)
  if empty(path)
    Notify('invalid session name: ' .. string(name), true)
    return false
  endif
  var existing_type = getftype(path)
  if !empty(existing_type)
    if !bang
      Notify('session already exists; use :SSave! to overwrite: ' .. name, true)
      return false
    elseif existing_type !=# 'file'
      Notify('refusing to overwrite non-file session path: ' .. name, true)
      return false
    endif
  endif
  if WritePath(path)
    RecordLast(name)
    Notify('session saved: ' .. name)
    return true
  endif
  return false
enddef

def ManagedCurrentPath(): string
  if empty(v:this_session)
    return ''
  endif
  var directory = Dir()
  var current = fnamemodify(v:this_session, ':p')
  return !empty(directory) && fnamemodify(current, ':h') ==# directory
        \ ? current
        \ : ''
enddef

def PersistCurrent(required: bool = false): bool
  if !required && !get(g:, 'simplestartify_session_persistence', 0)
    return true
  endif
  if empty(v:this_session)
    return true
  endif
  var current = ManagedCurrentPath()
  # An externally sourced session is outside this plugin's write boundary.
  if empty(current)
    return true
  endif
  if getftype(current) !=# 'file' || !filereadable(current)
    Notify('managed session is missing or not a regular file: ' .. current, true)
    return false
  endif
  if filewritable(current) != 1
    Notify('managed session is not writable: ' .. current, true)
    return false
  endif
  return WritePath(current)
enddef

export def Persist(): bool
  return PersistCurrent()
enddef

export def Load(bang: bool = false, requested: string = ''): bool
  var name = requested
  if empty(name) && bang
    name = LastSessionName()
    if empty(name)
      Notify('there is no last session', true)
      return false
    endif
  endif
  if empty(name)
    inputsave()
    try
      name = input('Load session: ', '', 'customlist,simplestartify#session#Complete')
    finally
      inputrestore()
    endtry
  endif
  var path = Path(name)
  var path_type = getftype(path)
  if path_type ==# 'link'
    var resolved = resolve(path)
    if name ==# '__LAST__'
          \ && fnamemodify(resolved, ':h') ==# Dir()
          \ && getftype(resolved) ==# 'file'
          \ && filereadable(resolved)
      path = resolved
      name = fnamemodify(resolved, ':t')
      path_type = 'file'
    endif
  endif
  if empty(path) || path_type !=# 'file' || !filereadable(path)
    Notify('no such session: ' .. string(name), true)
    return false
  endif
  var modified = ModifiedBuffers()
  if !bang && !empty(modified)
    Notify('modified buffers would be discarded; save them or use :SLoad!: '
      .. join(modified, ', '), true)
    return false
  endif
  if !PersistCurrent(false)
    return false
  endif
  var previous_session = v:this_session
  LeaveDashboard()
  var rollback = Snapshot()
  if empty(rollback)
    return false
  endif
  try
    DeleteListedBuffers()
    execute 'silent source ' .. fnameescape(path)
    v:this_session = path
    RecordLast(name)
    silent! doautocmd <nomodeline> User SimpleStartifySessionLoaded
    return true
  catch
    var failure = v:exception
    try
      DeleteListedBuffers()
      execute 'silent source ' .. fnameescape(rollback)
      v:this_session = previous_session
    catch
      failure ..= '; rollback failed: ' .. v:exception
    endtry
    Notify('session load failed: ' .. failure, true)
    return false
  finally
    delete(rollback)
  endtry
  return false
enddef

export def Delete(bang: bool = false, requested: string = ''): bool
  var name = requested
  if empty(name)
    inputsave()
    try
      name = input('Delete session: ', '', 'customlist,simplestartify#session#Complete')
    finally
      inputrestore()
    endtry
  endif
  var path = Path(name)
  if empty(path) || !filereadable(path)
    Notify('no such session: ' .. string(name), true)
    return false
  endif
  if !bang
    Notify('use :SDelete! to confirm deletion: ' .. name, true)
    return false
  endif
  var was_last = LastSessionName() ==# name
  if delete(path) != 0
    Notify('could not delete session: ' .. name, true)
    return false
  endif
  if fnamemodify(v:this_session, ':p') ==# path
    v:this_session = ''
  endif
  if was_last && getftype(LastPointer()) ==# 'file'
    delete(LastPointer())
  endif
  Notify('session deleted: ' .. name)
  return true
enddef

export def Close(bang: bool = false)
  var modified = ModifiedBuffers()
  if !bang && !empty(modified)
    Notify('modified buffers would be discarded; save them or use :SClose!: '
      .. join(modified, ', '), true)
    return
  endif
  if !PersistCurrent(true)
    Notify('session persistence failed; close aborted', true)
    return
  endif
  v:this_session = ''
  DeleteListedBuffers()
  simplestartify#Open()
enddef
