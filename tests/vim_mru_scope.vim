vim9script

# Cache identity is evaluated on use, including the timer/exit save. A pending
# visit or Forget must never be written to a different configured cache.
set hidden
const ROOT = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
const TMP = tempname()
mkdir(TMP, '', 0o700)
const A = TMP .. '/scope-a'
const B = TMP .. '/scope-b'
const ALPHA = TMP .. '/alpha.txt'
const BETA = TMP .. '/beta.txt'
const GAMMA = TMP .. '/gamma.txt'
for path in [ALPHA, BETA, GAMMA]
  writefile(['x'], path)
endfor
const A_SEED = ['1700000000' .. "\t" .. ALPHA]
const B_SEED = ['1700000000' .. "\t" .. BETA]
writefile(A_SEED, A)
writefile(B_SEED, B)
execute 'set runtimepath^=' .. fnameescape(ROOT)
g:simplestartify_auto_open = 0
g:simplestartify_session_dir = TMP .. '/sessions'
g:simplestartify_mru_file = A
execute 'source ' .. fnameescape(ROOT .. '/plugin/simplestartify.vim')

execute 'edit ' .. fnameescape(GAMMA)
assert_equal([GAMMA, ALPHA], simplestartify#mru#List(), 'visit pending in A')
g:simplestartify_mru_file = B
assert_true(simplestartify#mru#Save(), 'first observation of switch is the save')
assert_equal(B_SEED, readfile(B), 'a pending visit from A must not reach B')
assert_equal(A_SEED, readfile(A), 'switch does not silently write the old cache')
assert_equal([BETA], simplestartify#mru#List(), 'draw sees only B')

# The same file can belong to both histories; Forget in A must not erase B.
writefile(B_SEED + A_SEED, B)
g:simplestartify_mru_file = A
assert_equal([ALPHA], simplestartify#mru#List())
assert_true(simplestartify#mru#Forget(ALPHA))
g:simplestartify_mru_file = B
assert_equal([BETA, ALPHA], simplestartify#mru#List(), 'Forget from A must not filter B')
assert_true(simplestartify#mru#Save())
assert_equal(B_SEED + A_SEED, readfile(B), 'Forget from A must not write B')

# Relative file settings can resolve differently after a cwd change even when
# the option string stays identical.
mkdir(TMP .. '/first', '', 0o700)
mkdir(TMP .. '/second', '', 0o700)
writefile(A_SEED, TMP .. '/first/history')
writefile(B_SEED, TMP .. '/second/history')
execute 'cd ' .. fnameescape(TMP .. '/first')
g:simplestartify_mru_file = 'history'
execute 'edit ' .. fnameescape(GAMMA)
assert_equal([GAMMA, ALPHA], simplestartify#mru#List())
execute 'cd ' .. fnameescape(TMP .. '/second')
assert_true(simplestartify#mru#Flush())
assert_equal([BETA], simplestartify#mru#List(), 'relative path scopes by resolved cache')
assert_equal(B_SEED, readfile(TMP .. '/second/history'))

# Same-scope saves still commit a genuine new visit.
execute 'edit ' .. fnameescape(ALPHA)
assert_true(simplestartify#mru#Save())
assert_equal([ALPHA, BETA], simplestartify#mru#List())
assert_match('\V' .. escape(ALPHA, '\'), join(readfile(TMP .. '/second/history'), "\n"))
cd /
delete(TMP, 'rf')
if !empty(v:errors)
  writefile(v:errors, '/dev/stderr')
  cquit 1
endif
qall!
