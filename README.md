# vim-zenmode

⚠ THIS HAS MANY BUGS !  
📜 Powered by Vim9 script

## INTRODUCTION
vim-zenmode is a Vim plugin emulates the next line with `echo` when statusline is not visible.

<img width="600" src="https://user-images.githubusercontent.com/6848636/190131844-dd95d5d4-0f18-44c1-a50b-35bddec8e1c6.png">

## USAGE
### Require
- Vim9 Head

### Install
- Example of `.vimrc`
  ```vim
  vim9script
  ⋮
  dein#add('utubo/vim-zenmode')
  ⋮
  set statusline = 0
  # toggle Zen-Mode
  nnoremap ZZ <Cmd>call zenmode#Toggle()<CR>
  ```
Note: This does not support contens of tabpanel.

## FUNCTIONS
- `zenmode#Enable(): bool`
  Enable zenmode and return true.
- `zenmode#Disable(): bool`
  Disable zenmode and return true.
- `zenmode#Toggle(): bool`
  Toggle zenmode and return true when zenmode is enabeld.

## VARIABLES
    
### `g:zenmode`
`g:zenmode` is a dictionaly.  

- `delay`  (default `-1`)  
  number.  
  The millseconds of show the next line when return from Command-mode.  
  `n(> 0)`: Delay n seconds.  
  `0`: No delay.  
  `-1`: Show the next line on cursor moved.  
- `horiz`  (default empty)  
  The char of the horizontal line.  
- `exclude`  (default `['ControlP']`)  
  The exclude bufnames.
- `refeshInteval`  (default `100`)  
  number  
  The millseconds of a timer to refresh without
  autocmd. e.g. On textoff is changed.
  `-1` means disable regular refreshs.
- `ruler` (default `false`)  
  Keep the ruler.
- `override` (default `(_, __, ___) => false`)  
  A funcref to echo next line.  
  The arguments are winid, winnr and width.  
  This returns |true| when hooked.  
  e.g.)
  ```vim
  def Foo(_: number, __: number, width: number): bool
    echon repeat('*', width)
    return true
  enddef
  g:zenomde.override = Foo
  ```
- `preventEcho`  (deprecated, default `false`)  
  Prevent to echo the next line.  
  (for echo you want.)

Example
```vim
vim9script
g:zenmode = {
  delay: 3,
  horiz: '═',
}
```

## COLORS
- `ZenmodeHoriz`  (default Strikeouted NonText)  
  Horizontal line.

