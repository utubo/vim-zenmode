# vim-zenmode

⚠ THIS HAS MANY BUGS !  
📜 Powered by vim9script

## INTRODUCTION
vim-zenmode is a Vim plugin emulates the next line with `echo` when statusline is not visible.

<img width="600" src="https://user-images.githubusercontent.com/6848636/190131844-dd95d5d4-0f18-44c1-a50b-35bddec8e1c6.png">

## USAGE
### Require
- vim9script

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

## FUNCTIONS
- `zenmode#Enable(): bool`
  Enable zenmode and return true.
- `zenmode#Disable(): bool`
  Disable zenmode and return true.
- `zenmode#Toggle(): bool`
  Toggle zenmode and return true when zenmode is enabeld.

## VARIABLES

### `g:zenmode`
`g:zenmode` is dictionaly.  

- `delay`  
  number.  
  millseconds of show the next line when return from Command-mode.  
  `n(> 0)`: delay n seconds.  
  `0`: no delay.  
  `-1`: show the next line on cursor moved.  
  default is `-1`.
- `horiz`  
  the char of the horizontal line.  
  default is empty.
- `exclude`  
  the exclude bufnames.
  default is `['ControlP']`.
- `refeshInteval`
  number  
  the millseconds of refresh the next line.
  `-1` means disable regular refreshs.
  default is `100`.
- `preventEcho`  
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
- `ZenmodeHoriz`
  Horizontal line.
  default is Strikeouted NonText

