# Testing vim-q-connect Highlighting

## Manual Test Commands

Open `test_highlight.py` in Vim and run these commands:

### 1. Set up highlighting colors and property types
```vim
:highlight QHighlightYellow ctermbg=yellow guibg=#ffff00 cterm=bold gui=bold
:highlight QHighlightOrange ctermbg=208 guibg=#ff8c00 cterm=bold gui=bold
:highlight QHighlightPink ctermbg=213 guibg=#ff69b4 cterm=bold gui=bold
:highlight QHighlightGreen ctermbg=green guibg=#90ee90 cterm=bold gui=bold
:highlight QHighlightBlue ctermbg=lightblue guibg=#add8e6 cterm=bold gui=bold
:highlight QHighlightPurple ctermbg=magenta guibg=#dda0dd cterm=bold gui=bold

:call prop_type_add('q_highlight_yellow', {'highlight': 'QHighlightYellow'})
:call prop_type_add('q_highlight_orange', {'highlight': 'QHighlightOrange'})
:call prop_type_add('q_highlight_pink', {'highlight': 'QHighlightPink'})
:call prop_type_add('q_highlight_green', {'highlight': 'QHighlightGreen'})
:call prop_type_add('q_highlight_blue', {'highlight': 'QHighlightBlue'})
:call prop_type_add('q_highlight_purple', {'highlight': 'QHighlightPurple'})
```

### 2. Test single line highlighting
```vim
" Highlight line 6 (the function definition) in yellow
:call prop_add(6, 1, {'end_col': 50, 'type': 'q_highlight_yellow'})

" Highlight line 12 (another function) in orange
:call prop_add(12, 1, {'end_col': 50, 'type': 'q_highlight_orange'})
```

### 3. Test multi-line highlighting
```vim
" Highlight lines 18-20 (the class definition) in green
:call prop_add(18, 1, {'end_lnum': 20, 'end_col': 50, 'type': 'q_highlight_green'})
```

### 4. Test highlighting with virtual text
```vim
" Add highlight with virtual text that appears on cursor hover
:call prop_add(7, 5, {'end_col': 25, 'type': 'q_highlight_pink', 'user_data': {'virtual_text': 'This function prints a greeting\nIt returns True to indicate success'}})
```

### 5. Test cursor tracking (move cursor into highlighted areas)
- Move cursor to line 6 - should see yellow highlight
- Move cursor to line 7 column 10 - should see pink highlight AND virtual text above
- Move cursor away - virtual text should disappear

### 6. Clear highlights
```vim
" Clear all yellow highlights
:call prop_remove({'type': 'q_highlight_yellow', 'all': 1})

" Clear all highlights
:QHighlightsClear
```

## MCP Tool Testing

If connected to Q CLI via MCP:

```
highlight_text(6, color="yellow", virtual_text="This is the main function")
highlight_text(12, 15, color="green", virtual_text="Multi-line function block")
clear_highlights()
```

## Expected Behavior

1. **Highlighting**: Text should have colored background and bold formatting
2. **Cursor tracking**: Moving cursor into highlighted text should trigger virtual text display
3. **Virtual text**: Should appear above the first line of the highlight with lightbulb emoji
4. **Multi-line**: Should work across multiple lines
5. **Cleanup**: Virtual text should disappear when cursor moves out of highlight
