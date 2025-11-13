" vim-q-connect.vim - Vim plugin for Q CLI context via MCP
" Maintainer: Edouard Poor

if exists('g:loaded_vim_q_connect')
  finish
endif
let g:loaded_vim_q_connect = 1

" Define highlight group for Q text
highlight qtext ctermbg=237 ctermfg=250 cterm=italic guibg=#2a2a2a guifg=#d0d0d0 gui=italic

" Socket path will be determined at connection time if not set

" Auto-annotate quickfix entries when opening files (disabled due to property type issues)
" augroup QQuickfixAnnotate
"   autocmd!
"   autocmd BufEnter * if !empty(getqflist()) | call vim_q_connect#quickfix_annotate() | endif
" augroup END

" Commands
command! -bang QConnect if <bang>0 | call vim_q_connect#stop_tracking() | else | call vim_q_connect#start_tracking() | endif
command! QVirtualTextClear call vim_q_connect#clear_virtual_text()
command! QQuickfixAnnotate call vim_q_connect#quickfix_annotate()
command! QQuickfixClear call vim_q_connect#clear_quickfix()
command! -bang QQuickfixAutoAnnotate call vim_q_connect#quickfix_auto_annotate(<bang>0 ? 0 : 1)
