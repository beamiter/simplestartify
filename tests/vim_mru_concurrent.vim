vim9script

# Multiple independent VimLeavePre handlers writing one shared cache. Gate the
# real child processes by files instead of sleep-based assumptions about the
# order in which they read or commit. Each scenario uses a distinct cache.
set nocompatible
set nomore
set hidden

const ROOT = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
const SCRIPT = resolve(expand('<sfile>:p'))

def WaitFor(Ready: func(): bool, phase: string)
  var start = reltime()
  while !Ready()
    if reltimefloat(reltime(start)) > 5.0
      throw 'timed out waiting for MRU ' .. phase
    endif
    sleep 10m
  endwhile
enddef

def RunChild(root: string, role: string)
  var alpha = root .. '/alpha.txt'
  var beta = root .. '/beta.txt'
  var cache = root .. '/mru'
  g:simplestartify_auto_open = 0
  g:simplestartify_session_dir = root .. '/sessions'
  g:simplestartify_mru_file = cache
  execute 'set runtimepath^=' .. fnameescape(ROOT)
  execute 'source ' .. fnameescape(ROOT .. '/plugin/simplestartify.vim')

  if role ==# 'open'
    execute 'edit ' .. fnameescape(alpha)
    return
  endif
  assert_equal([alpha], simplestartify#mru#List(), 'initial snapshot: ' .. role)
  if role ==# 'forget' || role ==# 'forget-and-wait'
    execute 'SimpleStartifyForget ' .. fnameescape(alpha)
    assert_equal([], simplestartify#mru#List(), 'forget in this instance')
    if role ==# 'forget'
      return
    endif
    assert_true(simplestartify#mru#Flush(), 'commit forget while staying open')
  elseif role ==# 'visit-and-wait'
    execute 'edit ' .. fnameescape(beta)
  endif
  writefile(['ready'], root .. '/ready')
  WaitFor(() => filereadable(root .. '/release'), 'peer commit')
enddef

if !empty($SIMPLESTARTIFY_TEST_MRU_ROLE)
  try
    RunChild($SIMPLESTARTIFY_TEST_MRU_DIR, $SIMPLESTARTIFY_TEST_MRU_ROLE)
  catch
    assert_report(v:exception .. ' (' .. v:throwpoint .. ')')
  endtry
  if !empty(v:errors)
    writefile(v:errors, '/dev/stderr')
    cquit 1
  endif
  qall!
endif

def StartChild(root: string, role: string): job
  var child = job_start([v:progpath, '-Nu', 'NONE', '-n', '-i', 'NONE', '-es', '-S', SCRIPT], {
    env: {SIMPLESTARTIFY_TEST_MRU_ROLE: role, SIMPLESTARTIFY_TEST_MRU_DIR: root},
    out_io: 'null',
    err_io: 'file',
    err_name: root .. '/' .. role .. '.log',
  })
  assert_notequal('fail', job_status(child), 'start child: ' .. role)
  return child
enddef

def FinishChild(child: job, root: string, role: string)
  WaitFor(() => job_status(child) !=# 'run', role .. ' exit')
  var log = root .. '/' .. role .. '.log'
  assert_equal(0, job_info(child).exitval, role .. ': ' ..
    (filereadable(log) ? join(readfile(log), "\n") : 'no diagnostic'))
enddef

def OnDisk(root: string): list<string>
  return mapnew(readfile(root .. '/mru'), (_, line) =>
    strpart(line, stridx(line, "\t") + 1))
enddef

def TestBetweenInstances(scenario: string, role: string, peer: string,
    retained: list<string>)
  var root = tempname()
  mkdir(root, '', 0o700)
  writefile(['a'], root .. '/alpha.txt')
  writefile(['b'], root .. '/beta.txt')
  var objects: list<job> = []
  try
    add(objects, StartChild(root, 'open'))
    FinishChild(objects[-1], root, 'open')
    assert_equal([root .. '/alpha.txt'], OnDisk(root), 'seed cache')

    add(objects, StartChild(root, role))
    # If the child fails before signalling, surface that error rather than
    # making a sleep or an empty result count as a successful reproduction.
    var held = objects[-1]
    WaitFor(() => filereadable(root .. '/ready') || job_status(held) !=# 'run',
      role .. ' ready')
    if !filereadable(root .. '/ready')
      FinishChild(held, root, role)
      assert_report(role .. ' did not observe the initial state')
      return
    endif
    add(objects, StartChild(root, peer))
    FinishChild(objects[-1], root, peer)
    assert_equal(peer ==# 'forget' ? [] : [root .. '/alpha.txt'], OnDisk(root),
      scenario .. ' (before original quit)')
    writefile([], root .. '/release')
    FinishChild(held, root, role)
    assert_equal(mapnew(retained, (_, name) => root .. '/' .. name), OnDisk(root),
      scenario .. ' (after original quit)')
  finally
    for child in objects
      if job_status(child) ==# 'run'
        job_stop(child)
        WaitFor(() => job_status(child) !=# 'run', 'fixture cleanup')
      endif
    endfor
    delete(root, 'rf')
  endtry
enddef

TestBetweenInstances('an idle observer cannot restore a sibling Forget',
  'observe-and-wait', 'forget', [])
TestBetweenInstances('saving an unrelated visit cannot restore a sibling Forget',
  'visit-and-wait', 'forget', ['beta.txt'])
TestBetweenInstances('a committed Forget cannot erase a later genuine visit',
  'forget-and-wait', 'open', ['alpha.txt'])

if !empty(v:errors)
  writefile(v:errors, '/dev/stderr')
  cquit 1
endif
qall!
