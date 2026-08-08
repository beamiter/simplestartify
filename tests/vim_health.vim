vim9script

# The health check is the first thing a user runs and the first thing that
# lands in a bug report, so each fact it can state gets a test that provokes
# exactly that condition.

set nocompatible
set nomore
set hidden

const ROOT = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
const TEMP = tempname()
mkdir(TEMP .. '/sessions', 'p')
writefile([], TEMP .. '/sessions/work')

execute 'set runtimepath^=' .. fnameescape(ROOT)
g:simplestartify_auto_open = 0
g:simplestartify_session_dir = TEMP .. '/sessions'
g:simplestartify_mru_file = TEMP .. '/state/mru'
execute 'source ' .. fnameescape(ROOT .. '/plugin/simplestartify.vim')

def Report(): string
  return join(simplestartify#Health().report, "\n")
enddef

var health = simplestartify#Health()
assert_true(health.ok)
assert_equal(1, health.session_count)
assert_true(health.session_writable)
assert_equal([], health.session_leftovers)
for section in ['ENVIRONMENT', 'STYLES', 'RECENT FILES', 'SESSIONS']
  assert_match(section, join(health.report, "\n"))
endfor
assert_notmatch('\[ERROR\]', join(health.report, "\n"))

# Every test here runs with -i NONE, so the recent-files section has to say
# why it is empty instead of just being empty.
assert_equal(0, health.oldfiles_count)
assert_match("\\[WARN\\].*viminfo", Report())

# An unknown style used to surface only as an error message on every draw.
g:simplestartify_style = 'centred'
var typo = simplestartify#Health()
assert_false(typo.ok)
assert_match('\[ERROR\].*g:simplestartify_style = centred', join(typo.report, "\n"))
g:simplestartify_style = 'random'

# A crash between "write the temporary" and "rename it into place" leaves a
# file the dashboard deliberately hides.  Health is where it becomes visible,
# and :SimpleStartifyClean is the remedy it names.
var leftover = TEMP .. '/sessions/.simplestartify-tmp-999-1-1-0'
writefile(['stale'], leftover)
assert_equal(['work'], simplestartify#session#List())
assert_equal([leftover], simplestartify#session#TempLeftovers())
assert_match('\[WARN\].*leftover', Report())
SimpleStartifyClean
assert_false(filereadable(leftover))
assert_notmatch('\[WARN\].*leftover', Report())

# A pointer that is not a regular file is fatal: RecordLast() refuses to
# replace it, so every save silently fails to update the last session.
mkdir(TEMP .. '/sessions/.simplestartify-last', 'p')
var blocked = simplestartify#Health()
assert_false(blocked.ok)
assert_match('\[ERROR\].*last-session pointer is a dir', join(blocked.report, "\n"))
delete(TEMP .. '/sessions/.simplestartify-last', 'd')

# A pointer naming a session that has since been deleted is a warning, not an
# error: the next successful save replaces it.
writefile(['gone'], TEMP .. '/sessions/.simplestartify-last')
assert_match('\[WARN\].*missing session: gone', Report())
writefile(['work'], TEMP .. '/sessions/.simplestartify-last')
assert_match('\[OK\].*last session: work', Report())

# An unwritable session directory is an error, and used to be computed and
# then ignored by "ok".
setfperm(TEMP .. '/sessions', 'r-xr-xr-x')
if filewritable(TEMP .. '/sessions') != 2
  # Skipped when the test runs as root, where mode bits do not deny anything.
  var locked = simplestartify#Health()
  assert_false(locked.session_writable)
  assert_false(locked.ok)
  assert_match('\[ERROR\].*not writable', join(locked.report, "\n"))
endif
setfperm(TEMP .. '/sessions', 'rwxr-xr-x')

# The report renders into its own scratch buffer.
SimpleStartifyHealth
assert_equal('nofile', &buftype)
assert_equal('simplestartifyhealth', &filetype)
assert_false(&modifiable)
assert_match('SimpleStartify health', getline(1))
assert_match('SESSIONS', join(getline(1, '$'), "\n"))
bwipeout!

execute 'lcd ' .. fnameescape(ROOT)
delete(TEMP, 'rf')
if !empty(v:errors)
  writefile(v:errors, '/dev/stderr')
  cquit 1
endif
qall!
