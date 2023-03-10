vim9script

# --------------------
# Global variables
# --------------------

var enable = false
var listchars = { tab: '  ', extends: '' }
var vertchar = '|'
const zen_horizline = '%#CmdHeight0Horiz#%{zenmode#HorizLine()}'
var statusline_bkup = &statusline
b:zenmode_teminal = false

# --------------------
# Utils
# --------------------

# silent with echo
def Silent(F: func)
  try
    F()
  catch
    augroup zenmode
      au!
    augroup END
    g:zenmode = get(g:, 'zenmode', {})
    g:zenmode.lasterror = v:exception
    g:zenmode.initialized = 0
    echoe 'vim-zenmode was stopped for safety. ' ..
      'You can `:call zenmode#Init()` to restart. ' ..
      $'Exception:{v:exception}'
    throw v:exception
  endtry
enddef

# get bottom windows
var bottomWinIds = []

def GetBottomWinIds(layout: any): any
  if layout[0] ==# 'col'
    return GetBottomWinIds(layout[1][-1])
  elseif layout[0] ==# 'row'
    var rows = []
    for r in layout[1]
      rows += GetBottomWinIds(r)
    endfor
    return rows
  else
    return [layout[1]]
  endif
enddef

def UpdateBottomWinIds()
  bottomWinIds = GetBottomWinIds(winlayout())
  g:zenmode.winupdated = 0
enddef

# others
def NVL(v: any, default: any): any
  return empty(v) ? default : v
enddef

# --------------------
# Setup
# --------------------

export def Init()
  const override = get(g:, 'zenmode', {})
  g:zenmode = {
    horiz: '-',
    delay: -1,
  }
  g:zenmode->extend(override)
  set noruler
  set noshowcmd
  set laststatus=0
  augroup zenmode
    au!
    au ColorScheme * Silent(Invalidate)
    au WinNew,WinClosed,TabLeave * g:zenmode.winupdated = 1
    au WinEnter * Silent(Update)|SaveWinSize() # for check scroll
    au WinLeave * Silent(Invalidate)
    au WinScrolled * Silent(OnSizeChangedOrScrolled)
    au ModeChanged [^c]:[^t] Silent(Invalidate)
    au ModeChanged c:* Silent(OverwriteEchoWithDelay)
    au ModeChanged t:* b:zenmode_teminal = false|Silent(Update)
    au ModeChanged *:t b:zenmode_teminal = true|Silent(Update)
    au TabEnter * Silent(Invalidate)
    au OptionSet laststatus,fillchars,number,relativenumber,signcolumn Silent(Invalidate)
    au CursorMoved * Silent(CursorMoved)
  augroup END
  # prevent to echo search word
  if maparg('n', 'n')->empty()
    nnoremap <script> <silent> n n
  endif
  if maparg('N', 'n')->empty()
    nnoremap <script> <silent> N N
  endif
  g:zenmode.initialized = 1
  Update()
enddef

# Scroll event
def SaveWinSize()
  w:zenmode_wsize = [winwidth(0), winheight(0)]
enddef

def OnSizeChangedOrScrolled()
  if !enable
    return
  endif
  const new_wsize = [winwidth(0), winheight(0)]
  if w:zenmode_wsize ==# new_wsize
    timer_start(0, EchoNextLine)
  else
    w:zenmode_wsize = new_wsize
    Update()
  endif
  # prevent flickering
  augroup zenmode_invalidate
    au!
    au SafeState * ++once Silent(EchoNextLine)
  augroup END
enddef

# Other events
def CursorMoved()
  if enable
    timer_start(0, EchoNextLine)
  endif
enddef

def OverwriteEchoWithDelay()
  if enable && 0 <= g:zenmode.delay
    timer_start(g:zenmode.delay, 'zenmode#Invalidate')
  endif
enddef

# --------------------
# Echo the next line
# --------------------

def SetupZen()
  const before = enable
  enable = &laststatus ==# 0 || &laststatus ==# 1 && winnr('$') ==# 1
  if !enable
    TurnDown(before)
    return
  endif
  # setup horizontal line
  if &statusline !=# zen_horizline
    statusline_bkup = &statusline
    &statusline = zen_horizline
  endif
  # cache &listchars, &fillchars
  listchars = { tab: '  ', extends: '' }
  for kv in split(&listchars, ',')
    var [k, v] = split(kv, ':')
    listchars[k] = v
  endfor
  const p = &fillchars->stridx('vert:')
  vertchar = p !=# -1 ? &fillchars[p + 5] : '|'
enddef

def TurnDown(before: bool)
  enable = false
  if &statusline ==# zen_horizline
    &statusline = statusline_bkup
  endif
  if before
    redraw!
    echo ""
  endif
enddef

def EchoNextLine(timer: any = 0, opt: any = { redraw: false })
  # Setup
  if !enable
    return
  endif
  const m = mode()[0]
  if m ==# 'c' || m ==# 'r'
    return
  endif
  if g:zenmode.winupdated ==# 1
    UpdateBottomWinIds()
  endif
  if opt.redraw
    redraw # This flicks the screen on gvim.
  else
    echo "\r"
  endif
  # Echo !
  var has_prev = false
  for winid in bottomWinIds
    if has_prev
      echoh VertSplit
      echon vertchar
    endif
    EchoNextLineWin(winid)
    has_prev = true
  endfor
enddef

def EchoNextLineWin(winid: number)
  const winnr = win_id2win(winid)
  var width = winwidth(winnr)
  # prevent linebreak with echo
  if winid ==# bottomWinIds[-1]
    width -= 1
  endif
  if width <= 0
    return
  endif
  if !!getbufvar(getwininfo(winid)[0].bufnr, 'zenmode_teminal')
    echoh Terminal
    echon repeat(' ', width)
    return
  endif
  # TODO: The line is dolubled when botline is wrapped.
  var linenr = line('w$', winid)
  const fce = WinGetLn(winid, linenr, 'foldclosedend')
  if fce !=# '-1'
    linenr = str2nr(fce)
  endif
  linenr += 1
  # end of buffer
  if linenr > line('$', winid)
    echoh EndOfBuffer
    echon printf($'%-{width}S', NVL(matchstr(&fcs, '\(eob:\)\@<=.'), '~'))
    echoh Normal
    return
  endif
  const textoff = getwininfo(winid)[0].textoff
  # sign & line-number
  if textoff !=# 0
    echoh SignColumn
    const rnu = getwinvar(winnr, '&relativenumber')
    if getwinvar(winnr, '&number') || rnu
      const nw = max([2, getwinvar(winnr, '&numberwidth')])
      const linestr = printf($'%{nw - 1}d ', rnu ? abs(linenr - line('.')) : linenr)
      echon repeat(' ', textoff - len(linestr))
      echoh LineNr
      echon linestr
    else
      echon repeat(' ', textoff)
    endif
  endif
  width -= textoff
  # folded
  if WinGetLn(winid, linenr, 'foldclosed') !=# '-1'
    echoh Folded
    echon printf($'%.{width}S', WinGetLn(winid, linenr, 'foldtextresult'))->printf($'%-{width}S')
    echoh Normal
    return
  endif
  # tab
  const ts = getwinvar(winnr, '&tabstop')
  const expandtab = listchars.tab[0] .. repeat(listchars.tab[1], ts)
  var text = NVL(getbufline(winbufnr(winnr), linenr), [''])[0]
  var i = 1
  var v = 0
  win_execute(winid, $'call zenmode#GetHiNames({linenr})')
  for c in split(text, '\zs')
    var vc = c
    if vc ==# "\t"
      echoh SpecialKey
      if !listchars.tab[2] # string to bool
        vc = strpart(expandtab, 0, ts - v % ts)
      else
        vc = strpart(expandtab, 0, ts - v % ts - 1) .. listchars.tab[2]
      endif
    else
      execute 'echoh ' .. get(hi_names, i, 'Error')
    endif
    var vw = strdisplaywidth(vc)
    if width <= v + vw
      echoh SpecialKey
      echon listchars.extends ?? printf('%.1S', vc)
      v += 1
      break
    endif
    echon vc
    i += len(c)
    v += vw
  endfor
  echoh Normal
  echon repeat(' ', width - v)
enddef

def WinGetLn(winid: number, linenr: number, com: string): string
  return win_execute(winid, $'echon {com}({linenr})')
enddef

var hi_names = []
export def GetHiNames(l: number)
  hi_names = ['Normal']
  for c in range(1, getline(l)->printf($'%+{winwidth(0)}S')->len())
    hi_names += [synID(l, c, 1)->synIDattr('name') ?? 'Normal']
  endfor
enddef

def Update()
  if get(g:zenmode, 'initialized', 0) ==# 0
    Init()
    return
  endif
  b:zenmode_teminal = mode() ==# 't'
  g:zenmode.winupdated = 1
  SaveWinSize()
  SetupZen()
  EchoNextLine(0, { redraw: true })
  redrawstatus # This flicks the screen on gvim.
enddef

# --------------------
# API
# --------------------

export def Invalidate(timer: any = 0)
  augroup zenmode_invalidate
    au!
    au SafeState * ++once Silent(Update)
  augroup END
enddef

export def HorizLine(): string
  const width = winwidth(0)
  return printf($"%.{width}S", repeat(g:zenmode.horiz, width))
enddef

