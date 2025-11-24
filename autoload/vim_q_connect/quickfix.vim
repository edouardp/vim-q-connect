" vim_q_connect/quickfix.vim - Quickfix list management for vim-q-connect
" Handles adding entries to quickfix list and auto-annotation

" Script-local state for quickfix
let s:auto_annotate_enabled = 0

" Clear quickfix list and annotations
function! vim_q_connect#quickfix#clear_quickfix()
  call vim_q_connect#quickfix#do_clear_quickfix()
endfunction

" Internal: Clear quickfix list
function! vim_q_connect#quickfix#do_clear_quickfix()
  " TODO: Only remove annotations that were added for quickfix entries, not all annotations
  call prop_remove({'type': 'q_virtual_text', 'all': 1})
  call setqflist([])
  silent! cclose
endfunction

" Add multiple entries to quickfix list
function! vim_q_connect#quickfix#add_to_quickfix(entries)
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
      let line_num = vim_q_connect#quickfix#find_line_by_text_in_file(entry.line, filename, line_number_hint)
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
    call vim_q_connect#quickfix#setup_quickfix_autocmd()
  elseif skipped > 0
    echohl WarningMsg | echo printf("All %d entries skipped - no valid entries", skipped) | echohl None
  endif
endfunction

" Find line number by searching for text in a specific file
function! vim_q_connect#quickfix#find_line_by_text_in_file(line_text, filename, ...)
  let line_number_hint = a:0 > 0 ? a:1 : 0
  
  " Read file directly instead of using buffers
  if !filereadable(a:filename)
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

" Set up autocmd for quickfix annotations after first quickfix list is created
function! vim_q_connect#quickfix#setup_quickfix_autocmd()
  let s:auto_annotate_enabled = 1
  augroup QQuickfixAnnotate
    autocmd!
    autocmd BufEnter * call vim_q_connect#quickfix#annotate_current_buffer()
  augroup END
endfunction

" Manually enable/disable auto-annotation mode
function! vim_q_connect#quickfix#set_auto_annotate(enable)
  let s:auto_annotate_enabled = a:enable
  if a:enable
    augroup QQuickfixAnnotate
      autocmd!
      autocmd BufEnter * call vim_q_connect#quickfix#annotate_current_buffer()
    augroup END
    " Annotate current buffer immediately if quickfix exists
    if !empty(getqflist())
      call vim_q_connect#quickfix#annotate_current_buffer()
    endif
  else
    augroup QQuickfixAnnotate
      autocmd!
    augroup END
  endif
endfunction

" Refresh quickfix line numbers for current file before annotation
function! vim_q_connect#quickfix#refresh_quickfix_patterns()
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
      let line_num = vim_q_connect#quickfix#find_line_by_text_in_file(entry.user_data.line_text, current_file, line_number_hint)
      
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
function! vim_q_connect#quickfix#annotate_current_buffer()
  if !s:auto_annotate_enabled || empty(getqflist()) || &buftype != ''
    return
  endif
  
  " Refresh patterns before annotating
  call vim_q_connect#quickfix#refresh_quickfix_patterns()
  
  let current_buf = bufnr('%')
  let qf_list = getqflist()
  
  for entry in qf_list
    if has_key(entry, 'bufnr') && entry.bufnr == current_buf && has_key(entry, 'lnum') && has_key(entry, 'text')
      let text = entry.text
      let emoji = ''
      
      " Always extract and consume emoji from text
      let text_emoji = vim_q_connect#virtual_text#extract_emoji(text)
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
      
      call vim_q_connect#virtual_text#add_virtual_text(entry.lnum, text, 'Comment', emoji)
    endif
  endfor
endfunction

" Annotate quickfix entries as virtual text
function! vim_q_connect#quickfix#quickfix_annotate()
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
        let text_emoji = vim_q_connect#virtual_text#extract_emoji(text)
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
        
        call vim_q_connect#virtual_text#add_virtual_text(entry.lnum, text, 'Comment', emoji)
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
function! vim_q_connect#quickfix#quickfix_auto_annotate(enable)
  call vim_q_connect#quickfix#set_auto_annotate(a:enable)
  if a:enable
    echo "Auto-annotation enabled for quickfix entries"
  else
    echo "Auto-annotation disabled"
  endif
endfunction
