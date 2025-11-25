" vim_q_connect/context.vim - Editor context tracking for vim-q-connect
" Monitors cursor position, selections, and file changes

" Script-local state variables
let s:context_active = 0                  " Flag to control context tracking
let s:current_filename = ''               " Currently tracked filename
let s:current_line = 0                    " Current cursor line number
let s:visual_start = 0                    " Start line of visual selection (0 = no selection)
let s:visual_end = 0                      " End line of visual selection (0 = no selection)
let s:visual_start_col = 0                " Start column of visual selection (0 = no selection)
let s:visual_end_col = 0                  " End column of visual selection (0 = no selection)
let s:visual_start_line_len = 0           " Length of start line (0 = no selection)
let s:visual_end_line_len = 0             " Length of end line (0 = no selection)

" Send current editor context to Q CLI MCP server
" Formats context as markdown with filename, line numbers, and code content
function! vim_q_connect#context#push_context_update()
  " Skip if no active connection
  let channel = vim_q_connect#mcp#get_channel()
  if channel == v:null || ch_status(channel) != 'open'
    return
  endif
  
  " Handle different buffer types and selection states
  if &buftype == 'terminal'
    let context = "The user is in a Terminal buffer - no context available"
    let buffer_type = 'terminal'
  elseif &buftype == 'nofile' && exists('b:NERDTree')
    let context = "The user in the NERDTree file browser - no context available"
    let buffer_type = 'nerdtree'
  elseif &buftype != ''
    let context = "The user is in a non-text buffer (" . &buftype . ") - no context available"
    let buffer_type = &buftype
  elseif s:visual_start > 0 && s:visual_end > 0
    " Visual selection active - send selected lines
    let lines = getline(s:visual_start, s:visual_end)
    let context = "# " . s:current_filename . "\n\nLines " . s:visual_start . "-" . s:visual_end . ":\n```\n" . join(lines, "\n") . "\n```"
    let buffer_type = 'text'
  else
    " Normal mode - send current line with context
    let line_content = getline(s:current_line)
    let total_lines = line('$')
    let context = "# " . s:current_filename . "\n\nLine " . s:current_line . "/" . total_lines . ":\n```\n" . line_content . "\n```"
    let buffer_type = 'text'
  endif
  
  " Build MCP message with comprehensive file metadata
  let update = {
    \ "method": "context_update",
    \ "params": {
      \ "filename": s:current_filename,
      \ "line": s:current_line,
      \ "visual_start": s:visual_start,
      \ "visual_end": s:visual_end,
      \ "visual_start_col": s:visual_start_col,
      \ "visual_end_col": s:visual_end_col,
      \ "visual_start_line_len": s:visual_start_line_len,
      \ "visual_end_line_len": s:visual_end_line_len,
      \ "total_lines": line('$'),
      \ "modified": &modified ? 1 : 0,
      \ "encoding": &fileencoding != '' ? &fileencoding : &encoding,
      \ "line_endings": &fileformat,
      \ "buffer_type": buffer_type,
      \ "context": context
    \ }
  \ }
  
  call vim_q_connect#mcp#send_to_mcp(update)
endfunction

" Internal: Update context state and push to MCP server
" Called by autocmds on cursor movement, text changes, etc.
function! vim_q_connect#context#write_context()
  " Skip if tracking disabled
  if !s:context_active
    return
  endif
  
  " Update current state
  let s:current_filename = expand('%:.')
  let s:current_line = line('.')
  
  " Detect and track visual selection bounds
  if mode() =~# '[vV\<C-v>]'
    let s:visual_start = line('v')
    let s:visual_end = line('.')
    let s:visual_start_line_len = col([s:visual_start, '$']) - 1
    let s:visual_end_line_len = col([s:visual_end, '$']) - 1
    
    " For line-wise visual mode (V), set columns to indicate full lines
    if mode() ==# 'V'
      let s:visual_start_col = 1
      let s:visual_end_col = s:visual_end_line_len
    else
      " For character-wise (v) and block-wise (^V) modes, use actual cursor positions
      let s:visual_start_col = col('v')
      let s:visual_end_col = col('.')
    endif
    
    " Ensure start <= end for consistent ordering
    if s:visual_start > s:visual_end || (s:visual_start == s:visual_end && s:visual_start_col > s:visual_end_col)
      let temp = s:visual_start
      let s:visual_start = s:visual_end
      let s:visual_end = temp
      let temp = s:visual_start_col
      let s:visual_start_col = s:visual_end_col
      let s:visual_end_col = temp
      let temp = s:visual_start_line_len
      let s:visual_start_line_len = s:visual_end_line_len
      let s:visual_end_line_len = temp
    endif
  else
    " Clear selection state when not in visual mode
    let s:visual_start = 0
    let s:visual_end = 0
    let s:visual_start_col = 0
    let s:visual_end_col = 0
    let s:visual_start_line_len = 0
    let s:visual_end_line_len = 0
  endif
  
  call vim_q_connect#context#push_context_update()
  
  " Check for cursor in highlighted text
  call vim_q_connect#highlights#check_cursor_in_highlight()
endfunction

" Internal: Annotate current buffer with quickfix entries
function! vim_q_connect#context#annotate_current_buffer()
  call vim_q_connect#quickfix#annotate_current_buffer()
endfunction

" Public API: Start context tracking and MCP connection
" Sets up autocmds to monitor cursor movement, text changes, and mode changes
function! vim_q_connect#context#start_tracking()
  let s:context_active = 1
  call vim_q_connect#mcp#start_mcp_server()
  
  " Only proceed if connection successful
  let channel = vim_q_connect#mcp#get_channel()
  if channel != v:null && ch_status(channel) == 'open'
    " Save current autoread settings
    let g:vim_q_connect_saved_autoread = &autoread
    let g:vim_q_connect_saved_autoread_group = exists('#AutoRead')
    
    " Enable autoread
    set autoread
    
    " Set up autoread autocmds
    augroup AutoRead
      autocmd!
      autocmd FocusGained,BufEnter,CursorHold,CursorHoldI * checktime
      autocmd FileChangedShellPost * call vim_q_connect#context#annotate_current_buffer()
    augroup END
  endif
  
  call vim_q_connect#context#write_context()
  
  " Monitor all relevant editor events for context updates
  augroup VimLLMContext
    autocmd!
    autocmd CursorMoved,CursorMovedI,ModeChanged * call vim_q_connect#context#write_context()
    autocmd TextChanged,TextChangedI * call vim_q_connect#context#write_context()
  augroup END
endfunction

" Public API: Stop context tracking and close MCP connection
" Sends disconnect message and cleans up resources
function! vim_q_connect#context#stop_tracking()
  call vim_q_connect#mcp#stop_mcp_server()
  let s:context_active = 0
  
  " Restore autoread settings if they were saved
  if exists('g:vim_q_connect_saved_autoread')
    let &autoread = g:vim_q_connect_saved_autoread
    unlet g:vim_q_connect_saved_autoread
    
    " Remove AutoRead group if it didn't exist before
    if exists('g:vim_q_connect_saved_autoread_group') && !g:vim_q_connect_saved_autoread_group
      augroup AutoRead
        autocmd!
      augroup END
      augroup! AutoRead
      unlet g:vim_q_connect_saved_autoread_group
    endif
  endif
  
  " Remove all autocmds
  augroup VimLLMContext
    autocmd!
  augroup END
  
  echo "Q MCP channel disconnected"
endfunction
