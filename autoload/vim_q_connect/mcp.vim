" vim_q_connect/mcp.vim - MCP server connection and message handling
" Manages connection to Q CLI MCP server and handles incoming messages

" Script-local state for MCP connection
let s:mcp_channel = v:null  " Vim channel handle for MCP socket connection

" SECURITY: Sanitize filenames to prevent command injection
" Validates and sanitizes filenames to prevent shell command execution
function! s:sanitize_filename(filename)
  " Reject empty filenames
  if a:filename == ''
    return ''
  endif
  
  " Reject filenames starting with special characters that could be interpreted as commands
  let first_char = a:filename[0]
  if first_char == '!' || first_char == '|' || first_char == ':' || first_char == '%'
    return ''
  endif
  
  " Reject filenames containing shell metacharacters
  if a:filename =~ '[;&$`\\]'
    return ''
  endif
  
  " Reject filenames with protocol schemes (could be URLs/commands)
  if a:filename =~ '^https\?://' || a:filename =~ '^file://' || a:filename =~ '^scp://'
    return ''
  endif
  
  " Normalize path and resolve symlinks
  let normalized = resolve(fnamemodify(a:filename, ':p'))
  
  " Ensure the path is under reasonable directory constraints
  " (This is a basic check - could be made more restrictive based on use case)
  if normalized =~ '^/'
    " Absolute path - ensure it's not trying to escape to system directories
    if normalized =~ '^/\.\./' || normalized =~ '^/etc/' || normalized =~ '^/proc/' || normalized =~ '^/sys/'
      return ''
    endif
  endif
  
  return normalized
endfunction

" Get socket path, using hashed directory structure for long paths
function! vim_q_connect#mcp#get_socket_path()
  let l:cwd_hash = sha256(getcwd())
  let l:socket_dir = '/tmp/vim-q-connect/' . l:cwd_hash
  call mkdir(l:socket_dir, 'p')
  return l:socket_dir . '/sock'
endfunction

" Handle incoming MCP messages from Q CLI
" Currently supports 'goto_line' method for navigation commands
function! vim_q_connect#mcp#handle_mcp_message(channel, msg)
  try
    let data = json_decode(a:msg)
  catch
    echohl ErrorMsg | echo 'Invalid JSON from MCP' | echohl None
    return
  endtry
  
  if !has_key(data, 'method')
    return
  endif
  
  if data.method == 'goto_line'
    if !has_key(data, 'params') || !has_key(data.params, 'line')
      return
    endif
    let line_num = data.params.line
    let filename = get(data.params, 'filename', '')
    call timer_start(0, {-> vim_q_connect#mcp#do_goto_line(line_num, filename)})
  elseif data.method == 'add_virtual_text'
    if !has_key(data, 'params') || !has_key(data.params, 'line') || !has_key(data.params, 'text')
      return
    endif
    let line_num = data.params.line
    let text = data.params.text
    let highlight = get(data.params, 'highlight', 'Comment')
    let emoji = get(data.params, 'emoji', '')
    call timer_start(0, {-> vim_q_connect#virtual_text#add_virtual_text(line_num, text, highlight, emoji)})
  elseif data.method == 'add_virtual_text_batch'
    if !has_key(data, 'params') || !has_key(data.params, 'entries')
      return
    endif
    let entries = data.params.entries
    call timer_start(0, {-> vim_q_connect#virtual_text#add_virtual_text_batch(entries)})
  elseif data.method == 'add_to_quickfix'
    if !has_key(data, 'params') || !has_key(data.params, 'entries')
      return
    endif
    let entries = data.params.entries
    call timer_start(0, {-> vim_q_connect#quickfix#add_to_quickfix(entries)})
  elseif data.method == 'get_annotations'
    let request_id = get(data, 'request_id', '')
    call timer_start(0, {-> vim_q_connect#mcp#do_get_annotations(request_id)})
  elseif data.method == 'get_current_quickfix'
    let request_id = get(data, 'request_id', '')
    call timer_start(0, {-> vim_q_connect#mcp#do_get_current_quickfix(request_id)})
  elseif data.method == 'clear_annotations'
    let filename = get(data.params, 'filename', '')
    call timer_start(0, {-> vim_q_connect#virtual_text#clear_annotations(filename)})
  elseif data.method == 'clear_quickfix'
    call timer_start(0, {-> vim_q_connect#quickfix#do_clear_quickfix()})
  elseif data.method == 'highlight_text'
    if !has_key(data, 'params')
      return
    endif
    let params = data.params
    " Check if params is a list (batch) or dict (single)
    if type(params) == type([])
      call timer_start(0, {-> vim_q_connect#highlights#highlight_text_batch(params)})
    else
      call timer_start(0, {-> vim_q_connect#highlights#highlight_text(params)})
    endif
  elseif data.method == 'clear_highlights'
    let filename = get(data.params, 'filename', '')
    call timer_start(0, {-> vim_q_connect#highlights#do_clear_highlights(filename)})
  endif
endfunction

" Navigate to line/file outside callback context
function! vim_q_connect#mcp#do_goto_line(line_num, filename)
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
    " SECURITY: Validate filename to prevent command injection
    let sanitized_filename = s:sanitize_filename(a:filename)
    if sanitized_filename == ''
      echohl ErrorMsg | echo 'Invalid filename specified' | echohl None
      return
    endif
    
    let target_bufnr = bufnr(sanitized_filename)
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
        execute 'split | edit ' . fnameescape(sanitized_filename)
      else
        execute 'edit ' . fnameescape(sanitized_filename)
      endif
    endif
  endif
  
  call cursor(a:line_num, 1)
  normal! zz
endfunction

" Get current quickfix entry
function! vim_q_connect#mcp#do_get_current_quickfix(request_id)
  if s:mcp_channel == v:null || ch_status(s:mcp_channel) != 'open'
    return
  endif
  
  " Get current quickfix index
  let qf_info = getqflist({'idx': 0, 'items': 1})
  let current_idx = qf_info.idx
  
  if current_idx == 0 || empty(qf_info.items)
    " No quickfix list or empty
    let response = {
      \ "method": "quickfix_entry_response",
      \ "request_id": a:request_id,
      \ "params": {
        \ "error": "No quickfix entries available"
      \ }
    \ }
  else
    let entry = qf_info.items[current_idx - 1]
    let response = {
      \ "method": "quickfix_entry_response",
      \ "request_id": a:request_id,
      \ "params": {
        \ "text": entry.text,
        \ "filename": bufname(entry.bufnr),
        \ "line_number": entry.lnum,
        \ "type": get(entry, 'type', 'I')
      \ }
    \ }
  endif
  
  try
    call ch_sendraw(s:mcp_channel, json_encode(response) . "\n")
  catch
  endtry
endfunction

" Get annotations at current cursor position
function! vim_q_connect#mcp#do_get_annotations(request_id)
  if s:mcp_channel == v:null || ch_status(s:mcp_channel) != 'open'
    return
  endif
  
  " Get annotations up to 20 lines above current position
  let current_line = line('.')
  let annotations = []
  let closest_distance = 999
  
  " Check lines above current position
  for line_num in range(max([1, current_line - 20]), current_line - 1)
    let props = prop_list(line_num, {'type': 'q_virtual_text'})
    if !empty(props)
      let distance = current_line - line_num
      if distance < closest_distance
        " Found closer annotations, reset list
        let closest_distance = distance
        let annotations = []
      endif
      
      if distance == closest_distance
        " Add annotations at this distance
        for prop in props
          if has_key(prop, 'text')
            call add(annotations, {
              \ 'type': prop.type,
              \ 'text': prop.text,
              \ 'line': line_num
            \ })
          endif
        endfor
      endif
    endif
  endfor
  
  " Send response back to MCP server
  let response = {
    \ "method": "annotations_response",
    \ "request_id": a:request_id,
    \ "params": {
      \ "annotations": annotations,
      \ "line": current_line
    \ }
  \ }
  
  try
    call ch_sendraw(s:mcp_channel, json_encode(response) . "\n")
  catch
  endtry
endfunction

" Establish connection to Q CLI MCP server
" Uses Unix domain socket at path defined by g:vim_q_connect_socket_path
function! vim_q_connect#mcp#start_mcp_server()
  if s:mcp_channel != v:null
    return
  endif
  
  " Set socket path at connection time if not configured
  if !exists('g:vim_q_connect_socket_path')
    let g:vim_q_connect_socket_path = vim_q_connect#mcp#get_socket_path()
  endif
  
  try
    " Open nl-mode channel with message callback
    let s:mcp_channel = ch_open('unix:' . g:vim_q_connect_socket_path, {
      \ 'mode': 'nl',
      \ 'callback': 'vim_q_connect#mcp#handle_mcp_message',
      \ 'close_cb': 'vim_q_connect#mcp#on_mcp_close'
    \ })
    
    if ch_status(s:mcp_channel) == 'open'
      echo "Q MCP channel connected"
    else
      let s:mcp_channel = v:null
      echohl WarningMsg | echo "Warning: Cannot connect to Q CLI MCP server. Make sure Q CLI is running." | echohl None
    endif
  catch
    let s:mcp_channel = v:null
    echohl WarningMsg | echo "Warning: Cannot connect to Q CLI MCP server. Make sure Q CLI is running." | echohl None
  endtry
endfunction

" Handle MCP channel closure (called by Vim when socket closes)
function! vim_q_connect#mcp#on_mcp_close(channel)
  echo "MCP channel closed"
  let s:mcp_channel = v:null
  
  " Restore autoread settings if connection was broken unexpectedly
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
endfunction

" Send message to MCP server
function! vim_q_connect#mcp#send_to_mcp(message)
  if s:mcp_channel == v:null || ch_status(s:mcp_channel) != 'open'
    return
  endif
  
  try
    call ch_sendraw(s:mcp_channel, json_encode(a:message) . "\n")
  catch
    " Silently ignore send failures (connection may be closed)
  endtry
endfunction

" Get MCP channel status
function! vim_q_connect#mcp#get_channel()
  return s:mcp_channel
endfunction

" Stop MCP connection
function! vim_q_connect#mcp#stop_mcp_server()
  if s:mcp_channel != v:null
    " Notify server of intentional disconnect
    let disconnect_msg = {"method": "disconnect", "params": {}}
    try
      call ch_sendraw(s:mcp_channel, json_encode(disconnect_msg) . "\n")
    catch
    endtry
    call ch_close(s:mcp_channel)
    let s:mcp_channel = v:null
  endif
endfunction
