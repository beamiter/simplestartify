vim9script

# Recent files must reflect this session, not only what viminfo happened to
# record before Vim started.  Every test here runs with `-i NONE`, so
# v:oldfiles is empty for the whole script: anything the dashboard shows had
# to be tracked live.

set nocompatible
set nomore
set hidden

const ROOT = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
const TEMP = tempname()
mkdir(TEMP .. '/sessions', 'p')
const CACHE = TEMP .. '/state/mru'
const ALPHA = TEMP .. '/alpha.txt'
const BETA = TEMP .. '/beta.txt'
const GAMMA = TEMP .. '/gamma.txt'
const DELTA = TEMP .. '/delta.txt'
for path in [ALPHA, BETA, GAMMA, DELTA]
  writefile(['x'], path)
endfor

execute 'set runtimepath^=' .. fnameescape(ROOT)
g:simplestartify_auto_open = 0
g:simplestartify_session_dir = TEMP .. '/sessions'
g:simplestartify_mru_file = CACHE
g:simplestartify_recent_count = 9
execute 'source ' .. fnameescape(ROOT .. '/plugin/simplestartify.vim')

# Baseline: with -i NONE there is nothing to inherit.
assert_equal([], v:oldfiles)
assert_equal([], simplestartify#mru#List())

execute 'edit ' .. fnameescape(ALPHA)
execute 'edit ' .. fnameescape(BETA)

# Vim never updates v:oldfiles during a session.  This assertion documents the
# defect the tracker exists to work around: without it the list below is empty.
assert_equal([], v:oldfiles)
assert_equal([BETA, ALPHA], simplestartify#mru#List())

# Re-opening a file moves it back to the front rather than duplicating it.
execute 'edit ' .. fnameescape(ALPHA)
assert_equal([ALPHA, BETA], simplestartify#mru#List())

# A file that exists only because this session opened it must be reachable
# from the dashboard.  Before in-session tracking this section was empty.
SimpleStartify minimal
var recent = filter(values(b:simplestartify_actions),
  (_, action) => get(action, 'kind', '') ==# 'file')
assert_equal(2, len(recent))
assert_equal(ALPHA, get(get(b:simplestartify_actions, '5', {}), 'path', ''))
simplestartify#ActivateKey('1')
assert_equal(ALPHA, expand('%:p'))

# Buffers without a real file on disk never enter the list: the dashboard is a
# nofile scratch buffer and must not record itself.
SimpleStartify minimal
assert_equal([ALPHA, BETA], simplestartify#mru#List())
enew
setline(1, 'scratch')
setlocal buftype=nofile
simplestartify#mru#Touch()
assert_equal([ALPHA, BETA], simplestartify#mru#List())

# Session files are the plugin's own bookkeeping and are skipped.
writefile([], TEMP .. '/sessions/work')
execute 'edit ' .. fnameescape(TEMP .. '/sessions/work')
assert_equal([ALPHA, BETA], simplestartify#mru#List())

# :SimpleStartifyForget drops an entry, and reports an unknown path instead of
# pretending to have done something.
execute 'SimpleStartifyForget ' .. fnameescape(BETA)
assert_equal([ALPHA], simplestartify#mru#List())
assert_false(simplestartify#mru#Forget(BETA))

# Persistence: the cache is written atomically under the configured path, and
# the reserved temporary namespace is not left behind.
assert_true(simplestartify#mru#Save())
assert_true(filereadable(CACHE))
assert_match('\t' .. escape(ALPHA, '\.'), join(readfile(CACHE), "\n"))
assert_equal([], glob(TEMP .. '/state/.simplestartify-*', false, true))

# A sibling Vim instance writing the same cache must not have its entries
# discarded by our save, and a newer timestamp there wins.
writefile(readfile(CACHE) + [(localtime() + 60) .. "\t" .. GAMMA], CACHE)
assert_true(simplestartify#mru#Save())
assert_equal([GAMMA, ALPHA], simplestartify#mru#List())

# A corrupt or hand-edited cache degrades to "fewer entries", never an error.
# This has to go through Save(), which re-reads the file: List() memoises the
# first Load() and would never open the cache again, so asserting on it here
# would compare the in-memory list against itself and pass no matter what the
# parser did.  The four malformed lines are dropped and the one valid line is
# merged in, which is only observable if FromDisk() actually ran.
g:simplestartify_mru_max = 200
writefile(['nonsense', "0\t" .. GAMMA, "12\trelative/path", "\tleading tab",
  (localtime() - 3600) .. "\t" .. DELTA], CACHE)
assert_true(simplestartify#mru#Save())
assert_equal([GAMMA, ALPHA, DELTA], simplestartify#mru#List())

execute 'lcd ' .. fnameescape(ROOT)
delete(TEMP, 'rf')
if !empty(v:errors)
  writefile(v:errors, '/dev/stderr')
  cquit 1
endif
qall!
