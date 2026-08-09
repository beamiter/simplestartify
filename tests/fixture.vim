vim9script

# Temporary-directory helpers shared by the scripts whose fixtures have to sit
# outside a Git repository.
#
# Vim's temporary directory is not necessarily outside one: a stray /tmp/.git,
# or a $HOME that is itself a checkout, makes every upward .git search from a
# fixture find *that* repository instead of nothing.  The assertions that
# depend on it used to be wrapped in a guard that skipped them whenever that
# happened, which reports a hole in the suite as a pass.  Pick a base whose
# whole ancestor chain is free of .git instead, so the assertion always runs,
# and say so loudly if the machine has none.
#
# Leaving tempname() behind costs two things Vim gave us for free, and both
# are paid back here: the directory is removed when Vim exits however the run
# ends (AutoRemove), and it is ours alone rather than a guessable name in a
# world-writable place another local user can pre-empt (PrivateDir).

# True when no .git exists at {path} or anywhere above it.
export def RepoFree(path: string): bool
  var directory = fnamemodify(path, ':p')
  while true
    var stripped = substitute(directory, '[\\/]\+$', '', '')
    if isdirectory(stripped .. '/.git') || filereadable(stripped .. '/.git')
      return false
    endif
    if empty(stripped)
      return true
    endif
    var parent = fnamemodify(stripped, ':h')
    if parent ==# stripped
      return true
    endif
    directory = parent
  endwhile
  return true
enddef

# Remove {path} when Vim exits, whatever ends the run.  A script that dies on
# an uncaught error, or quits through :cquit because an assertion failed, never
# reaches its own closing delete(), and a directory outside tempname() is not
# cleaned up by anyone else - so every aborted run would leave one more fixture
# tree behind for good.
export def AutoRemove(path: string)
  # Declaring the group before using it: :autocmd refuses an unknown group
  # name, and clearing it here would throw away an earlier registration.
  execute 'augroup simplestartify_fixture'
  execute 'augroup END'
  execute printf('autocmd simplestartify_fixture VimLeave * call delete(%s, %s)',
    string(path), string('rf'))
enddef

# Create {base}/{name} as a directory nobody else can have prepared, and return
# it - or an empty string when the path was already taken.
#
# A shared base such as /dev/shm or /var/tmp is mode 1777 and the name is
# guessable, so another local user can leave a symlink sitting at it.  mkdir()
# with 'p' would follow that link without a murmur: the whole fixture, .git
# directory included, lands wherever they pointed, the closing delete() removes
# only the link, and whatever they planted inside is what the assertions read.
# Creating the directory *without* 'p' fails on anything that already exists,
# symlink included, which is exactly the check that is wanted; 0700 then keeps
# the fixture unreadable to everyone else while it is in use.
export def PrivateDir(base: string, name: string): string
  var path = resolve(base) .. '/' .. name
  try
    mkdir(path, '', 0o700)
  catch /E739:/
    return ''
  endtry
  return path
enddef

# An existing, private directory for fixtures that must not look like they are
# inside a repository.  Vim's own temporary directory when it qualifies - Vim
# removes that one on exit, so it needs no registration - otherwise the first
# shared base that qualifies, made private and registered for removal.
export def RepoFreeTemp(): string
  var native = resolve(tempname())
  if RepoFree(native)
    var own = PrivateDir(fnamemodify(native, ':h'), fnamemodify(native, ':t'))
    if !empty(own)
      return own
    endif
  endif
  var name = 'simplestartify-test-' .. getpid() .. '-'
    .. fnamemodify(native, ':t')
  for base in [$XDG_RUNTIME_DIR, '/dev/shm', '/var/tmp', $TMPDIR]
    if filewritable(base) != 2 || !RepoFree(base)
      continue
    endif
    var owned = PrivateDir(base, name)
    if empty(owned)
      continue
    endif
    AutoRemove(owned)
    return owned
  endfor
  assert_report('no repository-free temporary directory on this machine: '
    .. 'every candidate has a .git above it, so the "outside a repository" '
    .. 'behaviour cannot be exercised')
  return native
enddef
