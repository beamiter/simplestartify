vim9script

# Pure layout helpers for SimpleStartify.  This file deliberately knows
# nothing about buffers or commands: a model goes in and renderable lines plus
# line-to-action metadata come out.  Keeping randomness outside the renderer
# makes every layout deterministic and straightforward to test.

const STYLE_ORDER = ['minimal', 'boxed', 'centered', 'terminal']
const STYLE_MIN_WIDTH = {
  minimal: 16,
  boxed: 28,
  centered: 24,
  terminal: 22,
}

def DisplaySlice(text: string, width: number): string
  if width <= 0
    return ''
  endif
  var out = ''
  var index = 0
  while index < strchars(text)
    var char = strcharpart(text, index, 1)
    if strdisplaywidth(out .. char) > width
      break
    endif
    out ..= char
    index += 1
  endwhile
  return out
enddef

export def Fit(text: string, width: number): string
  if width <= 0
    return ''
  endif
  var clean = substitute(text, '[\r\n\t]', ' ', 'g')
  clean = substitute(clean, '\s\+$', '', '')
  if strdisplaywidth(clean) <= width
    return clean
  endif
  var ellipsis = '…'
  var ellipsis_width = strdisplaywidth(ellipsis)
  if width <= ellipsis_width
    return DisplaySlice(clean, width)
  endif
  return DisplaySlice(clean, width - ellipsis_width) .. ellipsis
enddef

def Center(text: string, width: number): string
  var fitted = Fit(text, width)
  var padding = max([0, (width - strdisplaywidth(fitted)) / 2])
  return repeat(' ', padding) .. fitted
enddef

def BoxRow(text: string, inner_width: number): string
  var fitted = Fit(text, inner_width)
  return '| ' .. fitted
        \ .. repeat(' ', max([0, inner_width - strdisplaywidth(fitted)]))
        \ .. ' |'
enddef

def Add(lines: list<string>, text: string, width: number): number
  add(lines, Fit(text, width))
  return len(lines)
enddef

def AddAction(
    lines: list<string>,
    actions: dict<any>,
    entry_lines: list<number>,
    text: string,
    entry: dict<any>,
    width: number): number
  var lnum = Add(lines, text, width)
  actions[string(lnum)] = copy(entry)
  add(entry_lines, lnum)
  return lnum
enddef

def Entries(model: dict<any>, name: string): list<dict<any>>
  var value = get(model, name, [])
  if type(value) != v:t_list
    return []
  endif
  return value
enddef

def Label(entry: dict<any>): string
  var key = get(entry, 'key', '?')
  var label = get(entry, 'label', '')
  return $'[{key}]  {label}'
enddef

def AddMinimalSection(
    lines: list<string>,
    actions: dict<any>,
    section_lines: list<number>,
    entry_lines: list<number>,
    title: string,
    entries: list<dict<any>>,
    width: number)
  add(section_lines, Add(lines, '  ' .. toupper(title), width))
  if empty(entries)
    Add(lines, '    (none yet)', width)
  else
    for entry in entries
      AddAction(lines, actions, entry_lines, '    ' .. Label(entry), entry, width)
    endfor
  endif
  Add(lines, '', width)
enddef

def BuildMinimal(model: dict<any>, width: number): dict<any>
  var lines: list<string> = []
  var actions: dict<any> = {}
  var header_lines: list<number> = []
  var section_lines: list<number> = []
  var entry_lines: list<number> = []
  var footer_lines: list<number> = []

  add(header_lines, Add(lines, 'SIMPLESTARTIFY', width))
  add(header_lines, Add(lines, 'a small, quick way into Vim', width))
  Add(lines, '', width)
  AddMinimalSection(lines, actions, section_lines, entry_lines,
    'recent files', Entries(model, 'recent'), width)
  AddMinimalSection(lines, actions, section_lines, entry_lines,
    'sessions', Entries(model, 'sessions'), width)
  AddMinimalSection(lines, actions, section_lines, entry_lines,
    'actions', Entries(model, 'special'), width)
  add(footer_lines, Add(lines, get(model, 'footer', ''), width))

  return {
    lines: lines,
    actions: actions,
    cursor: empty(entry_lines) ? 1 : entry_lines[0],
    header_lines: header_lines,
    section_lines: section_lines,
    entry_lines: entry_lines,
    footer_lines: footer_lines,
  }
enddef

def AddBoxedSection(
    lines: list<string>,
    actions: dict<any>,
    section_lines: list<number>,
    entry_lines: list<number>,
    title: string,
    entries: list<dict<any>>,
    inner: number,
    width: number)
  add(section_lines, Add(lines, BoxRow('-- ' .. toupper(title) .. ' --', inner), width))
  if empty(entries)
    Add(lines, BoxRow('  (none yet)', inner), width)
  else
    for entry in entries
      AddAction(lines, actions, entry_lines,
        BoxRow('  ' .. Label(entry), inner), entry, width)
    endfor
  endif
enddef

def BuildBoxed(model: dict<any>, width: number): dict<any>
  var lines: list<string> = []
  var actions: dict<any> = {}
  var header_lines: list<number> = []
  var section_lines: list<number> = []
  var entry_lines: list<number> = []
  var footer_lines: list<number> = []
  var box_width = min([74, max([12, width])])
  var inner = max([1, box_width - 4])
  var edge = '+' .. repeat('-', inner + 2) .. '+'

  add(header_lines, Add(lines, edge, width))
  add(header_lines, Add(lines, BoxRow('SIMPLESTARTIFY // RANDOM DECK', inner), width))
  add(header_lines, Add(lines, edge, width))
  AddBoxedSection(lines, actions, section_lines, entry_lines,
    'recent', Entries(model, 'recent'), inner, width)
  Add(lines, BoxRow('', inner), width)
  AddBoxedSection(lines, actions, section_lines, entry_lines,
    'sessions', Entries(model, 'sessions'), inner, width)
  Add(lines, BoxRow('', inner), width)
  AddBoxedSection(lines, actions, section_lines, entry_lines,
    'actions', Entries(model, 'special'), inner, width)
  add(footer_lines, Add(lines, edge, width))
  add(footer_lines, Add(lines, BoxRow(get(model, 'footer', ''), inner), width))
  add(footer_lines, Add(lines, edge, width))

  return {
    lines: lines,
    actions: actions,
    cursor: empty(entry_lines) ? 1 : entry_lines[0],
    header_lines: header_lines,
    section_lines: section_lines,
    entry_lines: entry_lines,
    footer_lines: footer_lines,
  }
enddef

def AddCenteredSection(
    lines: list<string>,
    actions: dict<any>,
    section_lines: list<number>,
    entry_lines: list<number>,
    title: string,
    entries: list<dict<any>>,
    width: number)
  add(section_lines, Add(lines, Center('-- ' .. title .. ' --', width), width))
  if empty(entries)
    Add(lines, Center('(none yet)', width), width)
  else
    for entry in entries
      AddAction(lines, actions, entry_lines,
        Center(Label(entry), width), entry, width)
    endfor
  endif
  Add(lines, '', width)
enddef

def BuildCentered(model: dict<any>, width: number): dict<any>
  var lines: list<string> = []
  var actions: dict<any> = {}
  var header_lines: list<number> = []
  var section_lines: list<number> = []
  var entry_lines: list<number> = []
  var footer_lines: list<number> = []

  for text in [' ____  _                 _',
      '/ ___|(_)_ __ ___  _ __ | | ___',
      '\___ \| | ''_ ` _ \| ''_ \| |/ _ \',
      ' ___) | | | | | | | |_) | |  __/',
      '|____/|_|_| |_| |_| .__/|_|\___|',
      '                  |_|  STARTIFY']
    add(header_lines, Add(lines, Center(text, width), width))
  endfor
  Add(lines, '', width)
  AddCenteredSection(lines, actions, section_lines, entry_lines,
    'RECENT', Entries(model, 'recent'), width)
  AddCenteredSection(lines, actions, section_lines, entry_lines,
    'SESSIONS', Entries(model, 'sessions'), width)
  AddCenteredSection(lines, actions, section_lines, entry_lines,
    'ACTIONS', Entries(model, 'special'), width)
  add(footer_lines, Add(lines, Center(get(model, 'footer', ''), width), width))

  return {
    lines: lines,
    actions: actions,
    cursor: empty(entry_lines) ? 1 : entry_lines[0],
    header_lines: header_lines,
    section_lines: section_lines,
    entry_lines: entry_lines,
    footer_lines: footer_lines,
  }
enddef

def AddTerminalSection(
    lines: list<string>,
    actions: dict<any>,
    section_lines: list<number>,
    entry_lines: list<number>,
    command: string,
    entries: list<dict<any>>,
    width: number)
  add(section_lines, Add(lines, '$ ' .. command, width))
  if empty(entries)
    Add(lines, '  -> (none yet)', width)
  else
    for entry in entries
      AddAction(lines, actions, entry_lines,
        '  -> ' .. Label(entry), entry, width)
    endfor
  endif
  Add(lines, '', width)
enddef

def BuildTerminal(model: dict<any>, width: number): dict<any>
  var lines: list<string> = []
  var actions: dict<any> = {}
  var header_lines: list<number> = []
  var section_lines: list<number> = []
  var entry_lines: list<number> = []
  var footer_lines: list<number> = []

  add(header_lines, Add(lines, '$ simplestartify --style=random', width))
  add(header_lines, Add(lines, 'boot: ready // cwd: ' .. get(model, 'cwd', ''), width))
  Add(lines, '', width)
  AddTerminalSection(lines, actions, section_lines, entry_lines,
    'recent --limit=' .. len(Entries(model, 'recent')),
    Entries(model, 'recent'), width)
  AddTerminalSection(lines, actions, section_lines, entry_lines,
    'session list', Entries(model, 'sessions'), width)
  AddTerminalSection(lines, actions, section_lines, entry_lines,
    'help --actions', Entries(model, 'special'), width)
  add(footer_lines, Add(lines, '# ' .. get(model, 'footer', ''), width))

  return {
    lines: lines,
    actions: actions,
    cursor: empty(entry_lines) ? 1 : entry_lines[0],
    header_lines: header_lines,
    section_lines: section_lines,
    entry_lines: entry_lines,
    footer_lines: footer_lines,
  }
enddef

export def Styles(): list<string>
  return copy(STYLE_ORDER)
enddef

export def Candidates(configured: any, width: number): list<string>
  var requested: list<any> = type(configured) == v:t_list
        \ ? configured
        \ : copy(STYLE_ORDER)
  var out: list<string> = []
  for style in requested
    if type(style) == v:t_string
          \ && index(STYLE_ORDER, style) >= 0
          \ && width >= get(STYLE_MIN_WIDTH, style, 1)
          \ && index(out, style) < 0
      add(out, style)
    endif
  endfor
  return empty(out) ? ['minimal'] : out
enddef

export def PickStyle(
    candidates: list<string>,
    previous: string,
    random_value: number,
    avoid_repeat: bool = true): string
  var pool = empty(candidates) ? ['minimal'] : copy(candidates)
  if avoid_repeat && len(pool) > 1
    filter(pool, (_, style) => style !=# previous)
  endif
  if empty(pool)
    return 'minimal'
  endif
  var index = random_value % len(pool)
  if index < 0
    index += len(pool)
  endif
  return pool[index]
enddef

export def Build(model: dict<any>, style: string, width: number): dict<any>
  var safe_width = max([1, width])
  if style ==# 'boxed'
    return BuildBoxed(model, safe_width)
  elseif style ==# 'centered'
    return BuildCentered(model, safe_width)
  elseif style ==# 'terminal'
    return BuildTerminal(model, safe_width)
  endif
  return BuildMinimal(model, safe_width)
enddef
