vim9script

# Keep Vim's own recently used files intact. These two real Vim invocations
# share a disposable viminfo, not the runner's history.
set nocompatible
set nomore
set hidden
set viminfo='100,<50,s10,h

const ROOT = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
const SCRIPT = resolve(expand('<sfile>:p'))

def Recent(): list<string>
  execute 'SimpleStartify minimal'
  return mapnew(filter(values(get(b:, 'simplestartify_actions', {})),
    (_, item) => get(item, 'kind', '') ==# 'file'), (_, item) => item.path)
enddef

def Child(root: string, mode: string)
  const alpha = root .. '/alpha.txt'
  const beta = root .. '/beta.txt'
  g:simplestartify_auto_open = 0
  g:simplestartify_session_dir = root .. '/sessions'
  g:simplestartify_mru_file = root .. '/mru'
  g:simplestartify_mru_persist = 0
  execute 'set runtimepath^=' .. fnameescape(ROOT)
  execute 'source ' .. fnameescape(ROOT .. '/plugin/simplestartify.vim')
  if mode ==# 'seed'
    execute 'edit ' .. fnameescape(alpha)
    execute 'edit ' .. fnameescape(beta)
    return
  endif

  var native = copy(v:oldfiles)
  assert_true(index(native, alpha) >= 0, 'Vim actually loaded alpha from viminfo')
  assert_true(index(native, beta) >= 0, 'Vim actually loaded beta from viminfo')
  assert_equal([], simplestartify#mru#List(), 'no plugin MRU before browsing history')
  assert_true(index(Recent(), alpha) >= 0, 'alpha is a native fallback')
  execute 'SimpleStartifyForget ' .. fnameescape(alpha)
  var after = Recent()
  assert_equal(-1, index(after, alpha), 'forget hides the native fallback here')
  assert_true(index(after, beta) >= 0, 'unrelated native fallback stays')
  assert_equal(native, v:oldfiles, 'Forget does not change native Vim history')
  assert_false(simplestartify#mru#Forget(alpha), 'already hidden entry is not forgotten twice')

  # A real open clears this session's suppression, even when the plugin
  # MRU is capped at zero, so it cannot supply the visible entry itself.
  g:simplestartify_mru_max = 0
  execute 'edit ' .. fnameescape(alpha)
  assert_equal([], simplestartify#mru#List(), 'zero-cap revisit is native fallback only')
  assert_true(index(Recent(), alpha) >= 0, 'a genuine revisit restores the native fallback')
  assert_equal(native, v:oldfiles)
enddef

if !empty($SIMPLESTARTIFY_HISTORY_MODE)
  try
    Child($SIMPLESTARTIFY_HISTORY_DIR, $SIMPLESTARTIFY_HISTORY_MODE)
  catch
    assert_report(v:exception .. ' (' .. v:throwpoint .. ')')
  endtry
  if !empty(v:errors)
    writefile(v:errors, '/dev/stderr')
    cquit 1
  endif
  qall!
endif

const TMP = tempname()
mkdir(TMP, '', 0o700)
writefile(['alpha'], TMP .. '/alpha.txt')
writefile(['beta'], TMP .. '/beta.txt')
try
  for mode in ['seed', 'check']
    var log = TMP .. '/child.log'
    var child = job_start([v:progpath, '-Nu', 'NONE', '-n', '-i', TMP .. '/history',
        '-es', '-S', SCRIPT], {
        env: {SIMPLESTARTIFY_HISTORY_MODE: mode, SIMPLESTARTIFY_HISTORY_DIR: TMP},
        out_io: 'null', err_io: 'file', err_name: log,
      })
    var start = reltime()
    while job_status(child) ==# 'run' && reltimefloat(reltime(start)) < 5.0
      sleep 10m
    endwhile
    if job_status(child) ==# 'run'
      job_stop(child)
      throw 'native history fixture child timed out: ' .. mode
    endif
    assert_equal('dead', job_status(child), 'child actually ran: ' .. mode)
    assert_equal(0, job_info(child).exitval,
      mode .. ': ' .. (filereadable(log) ? join(readfile(log), "\n") : 'no diagnostic'))
  endfor
finally
  delete(TMP, 'rf')
endtry
if !empty(v:errors)
  writefile(v:errors, '/dev/stderr')
  cquit 1
endif
qall!
