# Refactored vim-q-connect: Quick Reference

## File Structure

```
autoload/
├── vim_q_connect.vim (55 lines)
│   └─ PUBLIC API FACADE
│      • start_tracking()
│      • stop_tracking()
│      • clear_virtual_text()
│      • clear_highlights()
│      • clear_quickfix()
│      • quickfix_annotate()
│      • quickfix_auto_annotate()
│
└── vim_q_connect/
    ├── context.vim (194 lines)
    │   └─ STATE & TRACKING
    │      • start_tracking() - Enable monitoring
    │      • stop_tracking() - Disable monitoring
    │      • write_context() - Update state
    │      • push_context_update() - Send to MCP
    │      • annotate_current_buffer() - Delegate
    │
    ├── mcp.vim (312 lines)
    │   └─ CONNECTION & MESSAGING
    │      • start_mcp_server() - Connect
    │      • stop_mcp_server() - Disconnect
    │      • handle_mcp_message() - Route messages
    │      • send_to_mcp() - Send data
    │      • get_channel() - Get status
    │      • get_socket_path() - Generate path
    │
    ├── virtual_text.vim (307 lines)
    │   └─ ANNOTATIONS & TEXT
    │      • add_virtual_text() - Add annotation
    │      • add_virtual_text_batch() - Batch add
    │      • extract_emoji() - Parse emoji
    │      • format_lines() - Format text
    │      • clear_virtual_text() - Remove all
    │      • clear_annotations() - Remove specific
    │
    ├── highlights.vim (276 lines)
    │   └─ HIGHLIGHTING & COLORS
    │      • highlight_text() - Add highlight
    │      • highlight_text_batch() - Batch add
    │      • check_cursor_in_highlight() - Detect
    │      • show_highlight_virtual_text() - Display
    │      • clear_highlight_virtual_text() - Remove
    │      • do_clear_highlights() - Clear all
    │
    └── quickfix.vim (330 lines)
        └─ QUICKFIX MANAGEMENT
           • add_to_quickfix() - Add entries
           • quickfix_annotate() - Annotate all
           • annotate_current_buffer() - Current
           • quickfix_auto_annotate() - Toggle
           • setup_quickfix_autocmd() - Enable auto
           • find_line_by_text_in_file() - Search
           • refresh_quickfix_patterns() - Update

plugin/
└── vim-q-connect.vim (37 lines)
    └─ PLUGIN INITIALIZATION
       • Highlight definitions
       • Command registration
       • Plugin guards
```

## Module Dependencies

```
context.vim
  ├─ mcp.vim (get_channel, send_to_mcp, start_mcp_server, stop_mcp_server)
  ├─ highlights.vim (check_cursor_in_highlight)
  └─ quickfix.vim (annotate_current_buffer)

mcp.vim
  ├─ virtual_text.vim (add_virtual_text, add_virtual_text_batch)
  ├─ highlights.vim (highlight_text, highlight_text_batch, do_clear_highlights)
  └─ quickfix.vim (add_to_quickfix, do_clear_quickfix)

highlights.vim
  ├─ virtual_text.vim (init_prop_types, format_lines)
  └─ (self-contained for highlighting logic)

quickfix.vim
  └─ virtual_text.vim (extract_emoji, add_virtual_text)

virtual_text.vim
  └─ (no inter-module dependencies)
```

## State Management

### context.vim
- `s:context_active` - Tracking enabled flag
- `s:current_filename` - Current file path
- `s:current_line` - Cursor line number
- `s:visual_start/end` - Selection line bounds
- `s:visual_start/end_col` - Selection columns
- `s:visual_start/end_line_len` - Line lengths

### mcp.vim
- `s:mcp_channel` - Vim channel handle

### highlights.vim
- `s:next_highlight_id` - ID counter
- `s:highlight_virtual_text` - Map of ID → text
- `s:highlight_colors` - Map of ID → color
- `s:highlight_start_lines` - Map of ID → line
- `s:current_virtual_text_prop_id` - Current display

### quickfix.vim
- `s:auto_annotate_enabled` - Auto-annotation flag

### virtual_text.vim
- (stateless utility module)

## Configuration Variables

Global variables that can be set before loading:

```vim
" Display characters for virtual text
let g:vim_q_connect_first_line_char = '┤'      " Default
let g:vim_q_connect_continuation_char = '│'    " Default

" Socket path (auto-generated if not set)
let g:vim_q_connect_socket_path = '/tmp/...'   " Optional

" Internal state variables (set by plugin, not user)
let g:vim_q_connect_saved_autoread = ...       " Internal
let g:vim_q_connect_saved_autoread_group = ... " Internal
```

## Commands (from plugin/vim-q-connect.vim)

```vim
:QConnect                      " Toggle tracking on/off
:QConnect!                     " Force disable
:QVirtualTextClear            " Clear all annotations
:QHighlightsClear             " Clear all highlights
:QQuickfixAnnotate            " Manually annotate quickfix
:QQuickfixClear               " Clear quickfix list
:QQuickfixAutoAnnotate        " Enable auto-annotation
:QQuickfixAutoAnnotate!       " Disable auto-annotation
```

## Message Types (MCP Protocol)

Incoming messages from Q CLI (handled by mcp.vim):

```
goto_line              → do_goto_line()
add_virtual_text       → add_virtual_text()
add_virtual_text_batch → add_virtual_text_batch()
add_to_quickfix        → add_to_quickfix()
get_annotations        → do_get_annotations()
get_current_quickfix   → do_get_current_quickfix()
clear_annotations      → clear_annotations()
clear_quickfix         → do_clear_quickfix()
highlight_text        → highlight_text() or highlight_text_batch()
clear_highlights      → do_clear_highlights()
disconnect            → (cleanup)
```

## Function Naming Convention

**Public functions** (from autoload/vim_q_connect.vim):
```vim
vim_q_connect#start_tracking()
vim_q_connect#stop_tracking()
vim_q_connect#clear_virtual_text()
```

**Module functions** (namespaced):
```vim
vim_q_connect#module_name#function_name()
```

Examples:
```vim
vim_q_connect#context#start_tracking()
vim_q_connect#mcp#start_mcp_server()
vim_q_connect#virtual_text#add_virtual_text()
vim_q_connect#highlights#highlight_text()
vim_q_connect#quickfix#add_to_quickfix()
```

**Script-local functions** (private to module):
```vim
function! s:private_function()
```

## Common Operations

### Add Annotation
```vim
call vim_q_connect#virtual_text#add_virtual_text(
  \ line_num,      " Line number
  \ text,          " Text content (can include emoji)
  \ 'Comment',     " Highlight group
  \ emoji          " Optional emoji
\ )
```

### Highlight Text Region
```vim
call vim_q_connect#highlights#highlight_text({
  \ 'start_line': 10,
  \ 'end_line': 15,
  \ 'color': 'yellow',
  \ 'virtual_text': 'Hover text here'
\ })
```

### Add Quickfix Entry
```vim
call vim_q_connect#quickfix#add_to_quickfix([{
  \ 'filename': 'path/to/file.py',
  \ 'line': 42,
  \ 'text': 'Error message',
  \ 'type': 'E',
  \ 'emoji': '🔴'
\ }])
```

## Testing Individual Modules

Each module can be sourced independently:

```vim
" Test virtual_text module
source autoload/vim_q_connect/virtual_text.vim
call vim_q_connect#virtual_text#extract_emoji('✅ Some text')

" Test highlights module
source autoload/vim_q_connect/highlights.vim
call vim_q_connect#highlights#highlight_text({...})

" Test quickfix module
source autoload/vim_q_connect/quickfix.vim
call vim_q_connect#quickfix#add_to_quickfix([...])
```

## Performance Notes

- **Module loading**: Lazy-loaded by autoload system (only when needed)
- **Batch operations**: Use `add_virtual_text_batch()` instead of loop
- **Line matching**: Three-pass approach (exact → trimmed → substring)
- **Cursor tracking**: Uses timer_start(0) for non-blocking updates

## Troubleshooting

### Commands not working
1. Check if plugin is loaded: `:scriptnames | grep vim-q-connect`
2. Verify Vim has textprop support: `:echo has('textprop')`
3. Check MCP channel status: `:echo vim_q_connect#mcp#get_channel()`

### Annotations not appearing
1. Verify textprop is supported
2. Check line number is valid: `:echo line('$')`
3. Clear existing: `:QVirtualTextClear`

### Tracking not working
1. Check MCP server is running
2. Verify socket path: `:echo g:vim_q_connect_socket_path`
3. Check connection: `:echo vim_q_connect#mcp#get_channel()`

## Future Extension Points

### Add new annotation style
Modify `virtual_text.vim`:
```vim
function! vim_q_connect#virtual_text#format_lines_custom(text, emoji)
  " Custom formatting logic
endfunction
```

### Add new quickfix operation
Modify `quickfix.vim`:
```vim
function! vim_q_connect#quickfix#custom_operation(params)
  " Custom quickfix logic
endfunction
```

### Add new MCP message type
Modify `mcp.vim`:
```vim
elseif data.method == 'new_method'
  call vim_q_connect#module#handler()
endif
```

## Summary

| Aspect | Value |
|--------|-------|
| Total Lines | 1,511 |
| Number of Modules | 6 |
| Largest Module | 330 lines (quickfix.vim) |
| Smallest Module | 37 lines (plugin file) |
| API File Size | 55 lines (-96% from original) |
| Public Functions | 7 |
| Message Types | 10 |
| Configuration Variables | 5 |
| Script-local State Items | 6 (total across modules) |
| Circular Dependencies | 0 ✅ |
| Test Coverage | Ready for unit tests |
