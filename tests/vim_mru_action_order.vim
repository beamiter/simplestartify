vim9script

# Gate real Vim children after their event and before VimLeavePre. The older
# action deliberately writes *last*. A separate fresh Vim checks the actual
# dashboard, not just the on-disk order record.
set nocompatible nomore hidden
set viminfo='100,<50,s10,h

const ROOT = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
const SCRIPT = resolve(expand('<sfile>:p'))

def WaitFor(Check: func(): bool, phase: string)
  var start = reltime()
  while !Check()
    if reltimefloat(reltime(start)) > 8.0
      throw 'MRU action-order fixture timed out: ' .. phase
    endif
    sleep 5m
  endwhile
enddef

def Dashboard(): list<string>
  execute 'SimpleStartify minimal'
  var out: list<string> = []
  var actions = get(b:, 'simplestartify_actions', {})
  for key in sort(keys(actions), 'n')
    if get(actions[key], 'kind', '') ==# 'file'
      add(out, actions[key].path)
    endif
  endfor
  # Minimal mode displays a file in more than one section. Compare the
  # first occurrence of every path in display order.
  var seen: dict<bool> = {}
  return filter(out, (_, path) => {
    if has_key(seen, path)
      return false
    endif
    seen[path] = true
    return true
  })
enddef

def Child(root: string, role: string)
  const alpha = root .. '/alpha.txt'
  const beta = root .. '/beta.txt'
  const gamma = root .. '/gamma.txt'
  g:simplestartify_auto_open = 0
  g:simplestartify_session_dir = root .. '/sessions'
  g:simplestartify_mru_file = root .. '/mru'
  g:simplestartify_mru_max = role ==# 'cap-one' || role ==# 'gamma-one' ? 1 : (role ==# 'cap-zero' ? 0 : 3)
  execute 'set runtimepath^=' .. fnameescape(ROOT)
  execute 'source ' .. fnameescape(ROOT .. '/plugin/simplestartify.vim')

  if role ==# 'guard-controls'
    var lock = root .. '/mru.order.lock'
    var order = root .. '/mru.order'
    var initial = readfile(order)
    mkdir(lock, '', 0o700)
    var newfile = root .. '/first-save.txt'
    execute 'edit ' .. fnameescape(newfile)
    assert_false(index(simplestartify#mru#List(), newfile) >= 0, 'unwritten file does not enter MRU')
    setline(1, 'first write')
    write
    assert_equal(newfile, simplestartify#mru#List()[0], 'BufWritePost still records the first save')
    assert_false(simplestartify#mru#Save(), 'existing lock is not stolen')
    assert_true(isdirectory(lock))
    assert_equal(initial, readfile(order), 'busy writer did not replace order file')
    delete(lock, 'd')
    writefile(['unknown format'], order)
    assert_false(simplestartify#mru#Save(), 'unrecognized sidecar is not overwritten')
    assert_equal(['unknown format'], readfile(order))
    writefile(initial, order)
    assert_true(simplestartify#mru#Save(), 'pending visit survives both denied writes')
    assert_equal(newfile, simplestartify#mru#List()[0])
    return
  endif
  if role ==# 'seed'
    execute 'edit ' .. fnameescape(beta)
    execute 'edit ' .. fnameescape(alpha)
    return
  endif
  if role ==# 'verify-reopen'
    assert_equal([], v:oldfiles, 'native history is disabled')
    assert_equal([alpha, beta], simplestartify#mru#List())
    assert_equal([alpha, beta], Dashboard())
    return
  elseif role ==# 'verify-forget'
    assert_true(index(v:oldfiles, alpha) >= 0, 'native Vim loaded alpha from a real history')
    assert_equal([beta], simplestartify#mru#List())
    assert_equal([beta], Dashboard())
    assert_true(index(v:oldfiles, alpha) >= 0, 'dashboard leaves native history intact')
    return
  elseif role ==# 'cap-one'
    assert_equal([gamma], simplestartify#mru#List())
    assert_equal([gamma], Dashboard())
    return
  elseif role ==# 'cap-zero'
    assert_equal([], simplestartify#mru#List())
    assert_equal([], Dashboard())
    return
  elseif role ==# 'verify-overlap'
    assert_equal(sort([alpha, beta, gamma]), sort(simplestartify#mru#List()))
    return
  endif
  if role ==# 'native-forget' || role ==# 'older-forget' || role ==# 'newer-forget'
    execute 'SimpleStartifyForget ' .. fnameescape(alpha)
    assert_equal([beta], simplestartify#mru#List(), 'forget must apply immediately')
  elseif role ==# 'overlap-beta'
    execute 'edit ' .. fnameescape(beta)
  elseif role ==# 'overlap-gamma' || role ==# 'gamma-one'
    execute 'edit ' .. fnameescape(gamma)
  else
    execute 'edit ' .. fnameescape(alpha)
  endif
  writefile([string(localtime())], root .. '/action-' .. role)
  if role =~# '^\%(older-\|overlap-\)'
    WaitFor(() => filereadable(root .. '/release'), role .. ' release')
  endif
enddef

if !empty($STARTIFY_ORDER_ROLE)
  try
    Child($STARTIFY_ORDER_ROOT, $STARTIFY_ORDER_ROLE)
  catch
    assert_report(v:exception .. ' (' .. v:throwpoint .. ')')
  endtry
  if !empty(v:errors)
    writefile(v:errors, '/dev/stderr')
    cquit 1
  endif
  qall!
endif

def Start(root: string, role: string, history: bool = false): job
  var child = job_start([v:progpath, '-Nu', 'NONE', '-n', '-i',
    history ? root .. '/viminfo' : 'NONE', '-es', '-S', SCRIPT], {
    env: {STARTIFY_ORDER_ROOT: root, STARTIFY_ORDER_ROLE: role},
    out_io: 'null', err_io: 'file', err_name: root .. '/log-' .. role,
  })
  assert_notequal('fail', job_status(child), role .. ' start')
  return child
enddef

def Finish(root: string, role: string, child: job)
  WaitFor(() => job_status(child) !=# 'run', role .. ' exit')
  assert_equal(0, job_info(child).exitval,
    role .. ': ' .. join(readfile(root .. '/log-' .. role), "\n"))
enddef

def Ready(root: string, role: string, child: job)
  WaitFor(() => filereadable(root .. '/action-' .. role) || job_status(child) !=# 'run',
    role .. ' action')
  if !filereadable(root .. '/action-' .. role)
    Finish(root, role, child)
    throw role .. ' did not perform its action'
  endif
enddef

def Setup(): string
  var root = tempname()
  mkdir(root, '', 0o700)
  for file in ['alpha', 'beta', 'gamma']
    writefile([file], root .. '/' .. file .. '.txt')
  endfor
  Finish(root, 'seed', Start(root, 'seed', true))
  return root
enddef

def Stop(child: job)
  if job_status(child) ==# 'run'
    job_stop(child)
    WaitFor(() => job_status(child) !=# 'run', 'cleanup')
  endif
enddef

def ReverseExit(older: string, newer: string, check: string)
  var root = Setup()
  # Start immediately after a second tick, keeping the ordered actions in the
  # same legacy epoch second. The closeout case cannot pass on seconds alone.
  var second = localtime()
  WaitFor(() => localtime() != second, 'test clock tick')
  var held = Start(root, older)
  try
    Ready(root, older, held)
    Finish(root, newer, Start(root, newer))
    assert_equal(readfile(root .. '/action-' .. older), readfile(root .. '/action-' .. newer),
      'fixture must exercise same-second actions, not timestamp-separated shortcuts')
    writefile([], root .. '/release')
    Finish(root, older, held)
    Finish(root, check, Start(root, check, check ==# 'verify-forget'))
    if check ==# 'verify-reopen'
      Finish(root, 'gamma-one', Start(root, 'gamma-one'))
      assert_equal(readfile(root .. '/action-' .. newer), readfile(root .. '/action-gamma-one'),
        'a later ordinary visit must outrank the same-second revival')
      Finish(root, 'cap-one', Start(root, 'cap-one'))
      Finish(root, 'cap-zero', Start(root, 'cap-zero'))
    else
      var order = root .. '/mru.order'
      assert_true(filereadable(order), 'persistent Forget must have a separate record')
      if filereadable(order)
        assert_notmatch('\V' .. escape(root .. '/alpha.txt', '\'), join(readfile(order), "\n"),
          'forget leaves only a hashed suppression key, not the plaintext path')
      endif
    endif
  finally
    Stop(held)
    delete(root, 'rf')
  endtry
enddef

def Overlap()
  var root = Setup()
  var first = Start(root, 'overlap-beta')
  var second = Start(root, 'overlap-gamma')
  try
    Ready(root, 'overlap-beta', first)
    Ready(root, 'overlap-gamma', second)
    var lock = root .. '/mru.order.lock'
    mkdir(lock, '', 0o700)
    writefile([], root .. '/release')
    sleep 30m
    assert_equal('run', job_status(first), 'first writer must wait outside the held lock')
    assert_equal('run', job_status(second), 'second writer must wait outside the held lock')
    assert_equal(0, delete(lock, 'd'))
    Finish(root, 'overlap-beta', first)
    Finish(root, 'overlap-gamma', second)
    Finish(root, 'verify-overlap', Start(root, 'verify-overlap'))
  finally
    Stop(first)
    Stop(second)
    delete(root, 'rf')
  endtry
enddef

try
  ReverseExit('older-visit', 'newer-forget', 'verify-forget')
  ReverseExit('older-forget', 'newer-visit', 'verify-reopen')
  Overlap()
  var guard_root = Setup()
  try
    Finish(guard_root, 'guard-controls', Start(guard_root, 'guard-controls'))
  finally
    delete(guard_root, 'rf')
  endtry
catch
  assert_report(v:exception .. ' (' .. v:throwpoint .. ')')
endtry
if !empty(v:errors)
  writefile(v:errors, '/dev/stderr')
  cquit 1
endif
qall!
