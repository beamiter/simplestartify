vim9script

# tests/fixture.vim exists because two scripts need a fixture that is not
# inside a Git repository, and Vim's own temporary directory is not always
# outside one.  Stepping away from tempname() gives up two things Vim was
# doing for free, and giving either of them up silently is how a test suite
# starts littering - or reading a fixture somebody else prepared:
#
#   * Vim deletes its temporary directory when it exits, however the run ends.
#     A directory of our own choosing has no such net, so a run that dies on
#     an uncaught error - or is killed - would leave the whole fixture tree
#     behind, on every aborted run, for good.
#   * Vim creates that directory itself, mode 0700.  A guessable name under a
#     mode-1777 base such as /dev/shm or /var/tmp can be pre-created by another
#     local user as a symlink, and mkdir(..., 'p') follows one without a word.
#
# Both are asserted here, the first through a child Vim that really does abort.

set nocompatible
set nomore
set hidden

const ROOT = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')

import './fixture.vim' as fixture

const FREE = fixture.RepoFreeTemp()

# What every caller is handed: a directory that already exists, is private, and
# has no repository above it.
assert_true(isdirectory(FREE), 'RepoFreeTemp() returned no directory: ' .. FREE)
assert_equal('rwx------', getfperm(FREE))
assert_true(fixture.RepoFree(FREE),
  'RepoFreeTemp() handed out a directory inside a repository: ' .. FREE)

# ---------------------------------------------------------------------------
# RepoFree(): a .git anywhere above the path disqualifies it.
# ---------------------------------------------------------------------------

mkdir(FREE .. '/tree/deep', 'p')
assert_true(fixture.RepoFree(FREE .. '/tree/deep'))

mkdir(FREE .. '/tree/.git', 'p')
assert_false(fixture.RepoFree(FREE .. '/tree/deep'))
delete(FREE .. '/tree/.git', 'd')

# A worktree or a submodule checkout has a .git *file* pointing elsewhere, and
# Git treats it as a repository just the same.
writefile(['gitdir: ' .. FREE .. '/tree/nowhere'], FREE .. '/tree/.git')
assert_false(fixture.RepoFree(FREE .. '/tree/deep'))
delete(FREE .. '/tree/.git')
assert_true(fixture.RepoFree(FREE .. '/tree/deep'))

# ---------------------------------------------------------------------------
# PrivateDir(): the directory is ours, or there is no directory.
# ---------------------------------------------------------------------------

const OWNED = fixture.PrivateDir(FREE, 'owned')
assert_equal(resolve(FREE) .. '/owned', OWNED)
assert_true(isdirectory(OWNED))
assert_equal('rwx------', getfperm(OWNED))

# Anything already sitting at the name is refused rather than adopted: that
# refusal is the whole defence, since the name is guessable and the base of the
# fallback chain is world-writable.
mkdir(FREE .. '/squatted', 'p')
assert_equal('', fixture.PrivateDir(FREE, 'squatted'))

if has('unix') && executable('ln')
  mkdir(FREE .. '/victim', 'p')
  writefile(['precious'], FREE .. '/victim/precious.txt')
  call system('ln -s ' .. shellescape(FREE .. '/victim')
    .. ' ' .. shellescape(FREE .. '/planted'))

  assert_equal('', fixture.PrivateDir(FREE, 'planted'))
  assert_equal(['precious.txt'], readdir(FREE .. '/victim'))

  # And this is what the refusal is worth: mkdir(..., 'p') is happy to reuse
  # whatever is at the name, so the fixture would have been built inside the
  # directory the link names - where its owner can read it, seed it, and keep
  # it, since deleting the link afterwards leaves the contents untouched.
  mkdir(FREE .. '/planted/sessions', 'p')
  assert_true(isdirectory(FREE .. '/victim/sessions'))
  delete(FREE .. '/victim/sessions', 'd')
  delete(FREE .. '/planted')
  assert_true(filereadable(FREE .. '/victim/precious.txt'))
else
  assert_report('no symlinks on this machine: the pre-created-path defence '
    .. 'of PrivateDir() cannot be exercised')
endif

# ---------------------------------------------------------------------------
# AutoRemove(): the fixture does not outlive a run that never finishes.
# ---------------------------------------------------------------------------

const CHILD = FREE .. '/child.vim'
const MARK = FREE .. '/mark.txt'

# A child Vim that builds a fixture, records where it put it, and then dies on
# an uncaught error - the shape of any run that fails before reaching its own
# closing delete().  Returns the directory the child chose.
def AbortingChild(build: list<string>): string
  delete(MARK)
  writefile(['vim9script',
    'import ' .. string(ROOT .. '/tests/fixture.vim') .. ' as fixture']
    + build
    + ['mkdir(temp .. "/deep", "p")',
       'writefile(["x"], temp .. "/deep/file.txt")',
       'writefile([temp], ' .. string(MARK) .. ')',
       'throw "simulated abort"',
       'delete(temp, "rf")',
       'qall!'], CHILD)
  var command = printf('%s -Nu NONE -n -i NONE -es -S %s',
    shellescape(v:progpath), shellescape(CHILD))
  var output = system(command, '')
  assert_true(filereadable(MARK),
    'child Vim recorded no directory: ' .. command .. ' -> ' .. output)
  return filereadable(MARK) ? readfile(MARK)[0] : ''
enddef

var registered = AbortingChild([
  'var temp = fixture.PrivateDir(' .. string(FREE) .. ', "registered")',
  'fixture.AutoRemove(temp)'])
assert_equal(resolve(FREE) .. '/registered', registered)
assert_false(isdirectory(registered),
  'AutoRemove() left ' .. registered .. ' behind after an aborted run')

# The control: the same child without the registration keeps everything, which
# is what the fallback directory used to do on every aborted run.
var unregistered = AbortingChild([
  'var temp = fixture.PrivateDir(' .. string(FREE) .. ', "unregistered")'])
assert_true(isdirectory(unregistered))
assert_true(filereadable(unregistered .. '/deep/file.txt'))
delete(unregistered, 'rf')

# End to end: whatever RepoFreeTemp() picks - Vim's temporary directory or a
# base of its own - an aborted run leaves none of it behind.
var chosen = AbortingChild(['var temp = fixture.RepoFreeTemp()'])
assert_false(isdirectory(chosen),
  'RepoFreeTemp() left ' .. chosen .. ' behind after an aborted run')

delete(FREE, 'rf')
if !empty(v:errors)
  writefile(v:errors, '/dev/stderr')
  cquit 1
endif
qall!
