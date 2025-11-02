" vim-llm-mcp.vim - Vim plugin for LLM context via MCP
" Maintainer: Your Name

if exists('g:loaded_vim_llm_mcp')
  finish
endif
let g:loaded_vim_llm_mcp = 1

" Default configuration
if !exists('g:vim_llm_mcp_socket_path')
  let g:vim_llm_mcp_socket_path = expand('<sfile>:p:h:h') . '/.vim-q-mcp.sock'
endif

if !exists('g:vim_llm_mcp_auto_start')
  let g:vim_llm_mcp_auto_start = 1
endif

" Commands
command! -bang QConnect if <bang>0 | call vim_llm_mcp#stop_tracking() | else | call vim_llm_mcp#start_tracking() | endif

" Auto-start context tracking if enabled
if g:vim_llm_mcp_auto_start
  autocmd VimEnter * call vim_llm_mcp#start_tracking()
endif
