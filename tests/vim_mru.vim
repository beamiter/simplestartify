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
# The four malformed lines are dropped and the one valid line is merged in,
# which is only observable if FromDisk() actually ran.
g:simplestartify_mru_max = 200
writefile(['nonsense', "0\t" .. GAMMA, "12\trelative/path", "\tleading tab",
  (localtime() - 3600) .. "\t" .. DELTA], CACHE)
assert_true(simplestartify#mru#Save())
assert_equal([GAMMA, ALPHA, DELTA], simplestartify#mru#List())

# Forgetting a path that is already in the on-disk cache must stick: Save()
# re-merges that cache, and without a tombstone the entry the user just
# dropped is written straight back and returns on the next launch.
assert_match(escape(GAMMA, '\.'), join(readfile(CACHE), "\n"))
assert_true(simplestartify#mru#Forget(GAMMA))
assert_equal([ALPHA, DELTA], simplestartify#mru#List())
assert_true(simplestartify#mru#Save())
assert_notmatch(escape(GAMMA, '\.'), join(readfile(CACHE), "\n"))
assert_equal([ALPHA, DELTA], simplestartify#mru#List())

# A tombstone is not a permanent ban: opening the file again records it anew
# and it persists like any other entry.
execute 'edit ' .. fnameescape(GAMMA)
assert_equal([GAMMA, ALPHA, DELTA], simplestartify#mru#List())
assert_true(simplestartify#mru#Save())
assert_match(escape(GAMMA, '\.'), join(readfile(CACHE), "\n"))

# A forget that removed nothing reports so and leaves no tombstone behind.
assert_false(simplestartify#mru#Forget(TEMP .. '/never-seen.txt'))

# The cap is a count of kept paths, so its documented lower bound means "keep
# none".  Reading 0 as "no cap" is the opposite instruction, and it let both
# the in-memory record and the file written at VimLeavePre grow without limit
# for exactly the user who asked for the smallest possible one.
g:simplestartify_mru_max = 0
execute 'edit ' .. fnameescape(DELTA)
assert_equal([], simplestartify#mru#List())
assert_equal(0, simplestartify#mru#Count())
assert_true(simplestartify#mru#Save())
assert_equal([], readfile(CACHE))

# And a small cap keeps exactly that many, newest first.
g:simplestartify_mru_max = 2
execute 'edit ' .. fnameescape(ALPHA)
execute 'edit ' .. fnameescape(BETA)
execute 'edit ' .. fnameescape(GAMMA)
assert_equal([GAMMA, BETA], simplestartify#mru#List())
assert_true(simplestartify#mru#Save())
assert_equal(2, len(readfile(CACHE)))
g:simplestartify_mru_max = 200

# A sibling Vim's work has to reach this Vim's dashboard while both are still
# running.  The record used to be read exactly once per session, so a list
# drawn hours later was still the list read at startup and a second Vim might
# as well not have existed; now that every Vim flushes its own record on a
# timer there is something to see, and the draw looks again.
writefile(readfile(CACHE) + [(localtime() + 120) .. "\t" .. DELTA], CACHE)
assert_equal([DELTA, GAMMA, BETA], simplestartify#mru#List())

# The record used to be written in exactly one place, at VimLeavePre, so a Vim
# that never got there - SIGKILL, the OOM killer, a container torn down, a flat
# battery - took every file it had opened with it.  Recording a file now arms a
# flush window, and the flush writes the cache with no quit in sight.  Timers
# never fire under `-es`, which never reaches the main loop, so the callback is
# called here exactly as the timer would have called it.
assert_equal([], timer_info())
delete(CACHE)
execute 'edit ' .. fnameescape(ALPHA)
assert_equal(1, len(timer_info()))
# One window, not one per file: re-arming on every recorded file would let a
# busy session postpone the write for as long as it kept opening things.
execute 'edit ' .. fnameescape(BETA)
assert_equal(1, len(timer_info()))
assert_true(simplestartify#mru#Flush())
assert_equal([], timer_info())
assert_match('\t' .. escape(BETA, '\.'), join(readfile(CACHE), "\n"))

# A flush with nothing to write is not a write.  Without that gate every armed
# window would rewrite the whole file, and a cache another Vim had just written
# would be replaced by an identical rewrite for no reason at all.
writefile(['written by someone else'], CACHE)
assert_true(simplestartify#mru#Flush())
assert_equal(['written by someone else'], readfile(CACHE))

# A cache is never worth aborting a quit, and a write that cannot succeed must
# not leave the flag set either: it would re-arm on every file opened for the
# rest of the session, so a read-only home would mean a doomed rewrite every
# few seconds forever.
g:simplestartify_mru_file = TEMP .. '/state/not-a-file'
mkdir(TEMP .. '/state/not-a-file', 'p')
execute 'edit ' .. fnameescape(GAMMA)
assert_equal(1, len(timer_info()))
assert_false(simplestartify#mru#Save())
assert_equal([], timer_info())
assert_true(simplestartify#mru#Flush())
assert_equal([], timer_info())
g:simplestartify_mru_file = CACHE

# The cache is read to the cap, and the two files that state a cap agree on it.
# plugin/ clamps g:simplestartify_mru_max into 0..5000 while the read stopped
# at 4096 lines, so every value in 4097..5000 was unreachable - and, because
# Save() rewrites whatever the read returned, the tail past 4096 was destroyed
# on the way out rather than merely ignored.
g:simplestartify_mru_max = 0
assert_equal([], simplestartify#mru#List())
g:simplestartify_mru_max = 4500
var stamp = localtime()
var many: list<string> = []
for index in range(4500)
  add(many, (stamp - index) .. "\t" .. TEMP .. '/deep/file-' .. index .. '.txt')
endfor
writefile(many, CACHE)
assert_equal(4500, simplestartify#mru#Count())
assert_equal(TEMP .. '/deep/file-4499.txt', simplestartify#mru#List()[-1])
assert_true(simplestartify#mru#Save())
assert_equal(4500, len(readfile(CACHE)))

# And the ceiling is the same 5000 on both sides.  A value assigned after
# startup never passes through plugin/, so this file has to hold the line on
# its own rather than trusting that someone else already clamped it - and an
# unbounded read of a cache this large is exactly what the old fixed limit was
# there to prevent.
g:simplestartify_mru_max = 0
assert_equal([], simplestartify#mru#List())
g:simplestartify_mru_max = 9000
for index in range(4500, 5099)
  add(many, (stamp - index) .. "\t" .. TEMP .. '/deep/file-' .. index .. '.txt')
endfor
writefile(many, CACHE)
assert_equal(5000, simplestartify#mru#Count())
g:simplestartify_mru_max = 200

execute 'lcd ' .. fnameescape(ROOT)
delete(TEMP, 'rf')
if !empty(v:errors)
  writefile(v:errors, '/dev/stderr')
  cquit 1
endif
qall!
