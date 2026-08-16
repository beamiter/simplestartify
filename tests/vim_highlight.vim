vim9script

# The [key] marker has its own documented highlight group.  It used to be
# expressed as a syntax match competing with a whole-line match anchored at
# column 1, which always won on Vim's earlier-start-position rule, so the
# group was documented but provably unreachable.  Assert the real rendered
# state, per style, rather than that the commands were issued.

set nocompatible
set nomore
set hidden

const ROOT = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
const TEMP = tempname()
mkdir(TEMP .. '/sessions', 'p')
writefile([], TEMP .. '/sessions/work')
const NOTE = TEMP .. '/note.txt'
writefile(['hello'], NOTE)

execute 'set runtimepath^=' .. fnameescape(ROOT)
g:simplestartify_auto_open = 0
g:simplestartify_session_dir = TEMP .. '/sessions'
g:simplestartify_mru_persist = 0
execute 'source ' .. fnameescape(ROOT .. '/plugin/simplestartify.vim')
execute 'edit ' .. fnameescape(NOTE)

if !has('textprop')
  # The syntax fallback still has to declare the key marker as "contained"
  # inside the entry match, otherwise the same priority defect returns.
  SimpleStartify minimal
  assert_match('contained', execute('syntax list SimpleStartifyKey'))
  delete(TEMP, 'rf')
  if !empty(v:errors)
    writefile(v:errors, '/dev/stderr')
    cquit 1
  endif
  qall!
endif

def PropsAt(lnum: number, type_name: string): list<dict<any>>
  return filter(prop_list(lnum), (_, prop) => prop.type ==# type_name)
enddef

def Priority(type_name: string): number
  return get(prop_type_get(type_name), 'priority', 0)
enddef

const HEADER_GROUPS = {
  minimal: 'SimpleStartifyHeaderMinimal',
  terminal: 'SimpleStartifyHeaderTerminal',
  blocks: 'SimpleStartifyHeaderBlocks',
  neon: 'SimpleStartifyHeaderNeon',
  retro: 'SimpleStartifyHeaderRetro',
  shadow: 'SimpleStartifyHeaderShadow',
  heavy: 'SimpleStartifyHeaderHeavy',
  sparkle: 'SimpleStartifyHeaderSparkle',
}

for style in simplestartify#ui#Styles()
  execute 'SimpleStartify ' .. style
  var actions = b:simplestartify_actions
  assert_false(empty(actions), style)
  for [lnum_text, action] in items(actions)
    var lnum = str2nr(lnum_text)
    var text = getline(lnum)

    # The whole entry line carries the entry span ...
    var entry = PropsAt(lnum, 'SimpleStartifyEntry')
    assert_equal(1, len(entry), $'{style}: entry prop on line {lnum}')
    assert_equal(1, entry[0].col, style)
    assert_equal(strlen(text), entry[0].length, style)

    # ... and the key marker is a separate, higher-priority span at exactly
    # the column the layout put it in.
    var marker = '[' .. action.key .. ']'
    var offset = stridx(text, marker)
    assert_true(offset >= 0, $'{style}: no marker in {string(text)}')
    var key = PropsAt(lnum, 'SimpleStartifyKey')
    assert_equal(1, len(key), $'{style}: key prop on line {lnum}')
    assert_equal(offset + 1, key[0].col, $'{style}: line {lnum}')
    assert_equal(strlen(marker), key[0].length, style)
  endfor

  # Header, section and footer lines are still distinguishable, and nothing
  # leaks onto a blank line.
  assert_false(empty(PropsAt(1, get(HEADER_GROUPS, style,
    'SimpleStartifyHeader'))), style)
endfor

# The key span is nested inside the entry span, so it has to win on priority
# or the whole exercise is pointless.
assert_true(Priority('SimpleStartifyKey') > Priority('SimpleStartifyEntry'))
assert_equal('SimpleStartifyKey',
  get(prop_type_get('SimpleStartifyKey'), 'highlight', ''))

# An empty section renders its muted placeholder as its own span.
g:simplestartify_recent_count = 0
SimpleStartify minimal
var muted = 0
for lnum in range(1, line('$'))
  muted += len(PropsAt(lnum, 'SimpleStartifyMuted'))
endfor
assert_equal(1, muted)

# Re-rendering must not accumulate stale spans on the same line.
g:simplestartify_recent_count = 7
SimpleStartify minimal
SimpleStartifyRefresh
SimpleStartifyRefresh
for lnum_text in keys(b:simplestartify_actions)
  assert_equal(1, len(PropsAt(str2nr(lnum_text), 'SimpleStartifyEntry')))
  assert_equal(1, len(PropsAt(str2nr(lnum_text), 'SimpleStartifyKey')))
endfor

execute 'lcd ' .. fnameescape(ROOT)
delete(TEMP, 'rf')
if !empty(v:errors)
  writefile(v:errors, '/dev/stderr')
  cquit 1
endif
qall!
