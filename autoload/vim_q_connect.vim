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
  let data = json_decode(a:msg)
  
  if data.method == 'goto_line'
    let line_num = data.params.line
    let filename = get(data.params, 'filename', '')
    call timer_start(0, {-> s:DoGotoLine(line_num, filename)})
  elseif data.method == 'add_virtual_text'
    let line_num = data.params.line
    let text = data.params.text
    let highlight = get(data.params, 'highlight', 'Comment')
    let emoji = get(data.params, 'emoji', '')
    call timer_start(0, {-> s:DoAddVirtualText(line_num, text, highlight, emoji)})
  elseif data.method == 'add_virtual_text_batch'
    let entries = data.params.entries
    call timer_start(0, {-> s:DoAddVirtualTextBatch(entries)})
  endif
endfunction

" Navigate to line/file outside callback context
function! s:DoGotoLine(line_num, filename)
  " If in terminal/nofile/empty buffer, switch to first file buffer
  if &buftype != ''
    for i in range(1, winnr('$'))
      let buftype = getwinvar(i, '&buftype')
      let is_nerdtree = getwinvar(i, 'b:NERDTree', 0)
      if buftype == '' && !is_nerdtree
        execute i . 'wincmd w'
        break
      endif
    endfor
  endif
  
  " If filename specified, find window with that buffer
  if a:filename != ''
    let target_bufnr = bufnr(a:filename)
    if target_bufnr != -1
      " Check all tabs for this buffer
      for tabnr in range(1, tabpagenr('$'))
        for winnr in range(1, tabpagewinnr(tabnr, '$'))
          if tabpagebuflist(tabnr)[winnr-1] == target_bufnr
            execute 'tabnext ' . tabnr
            execute winnr . 'wincmd w'
            break
          endif
        endfor
        if tabpagenr() == tabnr && winnr() <= tabpagewinnr(tabnr, '$') && bufnr('%') == target_bufnr
          break
        endif
      endfor
      " If not found in any window, open in current tab
      if bufnr('%') != target_bufnr
        if &modified
          execute 'split | buffer ' . target_bufnr
        else
          execute 'buffer ' . target_bufnr
        endif
      endif
    else
      if &modified
        execute 'split | edit ' . fnameescape(a:filename)
      else
        execute 'edit ' . fnameescape(a:filename)
      endif
    endif
  endif
  
  execute a:line_num
  normal! zz
endfunction

" Initialize property types for virtual text
function! s:InitPropTypes()
  if empty(prop_type_get('q_connect'))
    call prop_type_add('q_connect', {'highlight': 'Comment'})
  endif
  if empty(prop_type_get('q_connect_warning'))
    call prop_type_add('q_connect_warning', {'highlight': 'WarningMsg'})
  endif
  if empty(prop_type_get('q_connect_error'))
    call prop_type_add('q_connect_error', {'highlight': 'ErrorMsg'})
  endif
  if empty(prop_type_get('q_connect_add'))
    call prop_type_add('q_connect_add', {'highlight': 'DiffAdd'})
  endif
  if empty(prop_type_get('q_connect_qtext'))
    call prop_type_add('q_connect_qtext', {'highlight': 'qtext', 'text_wrap': 'wrap'})
  endif
endfunction

" Add virtual text above specified line
function! s:DoAddVirtualText(line_num, text, highlight, emoji)
  call s:InitPropTypes()
  
  let l:prop_type = 'q_connect'
  if a:highlight == 'WarningMsg'
    let l:prop_type = 'q_connect_warning'
  elseif a:highlight == 'ErrorMsg'
    let l:prop_type = 'q_connect_error'
  elseif a:highlight == 'DiffAdd'
    let l:prop_type = 'q_connect_add'
  elseif a:highlight == 'qtext'
    let l:prop_type = 'q_connect_qtext'
  endif
  
  " Use provided emoji or default to fullwidth Q
  let display_emoji = empty(a:emoji) ? 'Ｑ' : a:emoji
  
  " Split text on newlines for multi-line virtual text
  let lines = split(a:text, '\n', 1)
  let win_width = winwidth(0)
  
  for i in range(len(lines))
    let line_text = lines[i]
    
    " Format first line with emoji and connector, others with continuation
    if i == 0
      let formatted_text = ' ' . display_emoji . ' ┤ ' . line_text
    else
      " Calculate spacing to align with first line text
      let spacing = strdisplaywidth(' ' . display_emoji . ' ')
      let formatted_text = repeat(' ', spacing) . '│ ' . line_text
    endif
    
    " Pad text to window width + 30 chars for full-line background
    let padded_text = formatted_text . repeat(' ', win_width + 30 - len(formatted_text))
    call prop_add(a:line_num, 0, {
      \ 'type': l:prop_type,
      \ 'text': padded_text,
      \ 'text_align': 'above'
    \ })
  endfor
endfunction

" Clear all Q Connect virtual text
function! QClearVirtualText()
  call prop_remove({'type': 'q_connect', 'all': 1})
  call prop_remove({'type': 'q_connect_warning', 'all': 1})
  call prop_remove({'type': 'q_connect_error', 'all': 1})
  call prop_remove({'type': 'q_connect_add', 'all': 1})
  call prop_remove({'type': 'q_connect_qtext', 'all': 1})
  echo "Q Connect virtual text cleared"
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
    let context = "The user is in a Terminal buffer - no context available"
    let buffer_type = 'terminal'
  elseif &buftype == 'nofile' && exists('b:NERDTree')
    let context = "The user in the NERDTree file browser - no context available"
    let buffer_type = 'nerdtree'
  elseif &buftype != ''
    let context = "The user is in a non-text buffer (" . &buftype . ") - no context available"
    let buffer_type = &buftype
  elseif g:visual_start > 0 && g:visual_end > 0
    " Visual selection active - send selected lines
    let lines = getline(g:visual_start, g:visual_end)
    let context = "# " . g:current_filename . "\n\nLines " . g:visual_start . "-" . g:visual_end . ":\n```\n" . join(lines, "\n") . "\n```"
    let buffer_type = 'text'
  else
    " Normal mode - send current line with context
    let line_content = getline(g:current_line)
    let total_lines = line('$')
    let context = "# " . g:current_filename . "\n\nLine " . g:current_line . "/" . total_lines . ":\n```\n" . line_content . "\n```"
    let buffer_type = 'text'
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
      \ "buffer_type": buffer_type,
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
  
  " Set socket path at connection time if not configured
  if !exists('g:vim_q_connect_socket_path')
    let g:vim_q_connect_socket_path = getcwd() . '/.vim-q-mcp.sock'
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
  " Skip if tracking disabled
  if !g:context_active
    return
  endif
  
  " Update current state
  let g:current_filename = expand('%:.')
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

" Add multiple virtual text entries efficiently
function! s:DoAddVirtualTextBatch(entries)
  for entry in a:entries
    " Determine line number - support both 'line_number' and 'line' keys
    if has_key(entry, 'line_number')
      let line_num = entry.line_number
    elseif has_key(entry, 'line') && type(entry.line) == v:t_number
      let line_num = entry.line
    elseif has_key(entry, 'line') && type(entry.line) == v:t_string
      " Search for the line text in the current buffer
      let line_num = s:FindLineByText(entry.line)
      if line_num == 0
        continue  " Skip if line not found
      endif
    else
      continue  " Skip entry if no valid line specification
    endif
    
    let text = entry.text
    let highlight = get(entry, 'highlight', 'Comment')
    let emoji = get(entry, 'emoji', '')
    call s:DoAddVirtualText(line_num, text, highlight, emoji)
  endfor
endfunction

" Find line number by searching for text content
function! s:FindLineByText(line_text)
  let total_lines = line('$')
  for i in range(1, total_lines)
    if getline(i) ==# a:line_text
      return i
    endif
  endfor
  return 0  " Not found
endfunction
