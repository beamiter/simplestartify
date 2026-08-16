vim9script

# Pure layout helpers for SimpleStartify.  This file deliberately knows
# nothing about buffers or commands: a model goes in and renderable lines plus
# line-to-action metadata come out.  Keeping randomness outside the renderer
# makes every layout deterministic and straightforward to test.

const STYLE_ORDER = ['minimal', 'terminal', 'blocks', 'neon', 'retro',
  'shadow', 'heavy', 'sparkle']
const STYLE_MIN_WIDTH = {
  minimal: 16,
  terminal: 22,
  blocks: 33,
  neon: 25,
  retro: 28,
  shadow: 34,
  heavy: 25,
  sparkle: 24,
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

def Entries(section: dict<any>): list<dict<any>>
  var value = get(section, 'entries', [])
  if type(value) != v:t_list
    return []
  endif
  return value
enddef

# The model is a list of sections rather than three fixed keys, so a layout
# renders whatever the user configured without knowing what any of it means.
def Sections(model: dict<any>): list<dict<any>>
  var value = get(model, 'sections', [])
  if type(value) != v:t_list
    return []
  endif
  return filter(copy(value), (_, section) => type(section) == v:t_dict)
enddef

# Header and footer are lists of plain text, and each layout renders them in
# its own house style rather than taking them verbatim - that is what keeps a
# user's banner recognisable whichever way the deck falls.
def TextLines(model: dict<any>, field: string): list<string>
  var value = get(model, field, [])
  if type(value) == v:t_string
    return empty(value) ? [] : [value]
  endif
  if type(value) != v:t_list
    return []
  endif
  return filter(copy(value), (_, line) => type(line) == v:t_string)
enddef

def Name(section: dict<any>, field: string): string
  var value = get(section, field, get(section, 'title', ''))
  return type(value) == v:t_string ? value : ''
enddef

def Label(entry: dict<any>): string
  var key = get(entry, 'key', '')
  var label = get(entry, 'label', '')
  # More entries than shortcut letters is a legitimate state: such an entry
  # keeps the marker's width so the column stays aligned, and is opened with
  # the cursor instead.
  return type(key) == v:t_string && !empty(key)
        \ ? $'[{key}]  {label}'
        \ : $'     {label}'
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

  var custom = TextLines(model, 'header')
  for text in empty(custom)
      ? ['SIMPLESTARTIFY', 'a small, quick way into Vim']
      : custom
    add(header_lines, Add(lines, text, width))
  endfor
  Add(lines, '', width)
  for section in Sections(model)
    AddMinimalSection(lines, actions, section_lines, entry_lines,
      Name(section, 'title'), Entries(section), width)
  endfor
  for text in TextLines(model, 'footer')
    add(footer_lines, Add(lines, text, width))
  endfor

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

  var custom = TextLines(model, 'header')
  if empty(custom)
    add(header_lines, Add(lines, '$ simplestartify --style=random', width))
    add(header_lines, Add(lines, 'boot: ready // cwd: ' .. get(model, 'cwd', ''), width))
  else
    for text in custom
      add(header_lines, Add(lines, '# ' .. text, width))
    endfor
  endif
  Add(lines, '', width)
  for section in Sections(model)
    AddTerminalSection(lines, actions, section_lines, entry_lines,
      Name(section, 'command'), Entries(section), width)
  endfor
  for text in TextLines(model, 'footer')
    add(footer_lines, Add(lines, '# ' .. text, width))
  endfor

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

# ─────────────────── blocks: 像素块横幅 ───────────────────

# 3x5 的像素字体，只收了拼出横幅需要的那几个字母。行的尾巴交给 Fit()
# 修剪，所以字形里的留白直接写成空格。
const PIXEL_FONT = {
  S: ['███', '█  ', '███', '  █', '███'],
  T: ['███', ' █ ', ' █ ', ' █ ', ' █ '],
  A: [' █ ', '█ █', '███', '█ █', '█ █'],
  R: ['██ ', '█ █', '██ ', '█ █', '█ █'],
  I: ['███', ' █ ', ' █ ', ' █ ', '███'],
  F: ['███', '█  ', '██ ', '█  ', '█  '],
  Y: ['█ █', '█ █', ' █ ', ' █ ', ' █ '],
}

def PixelBanner(word: string): list<string>
  var rows = ['', '', '', '', '']
  for letter in split(toupper(word), '\zs')
    var glyph = get(PIXEL_FONT, letter, [])
    if empty(glyph)
      continue
    endif
    for i in range(5)
      rows[i] ..= (empty(rows[i]) ? '' : ' ') .. glyph[i]
    endfor
  endfor
  return rows
enddef

def AddBlocksSection(
    lines: list<string>,
    actions: dict<any>,
    section_lines: list<number>,
    entry_lines: list<number>,
    title: string,
    entries: list<dict<any>>,
    width: number)
  add(section_lines, Add(lines, '  ▌' .. toupper(title), width))
  if empty(entries)
    Add(lines, '    (none yet)', width)
  else
    for entry in entries
      AddAction(lines, actions, entry_lines, '  ▪ ' .. Label(entry), entry, width)
    endfor
  endif
  Add(lines, '', width)
enddef

def BuildBlocks(model: dict<any>, width: number): dict<any>
  var lines: list<string> = []
  var actions: dict<any> = {}
  var header_lines: list<number> = []
  var section_lines: list<number> = []
  var entry_lines: list<number> = []
  var footer_lines: list<number> = []

  var custom = TextLines(model, 'header')
  if empty(custom)
    for art in PixelBanner('STARTIFY')
      add(header_lines, Add(lines, Center(art, width), width))
    endfor
    add(header_lines, Add(lines, Center('· a small, quick way into Vim ·', width), width))
  else
    for text in custom
      add(header_lines, Add(lines, Center(text, width), width))
    endfor
  endif
  Add(lines, '', width)
  for section in Sections(model)
    AddBlocksSection(lines, actions, section_lines, entry_lines,
      Name(section, 'short'), Entries(section), width)
  endfor
  for text in TextLines(model, 'footer')
    add(footer_lines, Add(lines, '  ' .. text, width))
  endfor

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

# ─────────────────── neon: 双线霓虹框 ───────────────────

def NeonRow(text: string, inner: number): string
  var fitted = Fit(text, inner)
  return '║ ' .. fitted
        \ .. repeat(' ', max([0, inner - strdisplaywidth(fitted)]))
        \ .. ' ║'
enddef

def BuildNeon(model: dict<any>, width: number): dict<any>
  var lines: list<string> = []
  var actions: dict<any> = {}
  var header_lines: list<number> = []
  var section_lines: list<number> = []
  var entry_lines: list<number> = []
  var footer_lines: list<number> = []
  var frame = min([44, max([14, width])])
  var inner = max([1, frame - 4])

  var custom = TextLines(model, 'header')
  add(header_lines, Add(lines, '  ╔' .. repeat('═', inner + 2) .. '╗', width))
  if empty(custom)
    add(header_lines, Add(lines, '  ' .. NeonRow('', inner), width))
    add(header_lines, Add(lines,
      '  ' .. NeonRow(Center('◈ S T A R T I F Y ◈', inner), inner), width))
    add(header_lines, Add(lines,
      '  ' .. NeonRow(Center('a small, quick way into Vim', inner), inner), width))
    add(header_lines, Add(lines, '  ' .. NeonRow('', inner), width))
  else
    for text in custom
      add(header_lines, Add(lines, '  ' .. NeonRow(Center(text, inner), inner), width))
    endfor
  endif
  add(header_lines, Add(lines, '  ╚' .. repeat('═', inner + 2) .. '╝', width))
  Add(lines, '', width)
  for section in Sections(model)
    var rule = '  ══ ' .. toupper(Name(section, 'short')) .. ' '
    rule ..= repeat('═', max([0, min([width, 56]) - strdisplaywidth(rule)]))
    add(section_lines, Add(lines, rule, width))
    if empty(Entries(section))
      Add(lines, '    (none yet)', width)
    else
      for entry in Entries(section)
        AddAction(lines, actions, entry_lines, '  ▸ ' .. Label(entry), entry, width)
      endfor
    endif
    Add(lines, '', width)
  endfor
  for text in TextLines(model, 'footer')
    add(footer_lines, Add(lines, '  ' .. text, width))
  endfor

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

# ─────────────────── retro: 圆角 unicode 框 ───────────────────

def RetroRow(text: string, inner: number): string
  var fitted = Fit(text, inner)
  return '│ ' .. fitted
        \ .. repeat(' ', max([0, inner - strdisplaywidth(fitted)]))
        \ .. ' │'
enddef

def AddRetroSection(
    lines: list<string>,
    actions: dict<any>,
    section_lines: list<number>,
    entry_lines: list<number>,
    title: string,
    entries: list<dict<any>>,
    inner: number,
    width: number)
  add(section_lines, Add(lines, RetroRow('── ' .. toupper(title) .. ' ──', inner), width))
  if empty(entries)
    Add(lines, RetroRow('  (none yet)', inner), width)
  else
    for entry in entries
      AddAction(lines, actions, entry_lines,
        RetroRow('  ' .. Label(entry), inner), entry, width)
    endfor
  endif
enddef

def BuildRetro(model: dict<any>, width: number): dict<any>
  var lines: list<string> = []
  var actions: dict<any> = {}
  var header_lines: list<number> = []
  var section_lines: list<number> = []
  var entry_lines: list<number> = []
  var footer_lines: list<number> = []
  var frame = min([64, max([12, width])])
  var inner = max([1, frame - 4])
  var top = '╭' .. repeat('─', inner + 2) .. '╮'
  var bottom = '╰' .. repeat('─', inner + 2) .. '╯'

  var custom = TextLines(model, 'header')
  add(header_lines, Add(lines, top, width))
  for text in empty(custom)
      ? ['~ SimpleStartify ~', 'a small, quick way into Vim']
      : custom
    add(header_lines, Add(lines, RetroRow(Center(text, inner), inner), width))
  endfor
  add(header_lines, Add(lines, bottom, width))
  var first = true
  for section in Sections(model)
    if !first
      Add(lines, RetroRow('', inner), width)
    endif
    first = false
    AddRetroSection(lines, actions, section_lines, entry_lines,
      Name(section, 'short'), Entries(section), inner, width)
  endfor
  # 底框的两条边也算进 footer_lines。
  add(footer_lines, Add(lines, bottom, width))
  for text in TextLines(model, 'footer')
    add(footer_lines, Add(lines, RetroRow(Center(text, inner), inner), width))
  endfor
  add(footer_lines, Add(lines, bottom, width))

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

# ─────────────────── shadow: 投影像素横幅 ───────────────────

# 复用 blocks 的像素字体,每个方块往右下投一格 ░ 影子,只落在空白处,
# 横幅于是有了浮起来的立体感。
def ShadowBanner(word: string): list<string>
  var art = PixelBanner(word)
  var out: list<string> = []
  var prev = ''
  for row in art
    var chars = split(row, '\zs')
    var above = split(prev, '\zs')
    for i in range(len(above))
      if above[i] ==# '█' && i + 1 < len(chars) && chars[i + 1] ==# ' '
        chars[i + 1] = '░'
      endif
    endfor
    add(out, join(chars, ''))
    prev = row
  endfor
  add(out, ' ' .. substitute(prev, '█', '░', 'g'))
  return out
enddef

def BuildShadow(model: dict<any>, width: number): dict<any>
  var lines: list<string> = []
  var actions: dict<any> = {}
  var header_lines: list<number> = []
  var section_lines: list<number> = []
  var entry_lines: list<number> = []
  var footer_lines: list<number> = []

  var custom = TextLines(model, 'header')
  if empty(custom)
    for art in ShadowBanner('STARTIFY')
      add(header_lines, Add(lines, Center(art, width), width))
    endfor
    add(header_lines, Add(lines, Center('a small, quick way into Vim', width), width))
  else
    for text in custom
      add(header_lines, Add(lines, Center(text, width), width))
    endfor
  endif
  Add(lines, '', width)
  for section in Sections(model)
    add(section_lines, Add(lines, '  ▓ ' .. toupper(Name(section, 'short')), width))
    if empty(Entries(section))
      Add(lines, '    (none yet)', width)
    else
      for entry in Entries(section)
        AddAction(lines, actions, entry_lines,
          '  ▒ ' .. Label(entry), entry, width)
      endfor
    endif
    Add(lines, '', width)
  endfor
  for text in TextLines(model, 'footer')
    add(footer_lines, Add(lines, '  ' .. text, width))
  endfor

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

# ─────────────────── heavy: 粗线框 ───────────────────

def HeavyRow(text: string, inner: number): string
  var fitted = Fit(text, inner)
  return '┃ ' .. fitted
        \ .. repeat(' ', max([0, inner - strdisplaywidth(fitted)]))
        \ .. ' ┃'
enddef

def BuildHeavy(model: dict<any>, width: number): dict<any>
  var lines: list<string> = []
  var actions: dict<any> = {}
  var header_lines: list<number> = []
  var section_lines: list<number> = []
  var entry_lines: list<number> = []
  var footer_lines: list<number> = []
  var frame = min([44, max([14, width])])
  var inner = max([1, frame - 4])

  var custom = TextLines(model, 'header')
  add(header_lines, Add(lines, '  ┏' .. repeat('━', inner + 2) .. '┓', width))
  if empty(custom)
    add(header_lines, Add(lines, '  ' .. HeavyRow('', inner), width))
    add(header_lines, Add(lines,
      '  ' .. HeavyRow(Center('S T A R T I F Y', inner), inner), width))
    add(header_lines, Add(lines,
      '  ' .. HeavyRow(Center('a small, quick way into Vim', inner), inner), width))
    add(header_lines, Add(lines, '  ' .. HeavyRow('', inner), width))
  else
    for text in custom
      add(header_lines, Add(lines, '  ' .. HeavyRow(Center(text, inner), inner), width))
    endfor
  endif
  add(header_lines, Add(lines, '  ┗' .. repeat('━', inner + 2) .. '┛', width))
  Add(lines, '', width)
  for section in Sections(model)
    var rule = '  ━━ ' .. toupper(Name(section, 'short')) .. ' '
    rule ..= repeat('━', max([0, min([width, 56]) - strdisplaywidth(rule)]))
    add(section_lines, Add(lines, rule, width))
    if empty(Entries(section))
      Add(lines, '    (none yet)', width)
    else
      for entry in Entries(section)
        AddAction(lines, actions, entry_lines,
          '  ◆ ' .. Label(entry), entry, width)
      endfor
    endif
    Add(lines, '', width)
  endfor
  for text in TextLines(model, 'footer')
    add(footer_lines, Add(lines, '  ' .. text, width))
  endfor

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

# ─────────────────── sparkle: 星饰 ───────────────────

def SparkleRule(left: string, right: string, width: number): string
  var rule = '  ' .. left .. ' '
  rule ..= repeat('─', max([0, min([width, 44]) - strdisplaywidth(rule)
        \ - strdisplaywidth(right) - 1]))
  return rule .. ' ' .. right
enddef

def BuildSparkle(model: dict<any>, width: number): dict<any>
  var lines: list<string> = []
  var actions: dict<any> = {}
  var header_lines: list<number> = []
  var section_lines: list<number> = []
  var entry_lines: list<number> = []
  var footer_lines: list<number> = []

  var custom = TextLines(model, 'header')
  add(header_lines, Add(lines, SparkleRule('✦', '✦', width), width))
  if empty(custom)
    add(header_lines, Add(lines, Center('S T A R T I F Y', width), width))
    add(header_lines, Add(lines, Center('✧ a small, quick way into Vim ✧', width), width))
  else
    for text in custom
      add(header_lines, Add(lines, Center(text, width), width))
    endfor
  endif
  add(header_lines, Add(lines, SparkleRule('✧', '✧', width), width))
  Add(lines, '', width)
  for section in Sections(model)
    add(section_lines, Add(lines, '  ✦ ' .. toupper(Name(section, 'short')), width))
    if empty(Entries(section))
      Add(lines, '    (none yet)', width)
    else
      for entry in Entries(section)
        AddAction(lines, actions, entry_lines,
          '  ⋆ ' .. Label(entry), entry, width)
      endfor
    endif
    Add(lines, '', width)
  endfor
  for text in TextLines(model, 'footer')
    add(footer_lines, Add(lines, '  ' .. text, width))
  endfor

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
  if style ==# 'terminal'
    return BuildTerminal(model, safe_width)
  elseif style ==# 'blocks'
    return BuildBlocks(model, safe_width)
  elseif style ==# 'neon'
    return BuildNeon(model, safe_width)
  elseif style ==# 'retro'
    return BuildRetro(model, safe_width)
  elseif style ==# 'shadow'
    return BuildShadow(model, safe_width)
  elseif style ==# 'heavy'
    return BuildHeavy(model, safe_width)
  elseif style ==# 'sparkle'
    return BuildSparkle(model, safe_width)
  endif
  return BuildMinimal(model, safe_width)
enddef
