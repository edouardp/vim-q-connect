" vim-q-connect.vim - Vim plugin for Q CLI context via MCP
" Maintainer: Edouard Poor
" 
" This is the plugin initialization file. The actual functionality is implemented
" in modular autoload files for better organization and maintainability.

if exists('g:loaded_vim_q_connect')
  finish
endif
let g:loaded_vim_q_connect = 1

" Define highlight group for Q text
highlight qtext ctermbg=237 ctermfg=250 cterm=italic guibg=#2a2a2a guifg=#d0d0d0 gui=italic

" Define highlighter pen colors
highlight QHighlightYellow  ctermbg=227    ctermfg=black  guibg=#ffff00  cterm=bold  gui=bold
highlight QHighlightOrange  ctermbg=208    ctermfg=black  guibg=#ff8c00  cterm=bold  gui=bold
highlight QHighlightPink    ctermbg=213    ctermfg=black  guibg=#ff69b4  cterm=bold  gui=bold
highlight QHighlightGreen   ctermbg=47     ctermfg=black  guibg=#90ee90  cterm=bold  gui=bold
highlight QHighlightBlue    ctermbg=87     ctermfg=black  guibg=#add8e6  cterm=bold  gui=bold
highlight QHighlightPurple  ctermbg=165    ctermfg=black  guibg=#dda0dd  cterm=bold  gui=bold

" Define virtual text highlight groups (darker shades)
highlight QHighlightVirtualYellow  ctermbg=214  ctermfg=black  guibg=#e6e600  guifg=black  gui=bold
highlight QHighlightVirtualOrange  ctermbg=166  ctermfg=black  guibg=#e67e00  guifg=black  gui=bold
highlight QHighlightVirtualPink    ctermbg=200  ctermfg=black  guibg=#ff1493  guifg=black  gui=bold
highlight QHighlightVirtualGreen   ctermbg=34   ctermfg=black  guibg=#7cb342  guifg=black  gui=bold
highlight QHighlightVirtualBlue    ctermbg=74   ctermfg=black  guibg=#4a90e2  guifg=black  gui=bold
highlight QHighlightVirtualPurple  ctermbg=129  ctermfg=black  guibg=#b366cc  guifg=black  gui=bold

" Commands
command! -bang QConnect if <bang>0 | call vim_q_connect#stop_tracking() | else | call vim_q_connect#start_tracking() | endif
command! QVirtualTextClear call vim_q_connect#clear_virtual_text()
command! QHighlightsClear call vim_q_connect#clear_highlights()
command! QQuickfixAnnotate call vim_q_connect#quickfix_annotate()
command! QQuickfixClear call vim_q_connect#clear_quickfix()
command! -bang QQuickfixAutoAnnotate call vim_q_connect#quickfix_auto_annotate(<bang>0 ? 0 : 1)
