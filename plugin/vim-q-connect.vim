" vim-q-connect.vim - Vim plugin for Q CLI context via MCP
" Maintainer: Edouard Poor

if exists('g:loaded_vim_q_connect')
  finish
endif
let g:loaded_vim_q_connect = 1

" Socket path will be determined at connection time if not set

" Commands
command! -bang QConnect if <bang>0 | call vim_q_connect#stop_tracking() | else | call vim_q_connect#start_tracking() | endif
