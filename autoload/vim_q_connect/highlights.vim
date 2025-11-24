" vim_q_connect/highlights.vim - Text highlight management for vim-q-connect
" Handles highlighting text regions with background colors and virtual text

" Script-local state for highlights
let s:next_highlight_id = 1
let s:highlight_virtual_text = {}  " Map of prop_id -> virtual_text for highlights
let s:highlight_colors = {}        " Map of prop_id -> color for highlights
let s:highlight_start_lines = {}   " Map of prop_id -> start line
let s:current_virtual_text_prop_id = -1

" Highlight text with background color and bold formatting
function! vim_q_connect#highlights#highlight_text(params)
  try
    if !has('textprop')
      return
    endif
    
    call vim_q_connect#virtual_text#init_prop_types()
    
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
    let prop_id = s:next_highlight_id
    let s:next_highlight_id += 1
    
    " Create text property
    let prop_options = {'type': prop_type, 'id': prop_id}
    if end_line > start_line
      let prop_options.end_lnum = end_line
      let prop_options.end_col = end_col + 1
    elseif end_col > start_col && end_col <= len(getline(start_line)) + 1
      " Single line partial highlight (inclusive of end column)
      let prop_options.length = end_col - start_col + 1
    endif
    
    " Add the property
    call prop_add(start_line, start_col, prop_options)
    
    " Store start line for this prop ID (for virtual text placement)
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

" Highlight multiple text regions
function! vim_q_connect#highlights#highlight_text_batch(entries)
  try
    for entry in a:entries
      if !has_key(entry, 'start_line')
        continue
      endif
      call vim_q_connect#highlights#highlight_text(entry)
    endfor
  catch
    " Silent error handling
  endtry
endfunction

" Clear all Q Connect highlights
function! vim_q_connect#highlights#clear_highlights()
  call vim_q_connect#highlights#do_clear_highlights('')
endfunction

" Internal: Clear highlights from specific file or current buffer
function! vim_q_connect#highlights#do_clear_highlights(filename)
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

" Check if cursor is in highlighted text and show virtual text
function! vim_q_connect#highlights#check_cursor_in_highlight()
  if !has('textprop')
    return
  endif
  
  " Initialize property types first
  call vim_q_connect#virtual_text#init_prop_types()
  
  let current_line = line('.')
  let current_col = col('.')
  let highlight_colors = ['yellow', 'orange', 'pink', 'green', 'blue', 'purple']
  let found_highlight = 0
  
  " Check all highlight types
  for color in highlight_colors
    let prop_type = 'q_highlight_' . color
    let props = prop_list(current_line, {'type': prop_type})
    
    if !empty(props)
    endif
    
    for prop in props
      
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
        else
          let prop_end_col = get(prop, 'end_col', 999999)
        endif
        
        if current_line == prop_start_line && current_col >= prop_start_col && current_col < prop_end_col
          let in_range = 1
        endif
      endif
      
      
      if in_range
        let found_highlight = 1
        " Check if this highlight has virtual text in our dict
        if has_key(s:highlight_virtual_text, prop.id)
          let virtual_text = s:highlight_virtual_text[prop.id]
          let highlight_color = get(s:highlight_colors, prop.id, 'yellow')
          if !empty(virtual_text)
            " Only show virtual text if we haven't already shown it for this prop ID
            if s:current_virtual_text_prop_id != prop.id
              " Clear old virtual text before showing new one
              call vim_q_connect#highlights#clear_highlight_virtual_text()
              " Get the actual start line for this highlight
              let actual_start_line = get(s:highlight_start_lines, prop.id, prop_start_line)
              " Add virtual text above the first line of the highlight
              call vim_q_connect#highlights#show_highlight_virtual_text(actual_start_line, virtual_text, highlight_color)
              let s:current_virtual_text_prop_id = prop.id
            endif
          endif
        else
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
    call vim_q_connect#highlights#clear_highlight_virtual_text()
    let s:current_virtual_text_prop_id = -1
  endif
endfunction

" Show virtual text for highlighted region
function! vim_q_connect#highlights#show_highlight_virtual_text(line_num, text, color)
  " Check if virtual text already exists at this line
  let all_props = prop_list(a:line_num)
  let existing_virtual = filter(copy(all_props), 'v:val.type =~ "q_highlight_virtual"')
  if !empty(existing_virtual)
    return
  endif
  
  " Format and add virtual text using color-matched highlight group
  let lines = split(a:text, '\n', 1)
  let win_width = winwidth(0)
  let prop_type = 'q_highlight_virtual_' . a:color
  
  " Ensure property type exists with correct highlight
  let hl_name = 'QHighlightVirtual' . substitute(a:color, '^.', '\U&', '')
  let prop_exists = !empty(prop_type_get(prop_type))
  
  if !prop_exists
    " Property type doesn't exist, create it
    if hlexists(hl_name)
      call prop_type_add(prop_type, {'highlight': hl_name})
    else
      call prop_type_add(prop_type, {'highlight': 'qtext'})
    endif
  else
    " Property type exists, check if it has the right highlight
    let prop_info = prop_type_get(prop_type)
    if hlexists(hl_name)
      if !has_key(prop_info, 'highlight') || prop_info.highlight != hl_name
        " Wrong or missing highlight, need to recreate
        " First clear any existing virtual text using this type
        call vim_q_connect#highlights#clear_highlight_virtual_text()
        call prop_type_delete(prop_type)
        call prop_type_add(prop_type, {'highlight': hl_name})
      else
      endif
    endif
  endif
  
  " Format virtual text lines using common function (no emoji provided, will extract from text)
  let formatted_lines = vim_q_connect#virtual_text#format_lines(a:text, '')
  
  for formatted_text in formatted_lines
    call prop_add(a:line_num, 0, {
      \ 'type': prop_type,
      \ 'text': formatted_text,
      \ 'text_align': 'above'
    \ })
  endfor
endfunction

" Clear highlight virtual text
function! vim_q_connect#highlights#clear_highlight_virtual_text()
  let highlight_colors = ['yellow', 'orange', 'pink', 'green', 'blue', 'purple']
  for color in highlight_colors
    let prop_name = 'q_highlight_virtual_' . color
    if !empty(prop_type_get(prop_name))
      call prop_remove({'type': prop_name, 'all': 1})
    endif
  endfor
endfunction
