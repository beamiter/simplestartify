vim9script

# The cache normally arrives ordered, but duplicate, hand-edited and
# out-of-order rows must still respect the original sort and dedup rules.
set nomore hidden
const REPO = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
const TMP = tempname()
mkdir(TMP, '', 0o700)
execute 'set runtimepath^=' .. fnameescape(REPO)
g:simplestartify_mru_max = 100

def Paths(names: list<string>): list<string>
  return mapnew(names, (_, name) => TMP .. '/' .. name)
enddef

def Seed(cache: string, rows: list<list<any>>)
  g:simplestartify_mru_file = TMP .. '/' .. cache
  writefile(mapnew(rows, (_, row) => row[0] .. "\t" .. TMP .. '/' .. row[1]), g:simplestartify_mru_file)
enddef

def Check(expected: list<string>, label: string)
  assert_equal(Paths(expected), simplestartify#mru#List(), label)
enddef

def CheckDisk(expected: list<string>)
  assert_true(simplestartify#mru#Save())
  assert_equal(Paths(expected), mapnew(readfile(g:simplestartify_mru_file),
    (_, row) => strpart(row, stridx(row, "\t") + 1)))
enddef

def Visit(name: string)
  var path = TMP .. '/' .. name
  writefile(['text'], path)
  execute 'edit ' .. fnameescape(path)
  simplestartify#mru#Touch()
enddef

try
  var now = localtime()
  Seed('sorted-cache', [[now - 2, 'a'], [now - 2, 'b'], [now - 3, 'c']])
  Check(['a', 'b', 'c'], 'preserve equal-second disk order')
  Visit('b')
  Check(['b', 'a', 'c'], 'existing key moves to front')
  CheckDisk(['b', 'a', 'c'])
  assert_true(simplestartify#mru#Forget(TMP .. '/a'))
  CheckDisk(['b', 'c'])

  Seed('new-key', [[now + 3600, 'future'], [now - 5, 'past']])
  Check(['future', 'past'], 'read second cache')
  Visit('new')
  CheckDisk(['future', 'new', 'past'])

  Seed('unsorted-cache', [[now - 10, 'old'], [now - 2, 'near'], [now - 1, 'latest']])
  Check(['latest', 'near', 'old'], 'do not assume arbitrary disk order')
  Visit('old')
  CheckDisk(['old', 'latest', 'near'])

  Seed('duplicate-cache', [[now - 6, 'dup'], [now - 1, 'middle'],
    [now - 1, 'dup'], [now - 1, 'end'], [now - 7, 'tail']])
  Check(['middle', 'dup', 'end', 'tail'], 'winning duplicate is ordered by its disk position')
  Visit('tail')
  CheckDisk(['tail', 'middle', 'dup', 'end'])

  Seed('batch-cache', [[now - 5, 'a']])
  Check(['a'], 'load before pending batch')
  Visit('b')
  Visit('c')
  CheckDisk(['c', 'b', 'a'])
catch
  assert_report(v:exception .. ': ' .. v:throwpoint)
finally
  delete(TMP, 'rf')
endtry
if !empty(v:errors)
  writefile(v:errors, '/dev/stderr')
  cquit
endif
qall!
