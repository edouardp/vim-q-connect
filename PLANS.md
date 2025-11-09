# vim-q-connect: Future Plans

## Design Principles

All features must satisfy the **Immediate Feedback Principle**:

> When Q performs an action in Vim, the user must immediately and obviously know that Q did something.

**Why this matters:**

- Q operates in a separate terminal from Vim
- User cannot see Q's internal processing
- Actions must be unambiguous and attributed to Q
- Passive/subtle features create confusion ("Did Q do anything?")

**What makes feedback obvious:**

- ✅ Windows open/close
- ✅ Text appears/changes
- ✅ Cursor moves
- ✅ Colors change
- ✅ Layout changes
- ❌ Silent background changes
- ❌ Requires discovery (hover, scroll, etc.)
- ❌ Could be from any plugin

## Planned Features

### 1. Code Highlighting with Hover Details (High Priority)

**Status:** Not implemented

**What it does:**
Highlight problematic code with subtle background colors. Show detailed explanations on hover or keypress.

**Design rationale:**

- **Immediate feedback:** Code changes color instantly (obvious)
- **Non-intrusive:** Subtle highlighting doesn't obscure code
- **Precise:** Highlights exact problematic code, not just lines
- **On-demand details:** Full explanation available without cluttering screen
- **Professional:** IDE-like experience

**Implementation approach:**

```vim
" Highlight code with text properties
call prop_add(line, col, {
  \ 'type': 'q_security',
  \ 'length': 15,
  \ 'id': unique_id
  \ })

" Show details on K or CursorHold
function! QShowDetailsAtCursor()
  " Find highlighted region under cursor
  " Show popup with full explanation
endfunction
```

**Visual example:**

```python
# 🔒 SQL injection vulnerability
query = "SELECT * FROM users WHERE id = " + user_id
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
      (highlighted in light red, hover for details)
```

**Three-tier information display:**

1. **Highlighting** - Glanceable (see issues at a glance)
2. **Brief annotation above** - Scannable (read quick summary)
3. **Popup on hover/K** - Detailed (full explanation + fix instructions)

**MCP tool:**

```python
@mcp.tool()
def highlight_issue(line: int, col: int, length: int, type: str, 
                   short_msg: str, detailed_msg: str) -> str:
    """Highlight code and attach detailed explanation"""
```

**Highlight types:**

- `q_security` - Light red background (security issues)
- `q_performance` - Light yellow background (performance issues)
- `q_quality` - Light blue background (code quality issues)

**Why better than current annotations:**

- More visual (color draws attention)
- Less cluttered (details on-demand)
- More precise (highlights exact code)
- More professional (IDE-like)

---

### 2. Diff Mode for Change Previews (High Priority)

**Status:** Not implemented

**What it does:**
Show side-by-side diff of proposed changes before applying them. User can review, edit, accept, or reject.

**Design rationale:**

- **Immediate feedback:** Split window opens with diff (obvious)
- **Trust building:** User sees exactly what will change
- **User control:** Accept/reject/edit before applying
- **Learning opportunity:** User understands Q's reasoning
- **Safety:** No surprises, no accidental changes

**Implementation approach:**

```vim
" Create side-by-side diff
function! s:DoPreviewChanges(filename, original, modified, description)
  " Left: original (read-only)
  " Right: proposed changes (editable)
  " Both in diff mode
  
  " Keybindings:
  " <leader>a - Accept changes
  " <leader>r - Reject changes
endfunction
```

**Visual example:**

```
┌─────────────────────────┬─────────────────────────┐
│ auth.py (original)      │ auth.py (proposed)      │
├─────────────────────────┼─────────────────────────┤
│ def authenticate(user): │ def authenticate(user): │
│-    if users[user] ==   │+    if not user:        │
│-        password:       │+        return False    │
│+                        │+    hashed = hash(pwd)  │
│+                        │+    if users[user] ==   │
│+                        │+        hashed:         │
│         return True     │         return True     │
└─────────────────────────┴─────────────────────────┘

PROPOSED CHANGES:
Fixed SQL injection by using parameterized queries
```

**Workflow:**

1. User: `@fix the security issue`
2. Q analyzes and generates fix
3. Q calls `preview_changes()` MCP tool
4. Vim opens diff view (obvious!)
5. User reviews changes
6. User presses `<leader>a` to accept or `<leader>r` to reject
7. Changes applied to actual file (or discarded)

**MCP tool:**

```python
@mcp.tool()
def preview_changes(filename: str, original_content: str, 
                   modified_content: str, description: str) -> str:
    """Show diff preview before applying changes"""
```

**Why this is powerful:**

- Transforms scary "AI modifies my code" into safe "AI suggests, I approve"
- User maintains control over codebase
- Builds trust in AI assistance
- Enables learning from AI's changes

**Integration with @fix prompt:**

```python
@mcp.prompt()
def fix(target: str = None):
    # ... analyze and generate fix ...
    
    # Show preview instead of direct modification
    preview_changes(filename, original, modified, description)
    
    # Wait for user acceptance before applying
```

---

### 3. Terminal Integration (Medium Priority)

**Status:** Not implemented

**What it does:**
Run commands in Vim terminal buffers. Show live output, capture results, enable interactive workflows.

**Design rationale:**

- **Immediate feedback:** Terminal window opens (obvious)
- **Live output:** User sees command execution in real-time
- **Interactive:** Can see tests running, builds compiling, etc.
- **Contextual:** Output appears in Vim, not separate terminal

**Use cases:**

- Run tests and show failures
- Execute linters and capture output
- Run build commands
- Start development servers
- Execute code and show results

**Implementation approach:**

```vim
function! s:DoRunCommand(command, description)
  " Open terminal buffer
  let term_buf = term_start(a:command, {
    \ 'term_finish': 'close',
    \ 'term_name': 'Q: ' . a:description
    \ })
  
  " Show notification
  call popup_notification(['Q is running: ' . a:description], {'time': 3000})
endfunction
```

**MCP tool:**

```python
@mcp.tool()
def run_command(command: str, description: str) -> str:
    """Execute command in Vim terminal buffer"""
```

**Example workflow:**

```
User: "Run the tests"
Q: [Calls run_command('pytest tests/', 'Running tests')]
Vim: [Opens terminal buffer, shows live test output]
Q: [Parses output, adds failures to quickfix]
```

**Why useful:**

- Keeps everything in Vim
- Live feedback during long operations
- Can parse output for further analysis
- Enables test-driven development workflows

---

### 4. Multi-File Operations (Medium Priority)

**Status:** Not implemented

**What it does:**
Open multiple related files and arrange them in optimal layouts.

**Design rationale:**

- **Immediate feedback:** Multiple windows open (obvious)
- **Notification:** Popup explains what Q arranged
- **Contextual:** Layout optimized for specific task
- **Productive:** Saves manual navigation

**Use cases:**

- Show test file next to implementation
- Open all files with TODO comments
- Display related files for refactoring
- Show documentation alongside code

**Implementation approach:**

```vim
function! s:DoOpenRelatedFiles(files, layout, description)
  " Open files in specified layout
  " Show notification explaining arrangement
  
  call popup_notification([
    \ 'Q arranged files for: ' . a:description,
    \ 'Files: ' . join(a:files, ', ')
    \ ], {'time': 5000})
endfunction
```

**MCP tool:**

```python
@mcp.tool()
def open_related_files(files: list[str], layout: str, description: str) -> str:
    """Open multiple files in specified layout"""
```

**Layouts:**

- `vertical` - Side-by-side splits
- `horizontal` - Stacked splits
- `tabs` - Separate tabs
- `grid` - 2x2 grid

**Example:**

```
User: "Show me the test file for this"
Q: [Calls open_related_files(['auth.py', 'test_auth.py'], 'vertical', 'implementation and tests')]
Vim: [Opens vertical split with both files]
Popup: "Q arranged files for: implementation and tests"
```

---

### 5. Notification System (Low Priority)

**Status:** Partially implemented (ad-hoc popups)

**What it does:**
Standardized notification system for all Q actions.

**Design rationale:**

- **Consistent feedback:** All actions show notifications
- **Attribution:** Always clear that Q did something
- **Non-intrusive:** Dismissible, timed popups
- **Informative:** Explains what happened and why

**Implementation approach:**

```vim
function! QNotify(message, type, duration)
  " type: 'info', 'warning', 'error', 'success'
  " duration: milliseconds (0 = manual dismiss)
  
  let highlight = a:type == 'error' ? 'ErrorMsg' :
                \ a:type == 'warning' ? 'WarningMsg' :
                \ a:type == 'success' ? 'DiffAdd' :
                \ 'Normal'
  
  call popup_notification([a:message], {
    \ 'time': a:duration,
    \ 'highlight': highlight,
    \ 'border': []
    \ })
endfunction
```

**MCP tool:**

```python
@mcp.tool()
def notify(message: str, type: str = 'info', duration: int = 3000) -> str:
    """Show notification popup"""
```

**Use for:**

- Confirming actions ("Q marked 3 locations")
- Progress updates ("Q analyzing code...")
- Completion messages ("Q found 5 issues")
- Error messages ("Q could not parse file")

---

## Ambient Context Features (Vim → Q)

These features provide Q with rich context about the user's workflow without requiring explicit actions. They enable smarter, more contextual assistance.

### 6. Command History (Medium Priority)

**Status:** Not implemented

**What it does:**
Q reads user's recent Vim commands to understand workflow patterns and suggest optimizations.

**Design rationale:**

- **Passive observation:** Doesn't change Vim state
- **No confusion:** User doesn't need to know Q is reading history
- **Enables intelligence:** Q can detect patterns and suggest improvements
- **Respects privacy:** Only reads commands, not file content

**Implementation approach:**

```vim
function! s:GetCommandHistory()
  " Get last 50 commands
  redir => history_output
  silent history cmd
  redir END
  
  return split(history_output, "\n")
endfunction
```

**MCP tool:**

```python
@mcp.tool()
def get_command_history() -> list[str]:
    """Get user's recent Vim commands to understand workflow"""
```

**Use cases:**

**Pattern detection:**

```
User runs: :w | :!pytest
User runs: :w | :!pytest  
User runs: :w | :!pytest

Q: "I noticed you always run pytest after saving. 
    Want me to set up auto-test on save?"
```

**Workflow optimization:**

```
User runs: :e file1.py
User runs: :e file2.py
User runs: :e file1.py
User runs: :e file2.py

Q: "You're switching between these files frequently.
    Want me to open them side-by-side?"
```

**Learning user preferences:**

```
User runs: :set number
User runs: :set relativenumber
User runs: :set cursorline

Q: "I see you prefer these settings. Should I remember them?"
```

**Why useful:**

- Proactive suggestions based on actual behavior
- Learns user's workflow without explicit teaching
- Can suggest automations for repetitive tasks
- Respects user's working style

---

### 7. Clipboard Integration (Medium Priority)

**Status:** Not implemented

**What it does:**
Q can read what user copied (for context) and write generated code to clipboard (for output).

**Design rationale:**

- **Reading clipboard:** Passive, provides context about user intent
- **Writing clipboard:** Obvious (user pastes and sees it)
- **Non-intrusive:** Doesn't modify files directly
- **Familiar workflow:** Users understand copy/paste

**Implementation approach:**

```vim
function! s:GetClipboard()
  return @"  " Unnamed register (last yank/delete)
endfunction

function! s:SetClipboard(content)
  let @+ = a:content  " System clipboard
  let @* = a:content  " Selection clipboard
endfunction
```

**MCP tools:**

```python
@mcp.tool()
def get_clipboard_content() -> str:
    """Get what user just copied (for context)"""

@mcp.tool()
def set_clipboard(content: str) -> str:
    """Put generated code on system clipboard"""
```

**Use cases:**

**Context from clipboard:**

```
User: [Copies function name "authenticate"]
User: "Generate tests for this"
Q: [Reads clipboard, sees "authenticate"]
Q: [Generates tests for authenticate() function]
```

**Output to clipboard:**

```
User: "Generate a helper function for parsing dates"
Q: [Generates code]
Q: [Calls set_clipboard(generated_code)]
Q: "Helper function copied to clipboard. Paste with Ctrl+V"
User: [Pastes into file]
```

**Code transformation:**

```
User: [Copies complex nested loop]
User: "Simplify this"
Q: [Reads clipboard, refactors code]
Q: [Puts refactored version on clipboard]
Q: "Simplified version on clipboard. Compare and paste if you like it."
```

**Why useful:**

- Natural workflow (copy/paste is familiar)
- Non-destructive (doesn't modify files)
- User maintains control (decides whether to paste)
- Works across applications (system clipboard)

---

### 8. Project Settings Awareness (Low Priority)

**Status:** Not implemented

**What it does:**
Q reads file-specific Vim settings (from modelines and buffer options) to respect project conventions.

**Design rationale:**

- **Respects conventions:** Uses project's indent style, tab settings, etc.
- **Passive reading:** Doesn't change settings
- **Better output:** Generated code matches project style
- **No configuration needed:** Reads existing settings

**Implementation approach:**

```vim
function! s:GetBufferSettings()
  return {
    \ 'tabstop': &tabstop,
    \ 'shiftwidth': &shiftwidth,
    \ 'expandtab': &expandtab,
    \ 'textwidth': &textwidth,
    \ 'filetype': &filetype,
    \ 'fileencoding': &fileencoding
    \ }
endfunction
```

**MCP tool:**

```python
@mcp.tool()
def get_buffer_settings() -> dict:
    """Get file-specific Vim settings to respect project conventions"""
```

**Use cases:**

**Respect indent style:**

```
File has: # vim: set ts=2 sw=2 et:
User: "Add a new function"
Q: [Reads settings: 2-space indent, spaces not tabs]
Q: [Generates function with 2-space indentation]
```

**Match line length:**

```
File has: # vim: set tw=80:
User: "Add documentation"
Q: [Reads textwidth=80]
Q: [Wraps docstring at 80 characters]
```

**File type awareness:**

```
File has: filetype=python
User: "Add type hints"
Q: [Reads filetype, knows it's Python]
Q: [Adds Python-style type hints, not TypeScript-style]
```

**Why useful:**

- Generated code matches project style automatically
- No need to configure Q with project conventions
- Respects existing modelines and .vimrc settings
- Works across different projects seamlessly

---

## Features Under Consideration

### Temporary Semantic Highlighting

**Concept:** Q highlights code patterns (security-sensitive functions, deprecated APIs, etc.) using text properties.

**Design rationale:**

- ✅ Immediate feedback (color changes)
- ✅ Temporary (cleared when done)
- ✅ Uses text properties (not permanent syntax rules)
- ✅ Must show notification

**Example:**

```vim
" Q highlights all security-sensitive functions
call prop_type_add('q_security_sensitive', {'highlight': 'WarningMsg'})

for [line, col] in FindSecurityFunctions()
  call prop_add(line, col, {'type': 'q_security_sensitive', 'length': len})
endfor

call popup_notification(['Q highlighted security-sensitive functions'], {'time': 3000})
```

**Use cases:**

- Highlight all database queries
- Mark deprecated API usage
- Show performance hotspots
- Identify security-sensitive code

**Verdict:** Useful if paired with notification. Medium priority.

---

### Marks for Navigation Breadcrumbs

**Concept:** Q sets marks at interesting locations, user can jump back.

**Problem:** Silent - user doesn't know marks were set until they try to use them.

**Solution:** Must show notification: "Q marked 3 locations (jump with 'a, 'b, 'c)"

**Verdict:** Useful but needs explicit notification. Low priority.

---

### Code Folding

**Concept:** Q folds boilerplate/irrelevant code to focus on important sections.

**Problem:** Could be disorienting if unexpected.

**Solution:** Must show notification: "Q folded boilerplate code (za to toggle)"

**Verdict:** Useful but needs careful UX. Low priority.

---

### Window Layout Management

**Concept:** Q arranges windows in optimal layouts for specific tasks.

**Problem:** Layout changes could be confusing.

**Solution:** Must show notification explaining the arrangement.

**Verdict:** Covered by multi-file operations. Medium priority.

---

## Features We Won't Implement

### Signs (Gutter Indicators)

**Why not:**

- ❌ Passive - might be off-screen
- ❌ Ambiguous - could be from any plugin
- ❌ Not obvious - no clear "Q did this" signal
- ❌ Not clickable - limited interaction

**Alternative:** Use highlighting + hover details instead.

**Exception:** Signs can be used as **supplementary** indicators when paired with quickfix, never standalone.

---

### Undo Tree Manipulation

**Why not:**

- ❌ Silent - nothing visible happens
- ❌ Too subtle for AI interaction
- ❌ User might not notice
- ❌ Confusing when discovered later

**Alternative:** Let user manage undo naturally.

---

### Autocommands

**Why not:**

- ❌ Silent - triggers in background
- ❌ User doesn't know Q set them up
- ❌ Confusing when they fire later
- ❌ Hard to debug

**Alternative:** Explicit actions only.

---

### Abbreviations

**Why not:**

- ❌ Silent - nothing happens until user types
- ❌ Surprising when they expand
- ❌ User forgets Q added them
- ❌ Interferes with typing

**Alternative:** Use snippets or direct code generation.

---

### Syntax Highlighting Changes

**Why not:**

- ❌ Persists across sessions (confusing)
- ❌ Could be from any plugin
- ❌ No clear "Q did this" signal
- ❌ Hard to undo (syntax rules persist)

**Alternative:** Use text property highlighting (temporary, obvious).

**Note:** Temporary semantic highlighting using text properties is acceptable (see "Features Under Consideration").

---

### Concealment

**Why not:**

- ❌ Visual mismatch with file content (confusing)
- ❌ File displays differently than it actually is
- ❌ Hard to undo (syntax rules persist)
- ❌ Breaks user's mental model

**Example problem:**

```python
# File contains:
def authenticate(user: str, password: str) -> bool:

# But displays as (with concealment):
def authenticate(user, password):

# User edits, gets confused why types reappear
```

**Alternative:** Use folding to hide entire sections, not concealment to hide characters.

---

### Undo Tree Manipulation

**Why not:**

- ❌ No metadata storage (can't label branches)
- ❌ Undo sequence numbers change (can't track reliably)
- ❌ Too fragile to map Q's actions to undo points
- ❌ Silent - user doesn't know Q navigated history

**What you can't do:**

```vim
" Can't store why/who/what for each undo point
" Can't label branches like "Security fix attempt 1"
" Can't reliably track which undo point corresponds to which Q action
```

**Alternative:** Use diff mode to show alternatives side-by-side instead of undo branches.

---

### Register Manipulation

**Why not:**

- ❌ Silent - nothing visible
- ❌ User doesn't know Q modified them
- ❌ Confusing when they paste
- ❌ Interferes with user's clipboard

**Alternative:** Generate code directly in buffer.

---

### Balloons (Tooltips)

**Why not:**

- ❌ Requires mouse hover
- ❌ Not immediate - doesn't appear until hover
- ❌ Easy to miss - user might not hover
- ❌ Ambiguous - could be from LSP or other plugins

**Alternative:** Use popups on CursorHold (auto-hover) or keypress (K).

**Exception:** Balloons can be used as **supplementary** detail when paired with obvious primary feedback (highlighting, annotations).

---

## Implementation Priority

**Phase 1: Core Enhancements (Next)**

1. Code highlighting with hover details
2. Diff mode for change previews

**Phase 2: Workflow Improvements**
3. Terminal integration
4. Multi-file operations
5. Standardized notification system

**Phase 3: Ambient Context**
6. Command history (workflow understanding)
7. Clipboard integration (read/write)
8. Project settings awareness

**Phase 4: Polish**
9. Temporary semantic highlighting
10. Marks with notifications
11. Code folding with notifications
12. Additional layout options

---

## Design Checklist

Before implementing any feature, verify:

- [ ] Does it provide immediate visual feedback?
- [ ] Is it obvious that Q did something?
- [ ] Can it be confused with other plugins?
- [ ] Does it require user discovery (hover, scroll)?
- [ ] Can user control/dismiss/undo it?
- [ ] Does it make sense in the Q CLI workflow?

If any answer is problematic, redesign or add notifications to make it obvious.

---

## Success Metrics

A feature is successful if:

1. **User never asks "Did Q do anything?"**
2. **User immediately understands what Q did**
3. **User can control/dismiss the action**
4. **Feature feels integrated, not bolted-on**
5. **Feature enhances productivity without confusion**

---

## Related Documents

- [README.md](README.md) - User-facing documentation
- [DESIGN_DECISIONS.md](DESIGN_DECISIONS.md) - Technical implementation details
