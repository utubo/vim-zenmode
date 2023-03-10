vim9script

def AtStart()
  if ! exists('g:zenmode.at_start') || g:zenmode.at_start !=# 0
    zenmode#Init()
  endif
enddef

augroup zenmode_atstart
  au!
  au VimEnter * AtStart()
augroup END

