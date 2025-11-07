" vim-q-connect.vim - Vim plugin for Q CLI context via MCP
" Maintainer: Edouard Poor

if exists('g:loaded_vim_q_connect')
  finish
endif
let g:loaded_vim_q_connect = 1

" Define highlight group for Q text
highlight qtext ctermbg=237 ctermfg=250 cterm=italic guibg=#2a2a2a guifg=#d0d0d0 gui=italic

" Socket path will be determined at connection time if not set

" Commands
command! -bang QConnect if <bang>0 | call vim_q_connect#stop_tracking() | else | call vim_q_connect#start_tracking() | endif
command! QVirtualTextClear call vim_q_connect#clear_virtual_text()
command! QQuickfixAnnotate call vim_q_connect#quickfix_annotate()
