vim9script

set nocompatible
set nomore
set ambiwidth=double

const ROOT = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
execute 'set runtimepath^=' .. fnameescape(ROOT)

var model = {
  cwd: '/tmp/项目',
  recent: [
    {key: '1', kind: 'file', label: 'README.md', path: '/tmp/README.md'},
    {key: '2', kind: 'file', label: '很长的中文文件名-and-ascii.txt', path: '/tmp/two'},
  ],
  sessions: [{key: 'a', kind: 'session', label: 'work', name: 'work'}],
  special: [
    {key: 'n', kind: 'new', label: 'new empty buffer'},
    {key: 'r', kind: 'restyle', label: 'roll another UI style'},
    {key: 'q', kind: 'quit', label: 'quit'},
  ],
  footer: '<Enter> open',
}

for style in simplestartify#ui#Styles()
  for width in [20, 28, 40, 80, 120]
    var layout = simplestartify#ui#Build(model, style, width)
    assert_false(empty(layout.lines), style)
    assert_equal(6, len(layout.actions), style)
    assert_true(has_key(layout.actions, string(layout.cursor)), style)
    for line_text in layout.lines
      assert_true(strdisplaywidth(line_text) <= width,
        $'{style}/{width}: {string(line_text)}')
      assert_notmatch('\s\+$', line_text, style)
    endfor
  endfor
endfor

var candidates = ['minimal', 'boxed', 'terminal']
assert_equal('boxed', simplestartify#ui#PickStyle(candidates, 'minimal', 0))
assert_equal('terminal', simplestartify#ui#PickStyle(candidates, 'minimal', 1))
assert_equal('minimal', simplestartify#ui#PickStyle(['minimal'], 'minimal', 7))
assert_equal('minimal', simplestartify#ui#PickStyle([], '', 9))
assert_equal(['minimal'], simplestartify#ui#Candidates(['boxed'], 20))
assert_equal('ab…', simplestartify#ui#Fit('abcdef', 4))

if !empty(v:errors)
  writefile(v:errors, '/dev/stderr')
  cquit 1
endif
qall!
