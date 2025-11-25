" Autoload functions for vim-q-connect
" 
" This plugin provides editor context to Q CLI via Model Context Protocol (MCP).
" It tracks cursor position, file changes, and visual selections, sending updates
" to Q CLI's MCP server over a Unix domain socket.
" 
" This file serves as the public API layer, delegating to specialized modules:
" - virtual_text.vim: Virtual text annotations
" - highlights.vim: Text highlighting with background colors
" - quickfix.vim: Quickfix list management
" - mcp.vim: MCP server connection and message handling
" - context.vim: Editor context tracking

" User-configurable display characters
if !exists('g:vim_q_connect_first_line_char')
  let g:vim_q_connect_first_line_char = '┤'
endif
if !exists('g:vim_q_connect_continuation_char')
  let g:vim_q_connect_continuation_char = '│'
endif

" Public API: Start context tracking and MCP connection
function! vim_q_connect#start_tracking()
  call vim_q_connect#context#start_tracking()
endfunction

" Public API: Stop context tracking and close MCP connection
function! vim_q_connect#stop_tracking()
  call vim_q_connect#context#stop_tracking()
endfunction

" Public API: Clear all virtual text annotations
function! vim_q_connect#clear_virtual_text()
  call vim_q_connect#virtual_text#clear_virtual_text()
endfunction

" Public API: Clear all highlights
function! vim_q_connect#clear_highlights()
  call vim_q_connect#highlights#clear_highlights()
endfunction

" Public API: Clear quickfix list
function! vim_q_connect#clear_quickfix()
  call vim_q_connect#quickfix#clear_quickfix()
endfunction

" Public API: Annotate quickfix entries as virtual text
function! vim_q_connect#quickfix_annotate()
  call vim_q_connect#quickfix#quickfix_annotate()
endfunction

" Public API: Enable/disable auto-annotation mode
function! vim_q_connect#quickfix_auto_annotate(enable)
  call vim_q_connect#quickfix#quickfix_auto_annotate(a:enable)
endfunction
