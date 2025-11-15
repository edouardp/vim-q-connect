" Autoload functions for vim-q-connect
" 
" This plugin provides editor context to Q CLI via Model Context Protocol (MCP).
" It tracks cursor position, file changes, and visual selections, sending updates
" to Q CLI's MCP server over a Unix domain socket.

" Script-local state variables
let s:context_active = 0      " Flag to control context tracking
let s:mcp_channel = v:null    " Vim channel handle for MCP socket connection
let s:current_filename = ''   " Currently tracked filename
let s:current_line = 0        " Current cursor line number
let s:visual_start = 0        " Start line of visual selection (0 = no selection)
let s:visual_end = 0          " End line of visual selection (0 = no selection)
let s:highlight_virtual_text = {}  " Map of prop_id -> virtual_text for highlights
let s:highlight_colors = {}        " Map of prop_id -> color for highlights

" User-configurable display characters
if !exists('g:vim_q_connect_first_line_char')
  let g:vim_q_connect_first_line_char = '┤'
endif
if !exists('g:vim_q_connect_continuation_char')
  let g:vim_q_connect_continuation_char = '│'
endif

" Handle incoming MCP messages from Q CLI
" Currently supports 'goto_line' method for navigation commands
function! HandleMCPMessage(channel, msg)
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
    call timer_start(0, {-> s:DoGotoLine(line_num, filename)})
  elseif data.method == 'add_virtual_text'
    if !has_key(data, 'params') || !has_key(data.params, 'line') || !has_key(data.params, 'text')
      return
    endif
    let line_num = data.params.line
    let text = data.params.text
    let highlight = get(data.params, 'highlight', 'Comment')
    let emoji = get(data.params, 'emoji', '')
    call timer_start(0, {-> s:DoAddVirtualText(line_num, text, highlight, emoji)})
  elseif data.method == 'add_virtual_text_batch'
    if !has_key(data, 'params') || !has_key(data.params, 'entries')
      " echom "vim-q-connect: add_virtual_text_batch missing params or entries"
      return
    endif
    let entries = data.params.entries
    " echom "vim-q-connect: Processing " . len(entries) . " virtual text entries"
    call timer_start(0, {-> s:DoAddVirtualTextBatch(entries)})
  elseif data.method == 'add_to_quickfix'
    if !has_key(data, 'params') || !has_key(data.params, 'entries')
      return
    endif
    let entries = data.params.entries
    call timer_start(0, {-> s:DoAddToQuickfix(entries)})
  elseif data.method == 'get_annotations'
    let request_id = get(data, 'request_id', '')
    call timer_start(0, {-> s:DoGetAnnotations(request_id)})
  elseif data.method == 'get_current_quickfix'
    let request_id = get(data, 'request_id', '')
    call timer_start(0, {-> s:DoGetCurrentQuickfix(request_id)})
  elseif data.method == 'clear_annotations'
    let filename = get(data.params, 'filename', '')
    call timer_start(0, {-> s:DoClearAnnotations(filename)})
  elseif data.method == 'clear_quickfix'
    call timer_start(0, {-> s:DoClearQuickfix()})
  elseif data.method == 'highlight_text'
    if !has_key(data, 'params')
      return
    endif
    let params = data.params
    call timer_start(0, {-> s:DoHighlightText(params)})
  elseif data.method == 'clear_highlights'
    let filename = get(data.params, 'filename', '')
    call timer_start(0, {-> s:DoClearHighlights(filename)})
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

" Initialize property types for virtual text and highlighting
function! s:InitPropTypes()
  " Check if text properties are supported
  if !has('textprop')
    return
  endif
  
  " Only create the property type if it doesn't already exist
  if empty(prop_type_get('q_virtual_text'))
    call prop_type_add('q_virtual_text', {'highlight': 'qtext'})
  endif
  
  " Initialize highlight virtual text property type
  if empty(prop_type_get('q_highlight_virtual'))
    call prop_type_add('q_highlight_virtual', {'highlight': 'qtext'})
  endif
  
  " Create property types for each virtual text color
  let highlight_colors = ['yellow', 'orange', 'pink', 'green', 'blue', 'purple']
  for color in highlight_colors
    let prop_name = 'q_highlight_virtual_' . color
    let hl_name = 'QHighlightVirtual' . substitute(color, '^.', '\U&', '')
    if empty(prop_type_get(prop_name)) && hlexists(hl_name)
      call prop_type_add(prop_name, {'highlight': hl_name})
    endif
  endfor
  
  " Define highlight groups and initialize highlight property types
  let highlight_colors = ['yellow', 'orange', 'pink', 'green', 'blue', 'purple']
  for color in highlight_colors
    let hl_name = 'QHighlight' . substitute(color, '^\w', '\u&', '')
    let prop_name = 'q_highlight_' . color
    
    " Define highlight group if it doesn't exist
    if !hlexists(hl_name)
      if color == 'yellow'
        execute 'highlight ' . hl_name . ' ctermbg=yellow ctermfg=black guibg=yellow guifg=black cterm=bold gui=bold'
      elseif color == 'orange'
        execute 'highlight ' . hl_name . ' ctermbg=red ctermfg=white guibg=orange guifg=black cterm=bold gui=bold'
      elseif color == 'pink'
        execute 'highlight ' . hl_name . ' ctermbg=magenta ctermfg=white guibg=pink guifg=black cterm=bold gui=bold'
      elseif color == 'green'
        execute 'highlight ' . hl_name . ' ctermbg=green ctermfg=black guibg=lightgreen guifg=black cterm=bold gui=bold'
      elseif color == 'blue'
        execute 'highlight ' . hl_name . ' ctermbg=blue ctermfg=white guibg=lightblue guifg=black cterm=bold gui=bold'
      elseif color == 'purple'
        execute 'highlight ' . hl_name . ' ctermbg=magenta ctermfg=white guibg=plum guifg=black cterm=bold gui=bold'
      endif
    endif
    
    " Create property type
    if empty(prop_type_get(prop_name))
      call prop_type_add(prop_name, {'highlight': hl_name})
    endif
  endfor
endfunction

" Extract emoji from beginning of text
function! s:ExtractEmoji(text)
  let emoji = ''
  let idx = 0
  while idx < strchars(a:text)
    let char = strcharpart(a:text, idx, 1)
    let codepoint = char2nr(char)
    if (codepoint >= 0x1F300 && codepoint <= 0x1F9FF) || 
     \ (codepoint >= 0x2600 && codepoint <= 0x27BF) ||
     \ (codepoint >= 0x2300 && codepoint <= 0x23FF) ||
     \ (codepoint >= 0x2100 && codepoint <= 0x214F) ||
     \ (codepoint >= 0xFE00 && codepoint <= 0xFE0F)
      let emoji .= char
      let idx += 1
    else
      break
    endif
  endwhile
  return emoji
endfunction

" Add virtual text above specified line
function! s:DoAddVirtualText(line_num, text, highlight, emoji)
  try
    " Check if text properties are supported
    if !has('textprop')
      echom "vim-q-connect: Text properties not supported"
      return
    endif
    
    " Validate line number
    if a:line_num <= 0 || a:line_num > line('$')
      " echom "vim-q-connect: Invalid line number " . a:line_num . " (file has " . line('$') . " lines)"
      return
    endif
    
    call s:InitPropTypes()
    
    " Always use qtext highlight (ignore passed highlight parameter)
    let l:prop_type = 'q_virtual_text'
    
    " Check for existing props with same text to avoid duplicates
    let existing_props = prop_list(a:line_num, {'type': l:prop_type})
    
    " Check if any existing prop contains the first line of our text
    let first_line = split(a:text, '\n', 1)[0]
    for prop in existing_props
      if has_key(prop, 'text') && stridx(prop.text, first_line) >= 0
        " echom "vim-q-connect: Duplicate virtual text detected at line " . a:line_num . ", skipping"
        return
      endif
    endfor
    
    " Use provided emoji or default to fullwidth Q
    let display_emoji = empty(a:emoji) ? 'Ｑ' : a:emoji
    
    " Split text on newlines for multi-line virtual text
    let lines = split(a:text, '\n', 1)
    let win_width = winwidth(0)
    
    " echom "vim-q-connect: Adding virtual text at line " . a:line_num . " with " . len(lines) . " lines"
    
    for i in range(len(lines))
      let line_text = lines[i]
      
      " Format first line with emoji and connector, others with continuation
      if i == 0
        let formatted_text = ' ' . display_emoji . ' ' . g:vim_q_connect_first_line_char . ' ' . line_text
      else
        " Calculate spacing to align with first line text
        let spacing = strdisplaywidth(' ' . display_emoji . ' ')
        let formatted_text = repeat(' ', spacing) . g:vim_q_connect_continuation_char . ' ' . line_text
      endif
      
      " Pad text to window width + 30 chars for full-line background
      let padded_text = formatted_text . repeat(' ', win_width + 30 - strwidth(formatted_text))
      
      try
        call prop_add(a:line_num, 0, {
          \ 'type': l:prop_type,
          \ 'text': padded_text,
          \ 'text_align': 'above'
        \ })
      catch
        " echom "vim-q-connect: Error adding prop at line " . a:line_num . ": " . v:exception
        throw v:exception
      endtry
    endfor
    
    " echom "vim-q-connect: Successfully added virtual text at line " . a:line_num
  catch
    " echom "vim-q-connect: Error in DoAddVirtualText: " . v:exception . " at " . v:throwpoint
  endtry
endfunction

" Clear all Q Connect virtual text
function! vim_q_connect#clear_virtual_text()
  call prop_remove({'type': 'q_virtual_text', 'all': 1})
endfunction

" Clear all Q Connect highlights
function! vim_q_connect#clear_highlights()
  call s:DoClearHighlights('')
endfunction

" Clear quickfix list and annotations
function! vim_q_connect#clear_quickfix()
  call s:DoClearQuickfix()
endfunction

" Clear annotations from specific file or current buffer
function! s:DoClearAnnotations(filename)
  if empty(a:filename)
    " Clear from current buffer
    call prop_remove({'type': 'q_virtual_text', 'all': 1})
  else
    " Clear from specific file
    let target_bufnr = bufnr(a:filename)
    if target_bufnr != -1
      call prop_remove({'type': 'q_virtual_text', 'all': 1, 'bufnr': target_bufnr})
    endif
  endif
endfunction

" Clear quickfix list
function! s:DoClearQuickfix()
  " TODO: Only remove annotations that were added for quickfix entries, not all annotations
  call prop_remove({'type': 'q_virtual_text', 'all': 1})
  call setqflist([])
  silent! cclose
endfunction

" Highlight text with background color and bold formatting
function! s:DoHighlightText(params)
  try
    if !has('textprop')
      return
    endif
    
    call s:InitPropTypes()
    
    " Get parameters
    let start_line = get(a:params, 'start_line', 0)
    let end_line = get(a:params, 'end_line', start_line)
    let start_col = get(a:params, 'start_col', 1)
    let end_col = get(a:params, 'end_col', -1)
    let color = get(a:params, 'color', 'yellow')
    let virtual_text = get(a:params, 'virtual_text', '')
    
    " Validate parameters
    if start_line <= 0 || start_line > line('$')
      return
    endif
    if end_line <= 0 || end_line > line('$')
      let end_line = start_line
    endif
    if end_col == -1
      let end_col = len(getline(end_line)) + 1
    endif
    
    " Build property type name
    let prop_type = 'q_highlight_' . color
    
    " Generate unique ID for this property
    if !exists('s:next_highlight_id')
      let s:next_highlight_id = 1
    endif
    let prop_id = s:next_highlight_id
    let s:next_highlight_id += 1
    
    " Create text property
    let prop_options = {'type': prop_type, 'id': prop_id}
    if end_line > start_line
      let prop_options.end_lnum = end_line
      let prop_options.end_col = end_col
    elseif end_col > start_col && end_col <= len(getline(start_line)) + 1
      " Single line partial highlight
      let prop_options.length = end_col - start_col
    endif
    
    " Add the property
    call prop_add(start_line, start_col, prop_options)
    
    " Store start line for this prop ID (for virtual text placement)
    if !exists('s:highlight_start_lines')
      let s:highlight_start_lines = {}
    endif
    let s:highlight_start_lines[prop_id] = start_line
    
    " Store virtual text and color in script-local dicts if provided
    if !empty(virtual_text)
      let s:highlight_virtual_text[prop_id] = virtual_text
      let s:highlight_colors[prop_id] = color
    endif
    
  catch
    " Silent error handling
  endtry
endfunction

function! s:DoClearHighlights(filename)
  let highlight_colors = ['yellow', 'orange', 'pink', 'green', 'blue', 'purple']
  
  if empty(a:filename)
    " Clear from current buffer and clean up virtual text dict
    for color in highlight_colors
      call prop_remove({'type': 'q_highlight_' . color, 'all': 1})
    endfor
    " Clear all virtual text entries for this buffer
    let s:highlight_virtual_text = {}
    let s:highlight_colors = {}
    let s:highlight_start_lines = {}
  else
    " Clear from specific file
    let target_bufnr = bufnr(a:filename)
    if target_bufnr != -1
      for color in highlight_colors
        call prop_remove({'type': 'q_highlight_' . color, 'all': 1, 'bufnr': target_bufnr})
      endfor
      " Note: We can't easily clean up virtual text dict for specific buffer
      " but it will be overwritten when new highlights are added
    endif
  endif
endfunction

" Get current quickfix entry
function! s:DoGetCurrentQuickfix(request_id)
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
function! s:DoGetAnnotations(request_id)
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

" Send current editor context to Q CLI MCP server
" Formats context as markdown with filename, line numbers, and code content
function! PushContextUpdate()
  " Skip if no active connection
  if s:mcp_channel == v:null || ch_status(s:mcp_channel) != 'open'
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
    call ch_sendraw(s:mcp_channel, json_encode(update) . "\n")
  catch
    " Silently ignore send failures (connection may be closed)
  endtry
endfunction

" Get socket path, using hashed directory structure for long paths
function! s:GetSocketPath()
    let l:cwd_hash = sha256(getcwd())
    let l:socket_dir = '/tmp/vim-q-connect/' . l:cwd_hash
    call mkdir(l:socket_dir, 'p')
    return l:socket_dir . '/sock'
endfunction

" Establish connection to Q CLI MCP server
" Uses Unix domain socket at path defined by g:vim_q_connect_socket_path
function! StartMCPServer()
  if s:mcp_channel != v:null
    return
  endif
  
  " Set socket path at connection time if not configured
  if !exists('g:vim_q_connect_socket_path')
    let g:vim_q_connect_socket_path = s:GetSocketPath()
  endif
  
  try
    " Open nl-mode channel with message callback
    let s:mcp_channel = ch_open('unix:' . g:vim_q_connect_socket_path, {
      \ 'mode': 'nl',
      \ 'callback': 'HandleMCPMessage',
      \ 'close_cb': 'OnMCPClose'
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
function! OnMCPClose(channel)
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

" Public API: Start context tracking and MCP connection
" Sets up autocmds to monitor cursor movement, text changes, and mode changes
function! vim_q_connect#start_tracking()
  let s:context_active = 1
  call StartMCPServer()
  
  " Only proceed if connection successful
  if s:mcp_channel != v:null && ch_status(s:mcp_channel) == 'open'
    " Save current autoread settings
    let g:vim_q_connect_saved_autoread = &autoread
    let g:vim_q_connect_saved_autoread_group = exists('#AutoRead')
    
    " Enable autoread
    set autoread
    
    " Set up autoread autocmds
    augroup AutoRead
      autocmd!
      autocmd FocusGained,BufEnter,CursorHold,CursorHoldI * checktime
      autocmd FileChangedShellPost * call s:AnnotateCurrentBuffer()
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

" Internal: Update context state and push to MCP server
" Called by autocmds on cursor movement, text changes, etc.
function! WriteContext()
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
    " Ensure start <= end for consistent ordering
    if s:visual_start > s:visual_end
      let temp = s:visual_start
      let s:visual_start = s:visual_end
      let s:visual_end = temp
    endif
  else
    " Clear selection state when not in visual mode
    let s:visual_start = 0
    let s:visual_end = 0
  endif
  
  call PushContextUpdate()
  
  " Check for cursor in highlighted text
  call s:CheckCursorInHighlight()
endfunction

" Check if cursor is in highlighted text and show virtual text
function! s:CheckCursorInHighlight()
  if !has('textprop')
    return
  endif
  
  " Initialize property types first
  call s:InitPropTypes()
  
  let current_line = line('.')
  let current_col = col('.')
  let highlight_colors = ['yellow', 'orange', 'pink', 'green', 'blue', 'purple']
  let found_highlight = 0
  
  " Track which prop ID we've shown virtual text for (to avoid duplicates on multi-line)
  if !exists('s:current_virtual_text_prop_id')
    let s:current_virtual_text_prop_id = -1
  endif
  
  echom "CheckCursorInHighlight: line=" . current_line . " col=" . current_col
  
  " Check all highlight types
  for color in highlight_colors
    let prop_type = 'q_highlight_' . color
    let props = prop_list(current_line, {'type': prop_type})
    
    if !empty(props)
      echom "Found " . len(props) . " " . color . " props on line " . current_line
    endif
    
    for prop in props
      echom "Checking prop: " . string(prop)
      
      " Skip if this prop doesn't have an id (e.g., virtual text props)
      if !has_key(prop, 'id')
        continue
      endif
      
      " Check if cursor is within this property
      let in_range = 0
      let prop_start_line = get(prop, 'lnum', current_line)
      let prop_start_col = get(prop, 'col', 1)
      
      if has_key(prop, 'end_lnum')
        " Multi-line highlight
        let prop_end_line = prop.end_lnum
        let prop_end_col = get(prop, 'end_col', 999999)
        
        echom "Multi-line: start=" . prop_start_line . ":" . prop_start_col . " end=" . prop_end_line . ":" . prop_end_col
        
        if current_line > prop_start_line && current_line < prop_end_line
          let in_range = 1
        elseif current_line == prop_start_line && current_col >= prop_start_col
          let in_range = 1
        elseif current_line == prop_end_line && current_col < prop_end_col
          let in_range = 1
        endif
      else
        " Single line highlight - check for length or end_col
        if has_key(prop, 'length')
          let prop_end_col = prop_start_col + prop.length
          echom "Single-line with length: start=" . prop_start_col . " length=" . prop.length . " end=" . prop_end_col
        else
          let prop_end_col = get(prop, 'end_col', 999999)
          echom "Single-line with end_col: start=" . prop_start_col . " end=" . prop_end_col
        endif
        
        if current_line == prop_start_line && current_col >= prop_start_col && current_col < prop_end_col
          let in_range = 1
        endif
      endif
      
      echom "in_range=" . in_range
      
      if in_range
        let found_highlight = 1
        echom "Cursor is in range! prop_id=" . prop.id
        " Check if this highlight has virtual text in our dict
        if has_key(s:highlight_virtual_text, prop.id)
          let virtual_text = s:highlight_virtual_text[prop.id]
          let highlight_color = get(s:highlight_colors, prop.id, 'yellow')
          echom "Found virtual_text: " . virtual_text
          if !empty(virtual_text)
            " Only show virtual text if we haven't already shown it for this prop ID
            if s:current_virtual_text_prop_id != prop.id
              " Get the actual start line for this highlight
              let actual_start_line = get(s:highlight_start_lines, prop.id, prop_start_line)
              echom "Using start line: " . actual_start_line
              " Add virtual text above the first line of the highlight
              call s:ShowHighlightVirtualText(actual_start_line, virtual_text, highlight_color)
              let s:current_virtual_text_prop_id = prop.id
            endif
          endif
        else
          echom "No virtual_text for prop_id " . prop.id
        endif
        break
      endif
    endfor
    
    if found_highlight
      break
    endif
  endfor
  
  " Clear virtual text if cursor moved out of all highlights
  if !found_highlight
    call s:ClearHighlightVirtualText()
    let s:current_virtual_text_prop_id = -1
  endif
endfunction

" Show virtual text for highlighted region
function! s:ShowHighlightVirtualText(line_num, text, color)
  echom "ShowHighlightVirtualText called: line=" . a:line_num . " text=" . a:text . " color=" . a:color
  " Check if virtual text already exists at this line
  let all_props = prop_list(a:line_num)
  let existing_virtual = filter(copy(all_props), 'v:val.type =~ "q_highlight_virtual"')
  echom "Existing virtual props: " . string(existing_virtual)
  if !empty(existing_virtual)
    echom "Already showing virtual text, returning"
    return
  endif
  
  echom "Adding virtual text..."
  " Format and add virtual text using color-matched highlight group
  let lines = split(a:text, '\n', 1)
  let win_width = winwidth(0)
  let prop_type = 'q_highlight_virtual_' . a:color
  
  " Ensure property type exists with correct highlight
  let hl_name = 'QHighlightVirtual' . substitute(a:color, '^.', '\U&', '')
  if empty(prop_type_get(prop_type))
    " Property type doesn't exist, create it
    if hlexists(hl_name)
      call prop_type_add(prop_type, {'highlight': hl_name})
      echom "Created prop_type " . prop_type . " with highlight " . hl_name
    else
      call prop_type_add(prop_type, {'highlight': 'qtext'})
      echom "Created prop_type " . prop_type . " with fallback highlight qtext"
    endif
  else
    " Property type exists, check if it has the right highlight
    let prop_info = prop_type_get(prop_type)
    if has_key(prop_info, 'highlight') && prop_info.highlight != hl_name && hlexists(hl_name)
      " Wrong highlight, recreate it
      call prop_type_delete(prop_type)
      call prop_type_add(prop_type, {'highlight': hl_name})
      echom "Recreated prop_type " . prop_type . " with correct highlight " . hl_name
    endif
  endif
  
  for i in range(len(lines))
    let line_text = lines[i]
    
    if i == 0
      let formatted_text = ' 💡 ' . g:vim_q_connect_first_line_char . ' ' . line_text
    else
      let spacing = strdisplaywidth(' 💡 ')
      let formatted_text = repeat(' ', spacing) . g:vim_q_connect_continuation_char . ' ' . line_text
    endif
    
    let padded_text = formatted_text . repeat(' ', win_width + 30 - strwidth(formatted_text))
    
    echom "Calling prop_add with text: " . padded_text . " prop_type: " . prop_type
    call prop_add(a:line_num, 0, {
      \ 'type': prop_type,
      \ 'text': padded_text,
      \ 'text_align': 'above'
    \ })
  endfor
  echom "Virtual text added successfully"
endfunction

" Clear highlight virtual text
function! s:ClearHighlightVirtualText()
  let highlight_colors = ['yellow', 'orange', 'pink', 'green', 'blue', 'purple']
  for color in highlight_colors
    let prop_name = 'q_highlight_virtual_' . color
    if !empty(prop_type_get(prop_name))
      call prop_remove({'type': prop_name, 'all': 1})
    endif
  endfor
endfunction

" Add multiple virtual text entries efficiently
function! s:DoAddVirtualTextBatch(entries)
  try
    " echom "vim-q-connect: DoAddVirtualTextBatch called with " . len(a:entries) . " entries"
    let processed = 0
    let skipped = 0
    
    for entry in a:entries
      try
        " Validate required field
        if !has_key(entry, 'line') || !has_key(entry, 'text')
          " echom "vim-q-connect: Skipping entry missing line or text: " . string(entry)
          let skipped += 1
          continue
        endif
        
        " Handle emoji: use provided emoji field, but always consume emoji from text
        let text = entry.text
        let emoji = get(entry, 'emoji', '')
        
        " Always extract and consume emoji from beginning of text
        if !empty(text)
          let text_emoji = s:ExtractEmoji(text)
          if !empty(text_emoji)
            " Remove emoji and following whitespace from text
            let text = strcharpart(text, strchars(text_emoji))
            let text = substitute(text, '^\s\+', '', '')
            " Use provided emoji field, or fall back to extracted emoji
            if empty(emoji)
              let emoji = text_emoji
            endif
          endif
        endif
        
        " Find line by text content
        let line_matches = s:FindAllLinesByText(entry.line)
        let line_num = 0
        
        if len(line_matches) == 1
          " Single match - use it
          let line_num = line_matches[0]
          " echom "vim-q-connect: Found single line match at " . line_num . " for: " . entry.line[:50]
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
            " echom "vim-q-connect: Found " . len(line_matches) . " matches, using closest to hint " . hint . ": " . line_num
          else
            " No hint - use first match
            let line_num = line_matches[0]
            " echom "vim-q-connect: Found " . len(line_matches) . " matches, using first: " . line_num
          endif
        else
          " No matches - use line_number_hint if provided
          if has_key(entry, 'line_number_hint')
            let line_num = entry.line_number_hint
            " echom "vim-q-connect: No line matches found, using hint: " . line_num
          else
            " echom "vim-q-connect: No line matches and no hint for: " . entry.line[:50]
            let skipped += 1
            continue  " Skip if no line found and no hint
          endif
        endif
        
        let highlight = get(entry, 'highlight', 'Comment')
        call s:DoAddVirtualText(line_num, text, highlight, emoji)
        let processed += 1
        
      catch
        " echom "vim-q-connect: Error processing entry: " . v:exception . " at " . v:throwpoint
        let skipped += 1
      endtry
    endfor
    
    " echom "vim-q-connect: Batch complete - processed: " . processed . ", skipped: " . skipped
  catch
    " echom "vim-q-connect: Error in DoAddVirtualTextBatch: " . v:exception . " at " . v:throwpoint
  endtry
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
  let resolved_entries = []
  let current_file = expand('%:p')
  let skipped = 0
  
  " Pass 1: Resolve line numbers
  for entry in a:entries
    " Validate required fields
    if !has_key(entry, 'text') || (!has_key(entry, 'line') && !has_key(entry, 'line_number'))
      let skipped += 1
      continue
    endif
    
    " Get filename - use provided or current file, expand to full path
    if has_key(entry, 'filename')
      let filename = fnamemodify(entry.filename, ':p')
    else
      let filename = current_file
    endif
    
    " Get entry type - E (error), W (warning), I (info), N (note)
    let entry_type = get(entry, 'type', 'I')
    
    " Resolve line number manually
    if has_key(entry, 'line')
      let line_number_hint = get(entry, 'line_number_hint', 0)
      let line_num = s:FindLineByTextInFile(entry.line, filename, line_number_hint)
      if line_num > 0
        let user_data = {'line_text': entry.line}
        if line_number_hint > 0
          let user_data.line_number_hint = line_number_hint
        endif
      else
        let skipped += 1
        continue
      endif
    else
      let line_num = entry.line_number
      let user_data = {}
    endif
    
    " Add emoji to user_data if provided
    if has_key(entry, 'emoji')
      let user_data.emoji = entry.emoji
    endif
    
    " Store resolved entry
    call add(resolved_entries, {
      \ 'filename': filename,
      \ 'lnum': line_num,
      \ 'text': entry.text,
      \ 'type': entry_type,
      \ 'user_data': user_data
    \ })
  endfor
  
  " Pass 2: Sort by filename then line number
  call sort(resolved_entries, {a, b -> 
    \ a.filename ==# b.filename ? (a.lnum - b.lnum) : (a.filename > b.filename ? 1 : -1)
  \ })
  
  " Pass 3: Build quickfix list
  let qf_list = []
  for entry in resolved_entries
    call add(qf_list, entry)
  endfor
  
  " Add to quickfix list
  if !empty(qf_list)
    call setqflist(qf_list, 'a')
    " Only open if not already open
    if empty(filter(getwininfo(), 'v:val.quickfix'))
      copen
    endif
    " Set up autocmd for future annotations now that quickfix exists
    call s:SetupQuickfixAutocmd()
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
  
  " First pass: exact matches (including whitespace)
  for i in range(len(lines))
    let line = lines[i]
    if line ==# a:line_text
      call add(matches, i + 1)  " Line numbers are 1-indexed
    endif
  endfor
  
  " Second pass: trimmed matches (only if no exact matches found)
  if empty(matches)
    for i in range(len(lines))
      let line = lines[i]
      if trim(line) ==# trim(a:line_text)
        call add(matches, i + 1)  " Line numbers are 1-indexed
      endif
    endfor
  endif
  
  return matches
endfunction

" Auto-annotation state
let s:auto_annotate_enabled = 0

" Set up autocmd for quickfix annotations after first quickfix list is created
function! s:SetupQuickfixAutocmd()
  let s:auto_annotate_enabled = 1
  augroup QQuickfixAnnotate
    autocmd!
    autocmd BufEnter * call s:AnnotateCurrentBuffer()
  augroup END
endfunction

" Manually enable/disable auto-annotation mode
function! s:SetAutoAnnotate(enable)
  let s:auto_annotate_enabled = a:enable
  if a:enable
    augroup QQuickfixAnnotate
      autocmd!
      autocmd BufEnter * call s:AnnotateCurrentBuffer()
    augroup END
    " Annotate current buffer immediately if quickfix exists
    if !empty(getqflist())
      call s:AnnotateCurrentBuffer()
    endif
  else
    augroup QQuickfixAnnotate
      autocmd!
    augroup END
  endif
endfunction

" Find line number by searching for text in a specific file
function! s:FindLineByTextInFile(line_text, filename, ...)
  let line_number_hint = a:0 > 0 ? a:1 : 0
  
  " Read file directly instead of using buffers
  if !filereadable(a:filename)
    " echom "File not readable: " . a:filename
    return 0
  endif
  
  let lines = readfile(a:filename)
  let matches = []
  
  " Collect all matches with their line numbers
  for i in range(len(lines))
    " Try exact match first
    if lines[i] ==# a:line_text
      call add(matches, i + 1)
    endif
  endfor
  
  " If no exact matches, try trimmed matches
  if empty(matches)
    for i in range(len(lines))
      if trim(lines[i]) ==# trim(a:line_text)
        call add(matches, i + 1)
      endif
    endfor
  endif
  
  " If still no matches, try substring matches
  if empty(matches)
    for i in range(len(lines))
      if stridx(lines[i], a:line_text) >= 0
        call add(matches, i + 1)
      endif
    endfor
  endif
  
  " Return best match
  if empty(matches)
    return 0
  elseif len(matches) == 1
    return matches[0]
  elseif line_number_hint > 0
    " Find closest match to hint
    let best_match = matches[0]
    let best_distance = abs(matches[0] - line_number_hint)
    for match in matches[1:]
      let distance = abs(match - line_number_hint)
      if distance < best_distance
        let best_match = match
        let best_distance = distance
      endif
    endfor
    return best_match
  else
    " No hint, return first match
    return matches[0]
  endif
endfunction

" Refresh quickfix line numbers for current file before annotation
function! s:RefreshQuickfixPatterns()
  let qf_list = getqflist({'all': 1})
  let items = qf_list.items
  let current_file = expand('%:p')
  let updated = 0
  
  for i in range(len(items))
    let entry = items[i]
    let entry_file = bufname(entry.bufnr)
    let entry_file_full = fnamemodify(entry_file, ':p')
    
    " Only update entries for current file that have line_text in user_data
    if entry_file_full ==# current_file && 
     \ has_key(entry, 'user_data') && 
     \ type(entry.user_data) == v:t_dict && 
     \ has_key(entry.user_data, 'line_text')
      
      " Find current line number for the text
      let line_number_hint = has_key(entry.user_data, 'line_number_hint') ? entry.user_data.line_number_hint : 0
      let line_num = s:FindLineByTextInFile(entry.user_data.line_text, current_file, line_number_hint)
      
      if line_num > 0 && line_num != entry.lnum
        let items[i].lnum = line_num
        " Remove pattern if it exists
        if has_key(items[i], 'pattern')
          unlet items[i].pattern
        endif
        let updated += 1
      endif
    endif
  endfor
  
  if updated > 0
    call setqflist([], 'r', {'items': items})
  endif
endfunction

" Annotate quickfix entries for current buffer only
function! s:AnnotateCurrentBuffer()
  if !s:auto_annotate_enabled || empty(getqflist()) || &buftype != ''
    return
  endif
  
  " Refresh patterns before annotating
  call s:RefreshQuickfixPatterns()
  
  let current_buf = bufnr('%')
  let qf_list = getqflist()
  
  for entry in qf_list
    if has_key(entry, 'bufnr') && entry.bufnr == current_buf && has_key(entry, 'lnum') && has_key(entry, 'text')
      let text = entry.text
      let emoji = ''
      
      " Always extract and consume emoji from text
      let text_emoji = s:ExtractEmoji(text)
      if !empty(text_emoji)
        let text = strcharpart(text, strchars(text_emoji))
        let text = substitute(text, '^\s\+', '', '')
      endif
      
      " Use provided emoji from user_data, or extracted emoji, or default
      if has_key(entry, 'user_data') && type(entry.user_data) == v:t_dict && has_key(entry.user_data, 'emoji') && !empty(entry.user_data.emoji)
        let emoji = entry.user_data.emoji
      elseif !empty(text_emoji)
        let emoji = text_emoji
      else
        let emoji = entry.type ==# 'E' ? '🔴' : entry.type ==# 'W' ? '🔶' : '🟢'
      endif
      
      call s:DoAddVirtualText(entry.lnum, text, 'Comment', emoji)
    endif
  endfor
endfunction

" Find all line numbers by searching for text content in current buffer
function! s:FindAllLinesByText(line_text)
  try
    let total_lines = line('$')
    let matches = []
    
    if empty(a:line_text)
      " echom "vim-q-connect: Empty line_text provided to FindAllLinesByText"
      return matches
    endif
    
    " First pass: exact matches (including whitespace)
    for i in range(1, total_lines)
      let line = getline(i)
      if line ==# a:line_text
        call add(matches, i)
      endif
    endfor
    
    " Second pass: trimmed matches (only if no exact matches found)
    if empty(matches)
      for i in range(1, total_lines)
        let line = getline(i)
        if trim(line) ==# trim(a:line_text)
          call add(matches, i)
        endif
      endfor
    endif
    
    if empty(matches)
      " echom "vim-q-connect: No matches found for line: " . a:line_text[:50]
    else
      " echom "vim-q-connect: Found " . len(matches) . " matches for line: " . a:line_text[:50]
    endif
    
    return matches
  catch
    " echom "vim-q-connect: Error in FindAllLinesByText: " . v:exception . " at " . v:throwpoint
    return []
  endtry
endfunction

" Annotate quickfix entries as virtual text
function! vim_q_connect#quickfix_annotate()
  let qf_list = getqflist()
  let annotated = 0
  let current_buf = bufnr('%')
  
  " Get list of buffers in windows
  let window_buffers = []
  for winnr in range(1, winnr('$'))
    call add(window_buffers, winbufnr(winnr))
  endfor
  
  for entry in qf_list
    if has_key(entry, 'bufnr') && has_key(entry, 'lnum') && has_key(entry, 'text')
      " Only annotate entries for buffers that are open in windows
      if index(window_buffers, entry.bufnr) >= 0
        " Handle emoji: always extract and consume from text
        let text = entry.text
        let emoji = ''
        
        " Always extract and consume emoji from text
        let text_emoji = s:ExtractEmoji(text)
        if !empty(text_emoji)
          let text = strcharpart(text, strchars(text_emoji))
          let text = substitute(text, '^\s\+', '', '')
        endif
        
        " Use emoji from user_data, or extracted emoji, or type-based default
        if has_key(entry, 'user_data') && type(entry.user_data) == v:t_dict && has_key(entry.user_data, 'emoji') && !empty(entry.user_data.emoji)
          let emoji = entry.user_data.emoji
        elseif !empty(text_emoji)
          let emoji = text_emoji
        else
          let emoji = entry.type ==# 'E' ? '🔴' : entry.type ==# 'W' ? '🔶' : '🟢'
        endif
        
        " Switch to the buffer temporarily to add virtual text
        if entry.bufnr != current_buf
          execute 'buffer ' . entry.bufnr
        endif
        
        call s:DoAddVirtualText(entry.lnum, text, 'Comment', emoji)
        let annotated += 1
        
        " Switch back to original buffer if we changed
        if entry.bufnr != current_buf
          execute 'buffer ' . current_buf
        endif
      endif
    endif
  endfor
  
  echo "Annotated " . annotated . " quickfix entries in open buffers"
endfunction

" Public API: Enable/disable auto-annotation mode
function! vim_q_connect#quickfix_auto_annotate(enable)
  call s:SetAutoAnnotate(a:enable)
  if a:enable
    echo "Auto-annotation enabled for quickfix entries"
  else
    echo "Auto-annotation disabled"
  endif
endfunction
