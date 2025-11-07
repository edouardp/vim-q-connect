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
  elseif data.method == 'add_to_quickfix'
    let entries = data.params.entries
    call timer_start(0, {-> s:DoAddToQuickfix(entries)})
  elseif data.method == 'get_annotations'
    let request_id = get(data, 'request_id', '')
    call timer_start(0, {-> s:DoGetAnnotations(request_id)})
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
  " Check if text properties are supported
  if !has('textprop')
    return
  endif
  
  " Try to get existing property type, create if it doesn't exist
  try
    let existing = prop_type_get('q_virtual_text')
  catch /E971:/
    " Property type doesn't exist, create it
    call prop_type_add('q_virtual_text', {'highlight': 'qtext'})
  catch
    " Other error, try to create anyway
    try
      call prop_type_add('q_virtual_text', {'highlight': 'qtext'})
    catch
      " If creation fails, we can't use virtual text
    endtry
  endtry
endfunction

" Add virtual text above specified line
function! s:DoAddVirtualText(line_num, text, highlight, emoji)
  " Check if text properties are supported
  if !has('textprop')
    return
  endif
  
  call s:InitPropTypes()
  
  " Always use qtext highlight (ignore passed highlight parameter)
  let l:prop_type = 'q_virtual_text'
  
  " Verify property type exists before using it
  try
    call prop_type_get(l:prop_type)
  catch
    " Property type doesn't exist, skip virtual text
    return
  endtry
  
  " Check for existing props with same text to avoid duplicates
  let existing_props = prop_list(a:line_num, {'type': l:prop_type})
  for prop in existing_props
    if has_key(prop, 'text') && stridx(prop.text, a:text) >= 0
      return  " Skip if similar text already exists
    endif
  endfor
  
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
    let padded_text = formatted_text . repeat(' ', win_width + 30 - strwidth(formatted_text))
    call prop_add(a:line_num, 0, {
      \ 'type': l:prop_type,
      \ 'text': padded_text,
      \ 'text_align': 'above'
    \ })
  endfor
endfunction

" Clear all Q Connect virtual text
function! vim_q_connect#clear_virtual_text()
  try
    call prop_remove({'type': 'q_virtual_text', 'all': 1})
  catch
  endtry
  echo "Q Connect virtual text cleared"
endfunction

" Get annotations at current cursor position
function! s:DoGetAnnotations(request_id)
  if g:mcp_channel == v:null || ch_status(g:mcp_channel) != 'open'
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
    call ch_sendraw(g:mcp_channel, json_encode(response) . "\n")
  catch
  endtry
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

" Public API: Start context tracking and MCP connection
" Sets up autocmds to monitor cursor movement, text changes, and mode changes
function! vim_q_connect#start_tracking()
  let g:context_active = 1
  call StartMCPServer()
  
  " Only proceed if connection successful
  if g:mcp_channel != v:null && ch_status(g:mcp_channel) == 'open'
    " Save current autoread settings
    let g:vim_q_connect_saved_autoread = &autoread
    let g:vim_q_connect_saved_autoread_group = exists('#AutoRead')
    
    " Enable autoread
    set autoread
    
    " Set up autoread autocmds
    augroup AutoRead
      autocmd!
      autocmd FocusGained,BufEnter,CursorHold,CursorHoldI * checktime
    augroup END
  endif
  
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
    " Validate required field
    if !has_key(entry, 'line') || !has_key(entry, 'text')
      continue
    endif
    
    " Find line by text content
    let line_matches = s:FindAllLinesByText(entry.line)
    let line_num = 0
    
    if len(line_matches) == 1
      " Single match - use it
      let line_num = line_matches[0]
    elseif len(line_matches) > 1
      " Multiple matches - use line_number_hint if provided
      if has_key(entry, 'line_number_hint')
        let hint = entry.line_number_hint
        " Find closest match to hint
        let closest_match = line_matches[0]
        let min_distance = abs(closest_match - hint)
        for match in line_matches[1:]
          let distance = abs(match - hint)
          if distance < min_distance
            let min_distance = distance
            let closest_match = match
          endif
        endfor
        let line_num = closest_match
      else
        " No hint - use first match
        let line_num = line_matches[0]
      endif
    else
      " No matches - use line_number_hint if provided
      if has_key(entry, 'line_number_hint')
        let line_num = entry.line_number_hint
      else
        continue  " Skip if no line found and no hint
      endif
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

" Add multiple entries to quickfix list
function! s:DoAddToQuickfix(entries)
  let qf_list = []
  let current_file = expand('%:p')
  let skipped = 0
  
  " First pass: resolve line numbers and build entries
  let resolved_entries = []
  for entry in a:entries
    " Validate required fields
    if !has_key(entry, 'text') || !has_key(entry, 'line')
      let skipped += 1
      continue
    endif
    
    " Get filename first - use provided or current file, expand to full path
    if has_key(entry, 'filename')
      let filename = fnamemodify(entry.filename, ':p')
    else
      let filename = current_file
    endif
    
    " Find line by text content
    let line_matches = s:FindAllLinesByTextInFile(entry.line, filename)
    let line_num = 0
    
    if len(line_matches) == 1
      " Single match - use it
      let line_num = line_matches[0]
    elseif len(line_matches) > 1
      " Multiple matches - use line_number_hint if provided
      if has_key(entry, 'line_number_hint')
        let hint = entry.line_number_hint
        " Find closest match to hint
        let closest_match = line_matches[0]
        let min_distance = abs(closest_match - hint)
        for match in line_matches[1:]
          let distance = abs(match - hint)
          if distance < min_distance
            let min_distance = distance
            let closest_match = match
          endif
        endfor
        let line_num = closest_match
      else
        " No hint - use first match
        let line_num = line_matches[0]
      endif
    else
      " No matches - use line_number_hint if provided
      if has_key(entry, 'line_number_hint')
        let line_num = entry.line_number_hint
      else
        let skipped += 1
        continue
      endif
    endif
    
    " Get entry type - E (error), W (warning), I (info), N (note)
    let entry_type = get(entry, 'type', 'I')
    
    " Add to resolved entries with sort key
    call add(resolved_entries, {
      \ 'filename': filename,
      \ 'lnum': line_num,
      \ 'text': entry.text,
      \ 'type': entry_type,
      \ 'emoji': get(entry, 'emoji', ''),
      \ 'sort_key': filename . ':' . printf('%08d', line_num)
    \ })
  endfor
  
  " Second pass: sort by filename then line number
  call sort(resolved_entries, {a, b -> a.sort_key ==# b.sort_key ? 0 : a.sort_key > b.sort_key ? 1 : -1})
  
  " Third pass: build final quickfix list
  for entry in resolved_entries
    let qf_entry = {
      \ 'filename': entry.filename,
      \ 'lnum': entry.lnum,
      \ 'text': entry.text,
      \ 'type': entry.type
    \ }
    
    " Add emoji to user_data if provided
    if has_key(entry, 'emoji')
      let qf_entry.user_data = {'emoji': entry.emoji}
    endif
    
    call add(qf_list, qf_entry)
  endfor
  
  " Add to quickfix list
  if !empty(qf_list)
    call setqflist(qf_list, 'a')
    " Only open if not already open
    if empty(filter(getwininfo(), 'v:val.quickfix'))
      copen
    endif
    " Auto-annotate current buffer after adding entries
    call vim_q_connect#quickfix_annotate()
    " Set up autocmd for future annotations now that quickfix exists
    call s:SetupQuickfixAutocmd()
    echo printf("Added %d entries to quickfix%s", len(qf_list), skipped > 0 ? printf(" (%d skipped)", skipped) : "")
  elseif skipped > 0
    echohl WarningMsg | echo printf("All %d entries skipped - no valid entries", skipped) | echohl None
  endif
endfunction

" Find all line numbers by searching for text in a specific file
function! s:FindAllLinesByTextInFile(line_text, filename)
  " If it's the current file, search directly
  if a:filename == expand('%:p')
    return s:FindAllLinesByText(a:line_text)
  endif
  
  " Get or create buffer for the file
  let bufnr = bufnr(a:filename)
  if bufnr == -1
    " Buffer doesn't exist, create it
    let bufnr = bufadd(a:filename)
  endif
  
  " Load buffer content without displaying it
  call bufload(bufnr)
  
  " Search through buffer lines
  let lines = getbufline(bufnr, 1, '$')
  let matches = []
  for i in range(len(lines))
    let line = lines[i]
    if line ==# a:line_text || trim(line) ==# trim(a:line_text)
      call add(matches, i + 1)  " Line numbers are 1-indexed
    endif
  endfor
  
  return matches
endfunction

" Set up autocmd for quickfix annotations after first quickfix list is created
function! s:SetupQuickfixAutocmd()
  " Only set up once
  if exists('g:quickfix_autocmd_setup')
    return
  endif
  let g:quickfix_autocmd_setup = 1
  
  augroup QQuickfixAnnotate
    autocmd!
    autocmd BufEnter * if !empty(getqflist()) | call vim_q_connect#quickfix_annotate() | endif
  augroup END
endfunction

" Find all line numbers by searching for text content in current buffer
function! s:FindAllLinesByText(line_text)
  let total_lines = line('$')
  let matches = []
  for i in range(1, total_lines)
    let line = getline(i)
    if line ==# a:line_text || trim(line) ==# trim(a:line_text)
      call add(matches, i)
    endif
  endfor
  return matches
endfunction

" Annotate quickfix entries as virtual text
function! vim_q_connect#quickfix_annotate()
  let qf_list = getqflist()
  let annotated = 0
  
  for entry in qf_list
    if has_key(entry, 'bufnr') && has_key(entry, 'lnum') && has_key(entry, 'text')
      " Use emoji from user_data if available, otherwise fall back to type-based emoji
      let emoji = ''
      if has_key(entry, 'user_data') && type(entry.user_data) == v:t_dict && has_key(entry.user_data, 'emoji')
        let emoji = entry.user_data.emoji
      else
        let emoji = entry.type ==# 'E' ? '❌' : entry.type ==# 'W' ? '⚠️' : '💡'
      endif
      
      " Switch to the buffer temporarily to add virtual text
      let current_buf = bufnr('%')
      if entry.bufnr != current_buf
        execute 'buffer ' . entry.bufnr
      endif
      
      call s:DoAddVirtualText(entry.lnum, entry.text, 'Comment', emoji)
      let annotated += 1
      
      " Switch back to original buffer if we changed
      if entry.bufnr != current_buf
        execute 'buffer ' . current_buf
      endif
    endif
  endfor
  
  if annotated > 0
    echo "Annotated " . annotated . " quickfix entries across all buffers"
  endif
endfunction
