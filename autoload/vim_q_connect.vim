" Autoload functions for vim-q-connect

let g:context_active = 0
let g:mcp_channel = v:null
let g:current_filename = ''
let g:current_line = 0
let g:visual_start = 0
let g:visual_end = 0

function! HandleMCPMessage(channel, msg)
  let data = json_decode(a:msg)
  
  if data.method == 'goto_line'
    let line_num = data.params.line
    let filename = get(data.params, 'filename', '')
    
    if filename != ''
      execute 'edit ' . filename
    endif
    execute line_num
    normal! zz
  endif
endfunction

function! PushContextUpdate()
  if g:mcp_channel == v:null || ch_status(g:mcp_channel) != 'open'
    return
  endif
  
  if &buftype == 'terminal'
    let context = "Terminal buffer - no context available"
  elseif g:visual_start > 0 && g:visual_end > 0
    let lines = getline(g:visual_start, g:visual_end)
    let context = "# " . g:current_filename . "\n\nLines " . g:visual_start . "-" . g:visual_end . ":\n```\n" . join(lines, "\n") . "\n```"
  else
    let line_content = getline(g:current_line)
    let total_lines = line('$')
    let context = "# " . g:current_filename . "\n\nLine " . g:current_line . "/" . total_lines . ":\n```\n" . line_content . "\n```"
  endif
  
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
  
  try
    call ch_sendraw(g:mcp_channel, json_encode(update) . "\n")
  catch
  endtry
endfunction

function! StartMCPServer()
  if g:mcp_channel != v:null
    return
  endif
  
  try
    let g:mcp_channel = ch_open('unix:' . g:vim_q_connect_socket_path, {
      \ 'mode': 'json',
      \ 'callback': 'HandleMCPMessage',
      \ 'close_cb': 'OnMCPClose'
    \ })
    
    if ch_status(g:mcp_channel) == 'open'
      echo "Q MCP channel connected"
    else
      let g:mcp_channel = v:null
    endif
  catch
    " MCP server not running - that's OK, Q CLI will start it
    let g:mcp_channel = v:null
  endtry
endfunction

function! OnMCPClose(channel)
  echo "MCP channel closed"
  let g:mcp_channel = v:null
endfunction

function! vim_q_connect#start_tracking()
  let g:context_active = 1
  call StartMCPServer()
  call WriteContext()
  
  augroup VimLLMContext
    autocmd!
    autocmd CursorMoved,CursorMovedI,ModeChanged * call WriteContext()
    autocmd TextChanged,TextChangedI * call WriteContext()
  augroup END
endfunction

function! vim_q_connect#stop_tracking()
  if g:mcp_channel != v:null
    let disconnect_msg = {"method": "disconnect", "params": {}}
    try
      call ch_sendraw(g:mcp_channel, json_encode(disconnect_msg) . "\n")
    catch
    endtry
    call ch_close(g:mcp_channel)
    let g:mcp_channel = v:null
  endif
  let g:context_active = 0
  
  augroup VimLLMContext
    autocmd!
  augroup END
  
  echo "Q MCP channel disconnected"
endfunction

function! WriteContext()
  if !g:context_active || &buftype == 'terminal'
    return
  endif
  
  let g:current_filename = expand('%:t')
  let g:current_line = line('.')
  
  if mode() =~# '[vV\<C-v>]'
    let g:visual_start = line('v')
    let g:visual_end = line('.')
    if g:visual_start > g:visual_end
      let temp = g:visual_start
      let g:visual_start = g:visual_end
      let g:visual_end = temp
    endif
  else
    let g:visual_start = 0
    let g:visual_end = 0
  endif
  
  call PushContextUpdate()
endfunction
