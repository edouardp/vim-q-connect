" Autoload functions for vim-q-connect
" 
" This plugin provides editor context to Q CLI via Model Context Protocol (MCP).
" It tracks cursor position, file changes, and visual selections, sending updates
" to Q CLI's MCP server over a Unix domain socket.

" Global state variables
let g:context_active = 0      " Flag to control context tracking
let g:mcp_channel = v:null    " Vim channel handle for MCP socket connection
let g:current_filename = ''   " Currently tracked filename
let g:current_line = 0        " Current cursor line number
let g:visual_start = 0        " Start line of visual selection (0 = no selection)
let g:visual_end = 0          " End line of visual selection (0 = no selection)

" Handle incoming MCP messages from Q CLI
" Currently supports 'goto_line' method for navigation commands
function! HandleMCPMessage(channel, msg)
  echo "DEBUG: Received MCP message: " . string(a:msg)
  
  " In nl mode, messages are strings - parse JSON
  let data = json_decode(a:msg)
  
  echo "DEBUG: Parsed data: " . string(data)
  
  if data.method == 'goto_line'
    echo "DEBUG: Processing goto_line command"
    let line_num = data.params.line
    let filename = get(data.params, 'filename', '')
    
    echo "DEBUG: Going to line " . line_num . " in file '" . filename . "'"
    
    " Switch to specified file if provided
    if filename != ''
      execute 'edit ' . filename
    endif
    " Jump to line and center it in viewport
    execute line_num
    normal! zz
    
    echo "DEBUG: Navigation completed"
  else
    echo "DEBUG: Unknown method: " . get(data, 'method', 'no method')
  endif
endfunction

" Send current editor context to Q CLI MCP server
" Formats context as markdown with filename, line numbers, and code content
function! PushContextUpdate()
  " Skip if no active connection
  if g:mcp_channel == v:null || ch_status(g:mcp_channel) != 'open'
    return
  endif
  
  " Handle different buffer types and selection states
  if &buftype == 'terminal'
    let context = "Terminal buffer - no context available"
  elseif g:visual_start > 0 && g:visual_end > 0
    " Visual selection active - send selected lines
    let lines = getline(g:visual_start, g:visual_end)
    let context = "# " . g:current_filename . "\n\nLines " . g:visual_start . "-" . g:visual_end . ":\n```\n" . join(lines, "\n") . "\n```"
  else
    " Normal mode - send current line with context
    let line_content = getline(g:current_line)
    let total_lines = line('$')
    let context = "# " . g:current_filename . "\n\nLine " . g:current_line . "/" . total_lines . ":\n```\n" . line_content . "\n```"
  endif
  
  " Build MCP message with comprehensive file metadata
  let update = {
    \ "method": "context_update",
    \ "params": {
      \ "filename": g:current_filename,
      \ "line": g:current_line,
      \ "visual_start": g:visual_start,
      \ "visual_end": g:visual_end,
      \ "total_lines": line('$'),
      \ "modified": &modified ? 1 : 0,
      \ "encoding": &fileencoding != '' ? &fileencoding : &encoding,
      \ "line_endings": &fileformat,
      \ "context": context
    \ }
  \ }
  
  " Send as raw JSON with newline delimiter (MCP protocol requirement)
  try
    call ch_sendraw(g:mcp_channel, json_encode(update) . "\n")
  catch
    " Silently ignore send failures (connection may be closed)
  endtry
endfunction

" Establish connection to Q CLI MCP server
" Uses Unix domain socket at path defined by g:vim_q_connect_socket_path
function! StartMCPServer()
  if g:mcp_channel != v:null
    return
  endif
  
  try
    " Open nl-mode channel with message callback
    let g:mcp_channel = ch_open('unix:' . g:vim_q_connect_socket_path, {
      \ 'mode': 'nl',
      \ 'callback': 'HandleMCPMessage',
      \ 'close_cb': 'OnMCPClose'
    \ })
    
    if ch_status(g:mcp_channel) == 'open'
      echo "Q MCP channel connected"
    else
      let g:mcp_channel = v:null
      echohl WarningMsg | echo "Warning: Cannot connect to Q CLI MCP server. Make sure Q CLI is running." | echohl None
    endif
  catch
    let g:mcp_channel = v:null
    echohl WarningMsg | echo "Warning: Cannot connect to Q CLI MCP server. Make sure Q CLI is running." | echohl None
  endtry
endfunction

" Handle MCP channel closure (called by Vim when socket closes)
function! OnMCPClose(channel)
  echo "MCP channel closed"
  let g:mcp_channel = v:null
endfunction

" Public API: Start context tracking and MCP connection
" Sets up autocmds to monitor cursor movement, text changes, and mode changes
function! vim_q_connect#start_tracking()
  let g:context_active = 1
  call StartMCPServer()
  call WriteContext()
  
  " Monitor all relevant editor events for context updates
  augroup VimLLMContext
    autocmd!
    autocmd CursorMoved,CursorMovedI,ModeChanged * call WriteContext()
    autocmd TextChanged,TextChangedI * call WriteContext()
  augroup END
endfunction

" Public API: Stop context tracking and close MCP connection
" Sends disconnect message and cleans up resources
function! vim_q_connect#stop_tracking()
  if g:mcp_channel != v:null
    " Notify server of intentional disconnect
    let disconnect_msg = {"method": "disconnect", "params": {}}
    try
      call ch_sendraw(g:mcp_channel, json_encode(disconnect_msg) . "\n")
    catch
    endtry
    call ch_close(g:mcp_channel)
    let g:mcp_channel = v:null
  endif
  let g:context_active = 0
  
  " Remove all autocmds
  augroup VimLLMContext
    autocmd!
  augroup END
  
  echo "Q MCP channel disconnected"
endfunction

" Internal: Update context state and push to MCP server
" Called by autocmds on cursor movement, text changes, etc.
function! WriteContext()
  " Skip if tracking disabled or in terminal buffer
  if !g:context_active || &buftype == 'terminal'
    return
  endif
  
  " Update current state
  let g:current_filename = expand('%:t')
  let g:current_line = line('.')
  
  " Detect and track visual selection bounds
  if mode() =~# '[vV\<C-v>]'
    let g:visual_start = line('v')
    let g:visual_end = line('.')
    " Ensure start <= end for consistent ordering
    if g:visual_start > g:visual_end
      let temp = g:visual_start
      let g:visual_start = g:visual_end
      let g:visual_end = temp
    endif
  else
    " Clear selection state when not in visual mode
    let g:visual_start = 0
    let g:visual_end = 0
  endif
  
  call PushContextUpdate()
endfunction
