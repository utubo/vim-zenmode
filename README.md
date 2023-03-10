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
  dein# add('utubo/vim-zenmode')
  ⋮
  set statusline = 0
  # toggle Zen-Mode
  nnoremap ZZ <Cmd>let &laststatus = !&laststatus ? 2 : 0<CR>
  ```


## VARIABLES

### `g:zenmode`
`g:zenmode` is dictionaly.  

- `delay`  
  number.  
  seconds of show the next line when return from Command-mode.  
  default is `-1`.  
  n(> 0): delay n seconds.  
  0: no delay.  
  n(< 0): show the next line on cursor moved.
- `horiz`  
  the char of the horizontal line.  
  default is `-`

Example
```vim
vim9script
g:zenmode = {
  delay: 3,
  horiz: '-',
}
```

