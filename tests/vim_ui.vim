vim9script

set nocompatible
set nomore
set ambiwidth=double

const ROOT = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
execute 'set runtimepath^=' .. fnameescape(ROOT)

var model = {
  cwd: '/tmp/项目',
  sections: [
    {id: 'files', title: 'recent files', short: 'recent',
      command: 'recent --limit=2', entries: [
      {key: '1', kind: 'file', label: 'README.md', path: '/tmp/README.md'},
      {key: '2', kind: 'file', label: '很长的中文文件名-and-ascii.txt', path: '/tmp/two'},
    ]},
    {id: 'sessions', title: 'sessions', short: 'sessions',
      command: 'session list',
      entries: [{key: 'a', kind: 'session', label: 'work', name: 'work'}]},
    {id: 'bookmarks', title: 'bookmarks', short: 'bookmarks',
      command: 'bookmarks', entries: [
      {key: 'c', kind: 'bookmark', label: '~/.vimrc', path: '/home/u/.vimrc'},
      # No key left in the pool: the entry still renders and is still an
      # action, reachable with the cursor.
      {key: '', kind: 'bookmark', label: '配置目录', path: '/home/u/.config'},
    ]},
    {id: 'commands', title: 'commands', short: 'commands',
      command: 'commands', entries: [
      {key: 'u', kind: 'command', label: 'update plugins',
        command: 'SimplePlugUpdate'},
    ]},
    {id: 'special', title: 'actions', short: 'actions',
      command: 'help --actions', entries: [
      {key: 'n', kind: 'new', label: 'new empty buffer'},
      {key: 'r', kind: 'restyle', label: 'roll another UI style'},
      {key: 'q', kind: 'quit', label: 'quit'},
    ]},
  ],
  footer: ['<Enter> open'],
}

for style in simplestartify#ui#Styles()
  for width in [20, 28, 40, 80, 120]
    var layout = simplestartify#ui#Build(model, style, width)
    assert_false(empty(layout.lines), style)
    assert_equal(9, len(layout.actions), style)
    assert_true(has_key(layout.actions, string(layout.cursor)), style)
    for line_text in layout.lines
      assert_true(strdisplaywidth(line_text) <= width,
        $'{style}/{width}: {string(line_text)}')
      assert_notmatch('\s\+$', line_text, style)
    endfor
    # Every configured section reaches the screen, under the name the style
    # addresses it by: the spelled-out title, the short frame-safe form, or
    # the shell-transcript command.
    if width >= 80
      var rendered = join(layout.lines, "\n")
      for section in model.sections
        var expected = style ==# 'terminal' ? section.command
              : toupper(style ==# 'minimal' ? section.title : section.short)
        assert_true(stridx(rendered, expected) >= 0,
          $'{style}: {expected} is missing from the layout')
      endfor
    endif
  endfor
endfor

# A keyless entry keeps the marker column's width so labels stay aligned, and
# is never given a fabricated "[?]" shortcut.
var aligned = simplestartify#ui#Build(model, 'minimal', 80)
assert_notmatch('\[?\]', join(aligned.lines, "\n"))
var keyless = filter(copy(aligned.lines), (_, text) => stridx(text, '配置目录') >= 0)
assert_equal(1, len(keyless))
assert_match('^ \+配置目录$', keyless[0])

# An empty section list renders nothing selectable rather than throwing, and a
# footer given as a bare string still renders.
var bare = simplestartify#ui#Build({cwd: '/tmp', sections: [], footer: 'x'},
  'boxed', 40)
assert_equal({}, bare.actions)
assert_equal(1, bare.cursor)
assert_match('x', join(bare.lines, "\n"))

# A custom header replaces each layout's built-in banner, in that layout's own
# house style, and a multi-line footer keeps the same width guarantees.
var branded = extend(copy(model), {
  header: ['MY VIM', '很长的中文标题-and-ascii'],
  footer: ['line one', 'line two'],
})
for style in simplestartify#ui#Styles()
  for width in [20, 28, 40, 80, 120]
    var layout = simplestartify#ui#Build(branded, style, width)
    var rendered = join(layout.lines, "\n")
    assert_equal(9, len(layout.actions), style)
    assert_equal(2, len(layout.footer_lines)
      + (style ==# 'boxed' ? -2 : 0), $'{style}/{width}')
    for line_text in layout.lines
      assert_true(strdisplaywidth(line_text) <= width,
        $'{style}/{width}: {string(line_text)}')
      assert_notmatch('\s\+$', line_text, style)
    endfor
    if width >= 80
      assert_match('MY VIM', rendered, style)
      assert_match('line two', rendered, style)
      # The built-in banner is gone, not merely pushed down.
      assert_notmatch('SIMPLESTARTIFY', rendered, style)
      assert_notmatch('STARTIFY', rendered, style)
    endif
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
