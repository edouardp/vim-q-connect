" vim-q-connect.vim - Vim plugin for Q CLI context via MCP
" Maintainer: Edouard Poor

if exists('g:loaded_vim_q_connect')
  finish
endif
let g:loaded_vim_q_connect = 1

" Define highlight group for Q text
highlight qtext ctermbg=237 ctermfg=250 cterm=italic guibg=#2a2a2a guifg=#d0d0d0 gui=italic

" Define highlighter pen colors
highlight QHighlightYellow ctermbg=yellow guibg=#ffff00 cterm=bold gui=bold
highlight QHighlightOrange ctermbg=208 guibg=#ff8c00 cterm=bold gui=bold
highlight QHighlightPink ctermbg=213 guibg=#ff69b4 cterm=bold gui=bold
highlight QHighlightGreen ctermbg=green guibg=#90ee90 cterm=bold gui=bold
highlight QHighlightBlue ctermbg=lightblue guibg=#add8e6 cterm=bold gui=bold
highlight QHighlightPurple ctermbg=magenta guibg=#dda0dd cterm=bold gui=bold

" Define virtual text highlight groups (darker shades)
highlight QHighlightVirtualYellow ctermbg=3 ctermfg=black guibg=#e6e600 guifg=black cterm=bold gui=bold
highlight QHighlightVirtualOrange ctermbg=130 ctermfg=black guibg=#e67e00 guifg=black cterm=bold gui=bold
highlight QHighlightVirtualPink ctermbg=198 ctermfg=black guibg=#ff1493 guifg=black cterm=bold gui=bold
highlight QHighlightVirtualGreen ctermbg=2 ctermfg=black guibg=#7cb342 guifg=black cterm=bold gui=bold
highlight QHighlightVirtualBlue ctermbg=4 ctermfg=black guibg=#4a90e2 guifg=black cterm=bold gui=bold
highlight QHighlightVirtualPurple ctermbg=5 ctermfg=black guibg=#b366cc guifg=black cterm=bold gui=bold

" Socket path will be determined at connection time if not set

" Auto-annotate quickfix entries when opening files (disabled due to property type issues)
" augroup QQuickfixAnnotate
"   autocmd!
"   autocmd BufEnter * if !empty(getqflist()) | call vim_q_connect#quickfix_annotate() | endif
" augroup END

" Commands
command! -bang QConnect if <bang>0 | call vim_q_connect#stop_tracking() | else | call vim_q_connect#start_tracking() | endif
command! QVirtualTextClear call vim_q_connect#clear_virtual_text()
command! QHighlightsClear call vim_q_connect#clear_highlights()
command! QQuickfixAnnotate call vim_q_connect#quickfix_annotate()
command! QQuickfixClear call vim_q_connect#clear_quickfix()
command! -bang QQuickfixAutoAnnotate call vim_q_connect#quickfix_auto_annotate(<bang>0 ? 0 : 1)
