" vim-q-connect.vim - Vim plugin for Q CLI context via MCP
" Maintainer: Edouard Poor

if exists('g:loaded_vim_q_connect')
  finish
endif
let g:loaded_vim_q_connect = 1

" Default configuration
if !exists('g:vim_q_connect_socket_path')
  let g:vim_q_connect_socket_path = getcwd() . '/.vim-q-mcp.sock'
endif

" Commands
command! -bang QConnect if <bang>0 | call vim_q_connect#stop_tracking() | else | call vim_q_connect#start_tracking() | endif
