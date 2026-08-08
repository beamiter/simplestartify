vim9script

# The session store and the recent-files cache need the same guarantee: a
# reader either sees the previous file or the complete new one, never a
# half-written mix, and a crash must never leave a corrupt target behind.
# Both therefore write a hidden neighbour first and rename it into place.
# Keeping that primitive here means there is exactly one implementation of it
# and one reserved namespace to filter out of listings.

var atomic_random = srand()

# Every temporary this plugin creates starts with this prefix, and no legal
# session name may, so a crash leftover can always be recognised and can never
# collide with real content.
export const PREFIX = '.simplestartify-'

export def Temporary(directory: string): string
  # Fresh candidate per attempt, existence-checked before use: two Vim
  # instances saving in the same second must not pick the same path.
  for attempt in range(64)
    var candidate = $'{directory}/{PREFIX}tmp-{getpid()}-'
          \ .. $'{localtime()}-{rand(atomic_random)}-{attempt}'
    if empty(getftype(candidate))
      return candidate
    endif
  endfor
  return ''
enddef

export def Replace(lines: list<string>, path: string): bool
  var directory = fnamemodify(path, ':h')
  if empty(path) || empty(directory) || !isdirectory(directory)
    return false
  endif
  var existing = getftype(path)
  # Refuse to follow a symlink or clobber a directory: the rename would
  # otherwise silently replace something that is not ours.
  if !empty(existing) && existing !=# 'file'
    return false
  endif
  var temporary = Temporary(directory)
  if empty(temporary)
    return false
  endif
  if writefile(lines, temporary, 's') != 0 || rename(temporary, path) != 0
    delete(temporary)
    return false
  endif
  return true
enddef
