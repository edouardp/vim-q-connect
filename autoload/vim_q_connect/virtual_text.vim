" vim_q_connect/virtual_text.vim - Virtual text management for vim-q-connect
" Handles adding, formatting, and clearing virtual text annotations

" Extract emoji from beginning of text
function! vim_q_connect#virtual_text#extract_emoji(text)
  let emoji = ''
  let idx = 0
  while idx < strchars(a:text)
    let char = strcharpart(a:text, idx, 1)
    let codepoint = char2nr(char)
    if (codepoint >= 0x1F300 && codepoint <= 0x1FAFF) || 
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

" Common function to format virtual text lines with emoji
" Returns: [display_emoji, cleaned_text]
function! vim_q_connect#virtual_text#extract_emoji_from_text(text, provided_emoji)
  let display_emoji = a:provided_emoji
  let cleaned_text = a:text
  
  " If no emoji provided, try to extract from text using existing function
  if empty(display_emoji)
    let text_emoji = vim_q_connect#virtual_text#extract_emoji(a:text)
    if !empty(text_emoji)
      let display_emoji = text_emoji
      " Remove emoji and following whitespace from text
      let cleaned_text = strcharpart(a:text, strchars(text_emoji))
      let cleaned_text = substitute(cleaned_text, '^\s\+', '', '')
    else
      " Default to fullwidth Q if no emoji found
      let display_emoji = 'Ｑ'
    endif
  endif
  
  return [display_emoji, cleaned_text]
endfunction

" Format virtual text lines with emoji and connectors
" Returns: list of formatted lines ready for display
function! vim_q_connect#virtual_text#format_lines(text, emoji)
  let [display_emoji, cleaned_text] = vim_q_connect#virtual_text#extract_emoji_from_text(a:text, a:emoji)
  let lines = split(cleaned_text, '\n', 1)
  let win_width = winwidth(0)
  let formatted_lines = []
  
  for i in range(len(lines))
    let line_text = lines[i]
    
    if i == 0
      let formatted_text = ' ' . display_emoji . ' ' . g:vim_q_connect_first_line_char . ' ' . line_text
    else
      let spacing = strdisplaywidth(' ' . display_emoji . ' ')
      let formatted_text = repeat(' ', spacing) . g:vim_q_connect_continuation_char . ' ' . line_text
    endif
    
    let padded_text = formatted_text . repeat(' ', win_width + 30 - strwidth(formatted_text))
    call add(formatted_lines, padded_text)
  endfor
  
  return formatted_lines
endfunction

" Add virtual text above specified line
function! vim_q_connect#virtual_text#add_virtual_text(line_num, text, highlight, emoji)
  try
    " Check if text properties are supported
    if !has('textprop')
      return
    endif
    
    " Validate line number
    if a:line_num <= 0 || a:line_num > line('$')
      return
    endif
    
    call vim_q_connect#virtual_text#init_prop_types()
    
    " Always use qtext highlight (ignore passed highlight parameter)
    let l:prop_type = 'q_virtual_text'
    
    " Check for existing props with same text to avoid duplicates
    let existing_props = prop_list(a:line_num, {'type': l:prop_type})
    
    " Check if any existing prop contains the first line of our text
    let first_line = split(a:text, '\n', 1)[0]
    for prop in existing_props
      if has_key(prop, 'text') && stridx(prop.text, first_line) >= 0
        return
      endif
    endfor
    
    " Format virtual text lines using common function
    let formatted_lines = vim_q_connect#virtual_text#format_lines(a:text, a:emoji)
    
    for formatted_text in formatted_lines
      try
        call prop_add(a:line_num, 0, {
          \ 'type': l:prop_type,
          \ 'text': formatted_text,
          \ 'text_align': 'above'
        \ })
      catch
        throw v:exception
      endtry
    endfor
    
  catch
  endtry
endfunction

" Initialize property types for virtual text and highlighting
function! vim_q_connect#virtual_text#init_prop_types()
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
  
  " Don't create color-specific property types here - they'll be created on-demand
  " in ShowHighlightVirtualText with the correct highlight groups
  
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

" Clear all Q Connect virtual text
function! vim_q_connect#virtual_text#clear_virtual_text()
  call prop_remove({'type': 'q_virtual_text', 'all': 1})
endfunction

" Clear annotations from specific file or current buffer
function! vim_q_connect#virtual_text#clear_annotations(filename)
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

" Add multiple virtual text entries efficiently
function! vim_q_connect#virtual_text#add_virtual_text_batch(entries)
  try
    let processed = 0
    let skipped = 0
    
    for entry in a:entries
      try
        " Validate required field
        if !has_key(entry, 'line') || !has_key(entry, 'text')
          let skipped += 1
          continue
        endif
        
        " Handle emoji: use provided emoji field, but always consume emoji from text
        let text = entry.text
        let emoji = get(entry, 'emoji', '')
        
        " Always extract and consume emoji from beginning of text
        if !empty(text)
          let text_emoji = vim_q_connect#virtual_text#extract_emoji(text)
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
        let line_matches = vim_q_connect#virtual_text#find_all_lines_by_text(entry.line)
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
            continue  " Skip if no line found and no hint
          endif
        endif
        
        let highlight = get(entry, 'highlight', 'Comment')
        call vim_q_connect#virtual_text#add_virtual_text(line_num, text, highlight, emoji)
        let processed += 1
        
      catch
        let skipped += 1
      endtry
    endfor
    
  catch
  endtry
endfunction

" Find all line numbers by searching for text content in current buffer
function! vim_q_connect#virtual_text#find_all_lines_by_text(line_text)
  try
    let total_lines = line('$')
    let matches = []
    
    if empty(a:line_text)
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
    else
    endif
    
    return matches
  catch
    return []
  endtry
endfunction
