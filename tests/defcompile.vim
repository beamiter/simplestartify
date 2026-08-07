set nocompatible
set nomore

let s:root = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
execute 'set runtimepath^=' .. fnameescape(s:root)

for s:plugin in glob(s:root .. '/plugin/**/*.vim', 0, 1)
  execute 'source ' .. fnameescape(s:plugin)
endfor

let s:errors = []
for s:file in glob(s:root .. '/autoload/**/*.vim', 0, 1)
  let s:temporary = tempname() .. '.vim'
  call writefile(readfile(s:file) + ['defcompile'], s:temporary)
  try
    execute 'source ' .. fnameescape(s:temporary)
  catch
    call add(s:errors, fnamemodify(s:file, ':t') .. ': ' .. v:exception)
  finally
    call delete(s:temporary)
  endtry
endfor

if !empty(s:errors)
  call writefile(s:errors, '/dev/stderr')
  cquit 1
endif
qall!
