" vim-q-connect.vim - Vim plugin for Q CLI context via MCP
" Maintainer: Your Name

if exists('g:loaded_vim_q_connect')
  finish
endif
let g:loaded_vim_q_connect = 1

" Default configuration
if !exists('g:vim_q_connect_socket_path')
  let g:vim_q_connect_socket_path = expand('<sfile>:p:h:h') . '/.vim-q-mcp.sock'
endif

if !exists('g:vim_q_connect_auto_start')
  let g:vim_q_connect_auto_start = 1
endif

" Commands
command! -bang QConnect if <bang>0 | call vim_q_connect#stop_tracking() | else | call vim_q_connect#start_tracking() | endif

" Auto-start context tracking if enabled
if g:vim_q_connect_auto_start
  autocmd VimEnter * call vim_q_connect#start_tracking()
endif
