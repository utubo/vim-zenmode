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
var refresh_timer = 0
var refresh_on_cursormoved = true
var cur_bkup = []
var tabpanel = [0, 0]
b:zenmode_teminal = false

# --------------------
# Utils
# --------------------

# silent with echo
def Silent(F: func)
  try
    F()
  catch
    au! zenmode
    timer_stop(refresh_timer)
    g:zenmode = get(g:, 'zenmode', {})
    g:zenmode.lasterror = v:exception
    g:zenmode.initialized = 0
    echoh ErrorMsg
    echom 'vim-zenmode was stopped for safety.'
    echom '  You can `:call zenmode#Init()` to restart.'
    echom $'  v:exception: {v:exception}'
    echom $'  v:throwpoint: {v:throwpoint}'
    echoh Normal
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
    refreshInterval: 100,
    ruler: false,
  }
  g:zenmode->extend(override)
  if !g:zenmode.ruler
    set noruler
  endif
  set noshowcmd
  set laststatus=0
  augroup zenmode
    au!
    au ColorScheme * SetupColor()
    au ColorScheme * Silent(Invalidate)
    au WinNew,WinClosed,TabLeave * winupdated = 1
    au WinEnter * Silent(RedrawNow)|SaveWinSize() # for check scroll
    au WinLeave * Silent(Invalidate)
    au WinScrolled * Silent(OnSizeChangedOrScrolled)
    au ModeChanged [^c]:[^t] Silent(Invalidate)
    au ModeChanged *:c Silent(OnCmdlineEnter)
    au ModeChanged t:* b:zenmode_teminal = false|Silent(RedrawNow)
    au ModeChanged *:t b:zenmode_teminal = true|Silent(RedrawNow)
    au TabEnter * Silent(Invalidate)
    au OptionSet signcolumn Silent(OnSign)
    au OptionSet laststatus,fillchars,number,relativenumber Silent(Invalidate)
    au CursorMoved * Silent(CursorMoved)
    au OptionSet tabpanelopt,showtabpanel,ruler Silent(GetTabPanel)
    au TabNew,TabClosed * Silent(GetTabPanel)
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
  if 0 < g:zenmode.refreshInterval
    refresh_timer = timer_start(g:zenmode.refreshInterval, RegularRefresh, { repeat: -1 })
  endif
  GetTabPanel()
  RedrawNow()
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
  if get(w:, 'zenmode_wsize', []) ==# new_wsize
    timer_start(0, EchoNextLine)
  else
    w:zenmode_wsize = new_wsize
    RedrawNow()
  endif
  # prevent flickering
  augroup zenmode_invalidate
    au!
    au SafeState * ++once Silent(EchoNextLine)
  augroup END
enddef

# Other events
def CursorMoved()
  if enable && refresh_on_cursormoved
    timer_start(0, EchoNextLine)
  endif
enddef
def OnSign()
   if CheckTextoff()
      RedrawNow()
   endif
enddef

def OnCmdlineEnter()
  if !enable
    return
  endif
  refresh_on_cursormoved = false
  cur_bkup = getcurpos()
  au ModeChanged c:[^c] ++once timer_start(0, (_) => {
    refresh_on_cursormoved = true
    if cur_bkup !=# getcurpos()
      Invalidate()
    endif
  })
  if 0 <= g:zenmode.delay
    au ModeChanged c:[^c] ++once timer_start(g:zenmode.delay, 'zenmode#Invalidate')
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
  # prevent to link Normal to MsgArea
  const normal_id = hlID('Normal')->synIDtrans()
  normal_fg = NVL(synIDattr(normal_id, 'fg#'), 'NONE')
  normal_bg = NVL(synIDattr(normal_id, 'bg#'), 'NONE')
  const x = normal_fg[0] =~# '^\d*$' ? 'cterm' : 'gui'
  execute $'hi ZenNormal {x}fg={normal_fg} {x}bg={normal_bg}'
  converted_hl = { 'Normal': 'ZenNormal' }
  # horizontal line
  const id = hlID('NonText')->synIDtrans()
  const fg = NVL(synIDattr(id, 'fg#'), 'NONE')
  execute $'silent! hi default ZenmodeHoriz {x}=strikethrough {x}fg={fg}'
enddef

def GetTabPanel()
  tabpanel = [0, 0]
  if !has('tabpanel') || &ruler
    return
  endif
  var s = 0
  silent! s = execute('echon &showtabpanel')->str2nr()
  if s ==# 0 || s ==# 1 && tabpagenr('$') ==# 1
    return
  endif
  var opt = ''
  silent! opt = execute('echon &tabpanelopt')
  const c = opt->matchstr('\(columns:\)\@<=\d\+')->str2nr() ?? 20
  if &columns < c
    return
  endif
  const i = opt->stridx('align:right') !=# -1 ? 1 : 0
  tabpanel[i] = c
enddef

def EchoTabPanel(width: number)
  if 1 < width
    echoh TabPanelFill
    echon repeat(' ', width)
    echoh Normal
  endif
enddef

var textoff_bk = 0
def CheckTextoff(): bool
  if !bottomWinIds
    return false
  endif
  const a = getwininfo(bottomWinIds[0])
  if !a
    return false
  endif
  const b = a[0].textoff
  if b ==# textoff_bk
    return false
  endif
  textoff_bk = b
  return true
enddef

var foldclosed_bk = 0
def CheckFoldClosed(): bool
  if !bottomWinIds
    return false
  endif
  const f = foldclosed('.')
  if f ==# foldclosed_bk
    return false
  endif
  foldclosed_bk = f
  return true
enddef

def RegularRefresh(t: number = 0)
  if CheckTextoff() || CheckFoldClosed()
    RedrawNow()
  endif
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
  # Check
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
  # Setup
  if winupdated ==# 1
    UpdateBottomWinIds()
  endif
  if opt.redraw
    redraw # This flicks the screen on gvim.
  else
    echo "\r"
  endif
  # Echo !
  EchoTabPanel(tabpanel[0])
  var has_prev = false
  for winid in bottomWinIds
    if has_prev
      echoh VertSplit
      echon vertchar
    endif
    const prevent_linebreak = winid ==# bottomWinIds[-1] && !tabpanel[1]
    EchoNextLineWin(winid, prevent_linebreak)
    has_prev = true
  endfor
  EchoTabPanel(tabpanel[1] - 1)
enddef

def EchoNextLineWin(winid: number, prevent_linebreak: bool)
  const winnr = win_id2win(winid)
  var width = winwidth(winnr)
  # prevent linebreak with echo
  if prevent_linebreak
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
  const iswrap = getwinvar(winnr, '&wrap')
  if iswrap && screenpos(winnr, linenr, 0).row !=# 0
    echoh EndOfBuffer
    echon repeat(NVL(matchstr(&fcs, '\(lastline:\)\@<=.'), '@'), width)
    echoh Normal
    return
  endif
  # show text
  var i = 1
  var v = 0
  win_execute(winid, $'call zenmode#GetHiNames({linenr})')
  for c in split(text, '\zs')
    echoh ZenNormal
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
      const id = hlID(name)->synIDtrans()
      const fg = NVL(synIDattr(id, 'fg#'), normal_fg)
      const bg = NVL(synIDattr(id, 'bg#'), normal_bg)
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

# --------------------
# API
# --------------------

export def RedrawNow()
  if get(g:zenmode, 'initialized', 0) ==# 0
    Init()
    return
  endif
  b:zenmode_teminal = mode() ==# 't'
  winupdated = 1
  silent! hi default link ZenmodeHoriz VertSplit
  SaveWinSize()
  SetupZen()
  EchoNextLine(0, { redraw: has('gui') })
  redrawstatus # This flicks the screen on gvim.
enddef

export def Invalidate(timer: any = 0)
  augroup zenmode_invalidate
    au!
    au SafeState * ++once {
      if mode() !=# 'c'
        Silent(RedrawNow)
      endif
    }
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

