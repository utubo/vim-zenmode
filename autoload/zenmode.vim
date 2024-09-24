vim9script

# --------------------
# Global variables
# --------------------

var enable = false
var winupdated = 1
var listchars = { tab: '  ', extends: '' }
var vertchar = '|'
const zen_horizline = '%#ZenmodeHoriz#%{zenmode#HorizLine()}'
var statusline_bkup = &statusline
var converted_hl = {}
var normal_fg = ''
var normal_bg = ''
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
  winupdated = 0
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
    horiz: '',
    delay: -1,
    exclude: ['ControlP'],
    preventEcho: false,
  }
  g:zenmode->extend(override)
  set noruler
  set noshowcmd
  set laststatus=0
  augroup zenmode
    au!
    au ColorScheme * SetupColor()
    au ColorScheme * Silent(Invalidate)
    au WinNew,WinClosed,TabLeave * winupdated = 1
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
  SetupColor()
  Enable()
  g:zenmode.initialized = 1
  timer_start(g:zenmode.delay, 'zenmode#Invalidate')
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

def GetFgBg(name: string): any
  var rv = name[0] ==# '!'
  const nm = rv ? name[1 : ] : name
  const id = hlID(nm)->synIDtrans()
  var fg = NVL(synIDattr(id, 'fg#'), 'NONE')
  var bg = NVL(synIDattr(id, 'bg#'), 'NONE')
  if synIDattr(id, 'reverse') ==# '1'
    rv = !rv
  endif
  if rv
    return { fg: bg, bg: fg }
  else
    return { fg: fg, bg: bg }
  endif
enddef

def SetupColor()
  const x = has('gui') ? 'gui' : 'cterm'
  # prevent to link Normal to MsgArea
  const normal_id = hlID('Normal')->synIDtrans()
  normal_fg = NVL(synIDattr(normal_id, 'fg#'), 'NONE')
  normal_bg = NVL(synIDattr(normal_id, 'bg#'), 'NONE')
  execute $'hi ZenNormal {x}fg={normal_fg} {x}bg={normal_bg}'
  converted_hl = { 'Normal': 'ZenNormal' }
  # horizontal line
  const id = hlID('NonText')->synIDtrans()
  const fg = NVL(synIDattr(id, 'fg#'), 'NONE')
  execute $'hi default ZenmodeHoriz {x}=strikethrough {x}fg={fg}'
enddef

# --------------------
# Echo the next line
# --------------------

def SetupZen()
  const before = enable
  enable = &laststatus ==# 0 || &laststatus ==# 1 && winnr('$') ==# 1
  if before ==# enable
    # nop
  elseif enable
    ZenEnter()
  else
    ZenLeave()
  endif
enddef

def ZenEnter()
  # cache &listchars, &fillchars
  listchars = { tab: '  ', extends: '' }
  for kv in split(&listchars, ',')
    var [k, v] = split(kv, ':')
    listchars[k] = v
  endfor
  const p = &fillchars->stridx('vert:')
  vertchar = p !=# -1 ? &fillchars[p + 5] : '|'
  # setup horizontal line
  if &statusline !=# zen_horizline
    statusline_bkup = &statusline
    &statusline = zen_horizline
  endif
enddef

def ZenLeave()
  if &statusline ==# zen_horizline
    &statusline = statusline_bkup
  endif
  redraw!
  echo ""
  redrawstatus
enddef

def EchoNextLine(timer: any = 0, opt: any = { redraw: false })
  # Setup
  if !enable || g:zenmode.preventEcho
    return
  endif
  if g:zenmode.exclude->index(bufname('%')) !=# -1
    return
  endif
  const m = mode()[0]
  if m ==# 'c' || m ==# 'r'
    return
  endif
  if winupdated ==# 1
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
  width -= textoff
  # sign & line-number
  if textoff !=# 0
    var w = textoff
    echoh SignColumn
    var snl = []
    silent! snl = sign_getplaced(winbufnr(winnr), { lnum: linenr, group: '*' })[0].signs
    if !!snl
      const sn = sign_getdefined(snl[0].name)[0]
      silent! execute 'echoh ' .. sn.texthl
      echon get(sn, 'text', '  ')
      w -= 2
    endif
    const rnu = getwinvar(winnr, '&relativenumber')
    if getwinvar(winnr, '&number') || rnu
      const nw = getwinvar(winnr, '&numberwidth')
      const linestr = printf($'%{nw - 1}d ', rnu ? abs(linenr - line('.', winid)) : linenr)
      echon repeat(' ', w - len(linestr))
      echoh LineNr
      echon linestr
    else
      echon repeat(' ', w)
    endif
  endif
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
  # wrapped
  # TODO: The line is dolubled when botline is wrapped.
  if getwinvar(winnr, '&wrap') && width < strdisplaywidth(text)
    echoh EndOfBuffer
    echon repeat(NVL(matchstr(&fcs, '\(lastline:\)\@<=.'), '@'), width)
    echoh Normal
    return
  endif
  # show text
  var i = 1
  var v = 0
  win_execute(winid, $'call zenmode#GetHiNames({linenr})')
  echoh ZenNormal
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
  echoh ZenNormal
  echon repeat(' ', width - v)
  echoh Normal
enddef

def WinGetLn(winid: number, linenr: number, com: string): string
  return win_execute(winid, $'echon {com}({linenr})')
enddef

var hi_names = []
export def GetHiNames(l: number)
  hi_names = ['ZenNormal']
  for c in range(1, getline(l)->printf($'%+{winwidth(0)}S')->len())
    const name = synID(l, c, 1)->synIDattr('name')
    if ! converted_hl->has_key(name)
      const id = hlID('Normal')->synIDtrans()
      const fg = NVL(synIDattr(id, 'fg#'), 'NONE')
      const bg = NVL(synIDattr(id, 'bg#'), 'NONE')
      if fg ==# normal_fg && bg ==# normal_bg
        converted_hl[name] = 'ZenNormal'
      else
        converted_hl[name] = name
      endif
    endif
    hi_names += [converted_hl[name]]
  endfor
  g:hi_names = hi_names
enddef

def Update()
  if get(g:zenmode, 'initialized', 0) ==# 0
    Init()
    return
  endif
  b:zenmode_teminal = mode() ==# 't'
  winupdated = 1
  silent! hi default link ZenmodeHoriz VertSplit
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

export def Enable(): bool
  silent! lightline#disable()
  &laststatus = 0
  ZenEnter() # for lightline
  return true
enddef

export def Disable(): bool
  silent! lightline#enable()
  &laststatus = 2
  return false
enddef

export def Toggle(): bool
  if &laststatus !=# 0
    return Enable()
  else
    return Disable()
  endif
enddef

