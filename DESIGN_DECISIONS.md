# vim-q-connect Design Decisions

## Table of Contents
1. [High-Level Overview](#high-level-overview)
2. [Architecture & Communication](#architecture--communication)
3. [MCP Server Implementation](#mcp-server-implementation)
4. [Vim Plugin Implementation](#vim-plugin-implementation)
5. [Annotation System](#annotation-system)
6. [Quickfix Integration](#quickfix-integration)

---

## High-Level Overview

vim-q-connect is a bidirectional integration between Vim and Q CLI (Amazon's AI assistant) using the Model Context Protocol (MCP). It enables real-time editor context sharing and remote control capabilities.

### Components

```
┌─────────────────────────────────────────────────────────────┐
│                         Q CLI                               │
│                    (AI Assistant)                           │
└────────────────────────┬────────────────────────────────────┘
                         │ MCP Protocol
                         │ (Tool Invocations)
                         │
┌────────────────────────▼────────────────────────────────────┐
│                    MCP Server                               │
│                  (mcp-server/main.py)                       │
│  - Exposes tools to Q CLI                                   │
│  - Manages Vim connection state                             │
│  - Handles bidirectional messaging                          │
└────────────────────────┬────────────────────────────────────┘
                         │ Unix Domain Socket
                         │ (JSON-RPC over newline-delimited)
                         │
┌────────────────────────▼────────────────────────────────────┐
│                   Vim Plugin                                │
│         (plugin/ + autoload/vim_q_connect.vim)              │
│  - Tracks editor context (cursor, selections, files)        │
│  - Handles remote commands (goto, annotations)              │
│  - Manages virtual text properties                          │
└─────────────────────────────────────────────────────────────┘
```

### Key Features

1. **Context Sharing**: Vim automatically sends cursor position, file content, and visual selections to Q CLI
2. **Remote Navigation**: Q CLI can navigate to specific lines/files in Vim
3. **Virtual Text Annotations**: Display inline code review comments, analysis results, etc.
4. **Quickfix Integration**: Automatically annotate quickfix entries with virtual text

---

## Architecture & Communication

### Message Flow

#### 1. Context Updates (Vim → MCP Server)

- **Trigger**: Cursor movement, text changes, mode changes
- **Direction**: One-way (no response expected)
- **Frequency**: High (every cursor move)

```
Vim Plugin                    MCP Server
    │                              │
    │  context_update              │
    ├─────────────────────────────►│
    │  {                           │
    │    method: "context_update"  │
    │    params: {                 │
    │      filename: "main.py"     │
    │      line: 42                │
    │      context: "..."          │
    │      visual_start: 0         │
    │      visual_end: 0           │
    │      ...                     │
    │    }                         │
    │  }                           │
    │                              │
```

#### 2. Navigation Commands (MCP Server → Vim)

- **Trigger**: Q CLI calls `goto_line()` tool
- **Direction**: One-way (fire-and-forget)

```
Q CLI                MCP Server              Vim Plugin
  │                      │                       │
  │  goto_line(42)       │                       │
  ├─────────────────────►│                       │
  │                      │  goto_line            │
  │                      ├──────────────────────►│
  │                      │  {                    │
  │                      │    method: "goto_line"│
  │                      │    params: {          │
  │                      │      line: 42         │
  │                      │      filename: ""     │
  │                      │    }                  │
  │                      │  }                    │
  │                      │                       │
  │  "Navigation sent"   │                       │
  │◄─────────────────────┤                       │
```

#### 3. Virtual Text Annotations (MCP Server → Vim)

- **Trigger**: Q CLI calls `add_virtual_text()` tool
- **Direction**: One-way (fire-and-forget)

```
Q CLI                MCP Server              Vim Plugin
  │                      │                       │
  │  add_virtual_text()  │                       │
  ├─────────────────────►│                       │
  │                      │  add_virtual_text_batch│
  │                      ├──────────────────────►│
  │                      │  {                    │
  │                      │    method: "add_..."  │
  │                      │    params: {          │
  │                      │      entries: [...]   │
  │                      │    }                  │
  │                      │  }                    │
  │                      │                       │
  │  "Added N entries"   │                       │
  │◄─────────────────────┤                       │
```

#### 4. Annotation Queries (MCP Server → Vim → MCP Server)

- **Trigger**: Q CLI calls `get_annotations_above_current_position()` tool
- **Direction**: Request-response with timeout

```
Q CLI                MCP Server              Vim Plugin
  │                      │                       │
  │  get_annotations()   │                       │
  ├─────────────────────►│                       │
  │                      │  get_annotations      │
  │                      ├──────────────────────►│
  │                      │  {                    │
  │                      │    method: "get_..."  │
  │                      │    request_id: "uuid" │
  │                      │  }                    │
  │                      │                       │
  │                      │  annotations_response │
  │                      │◄──────────────────────┤
  │                      │  {                    │
  │                      │    method: "annot..." │
  │                      │    request_id: "uuid" │
  │                      │    params: {          │
  │                      │      annotations: []  │
  │                      │    }                  │
  │                      │  }                    │
  │                      │                       │
  │  JSON annotations    │                       │
  │◄─────────────────────┤                       │
```

**Key Design Decision**: Request-response pattern uses:

- Unique `request_id` (UUID) to correlate responses
- Per-request response queues in MCP server
- 5-second timeout to prevent hanging
- Queue cleanup after response received

#### 5. Quickfix Queries (MCP Server → Vim → MCP Server)

- **Trigger**: Q CLI calls `get_current_quickfix_entry()` tool
- **Direction**: Request-response (same pattern as annotations)

### Protocol Details

- **Transport**: Unix domain socket at `.vim-q-mcp.sock`
- **Format**: JSON-RPC over newline-delimited messages
- **Encoding**: UTF-8 with error replacement

**Message Structure**:

```json
{
  "method": "method_name",
  "params": { ... },
  "request_id": "optional-uuid-for-responses"
}
```

---

## MCP Server Implementation

### Threading Model

The MCP server uses a multi-threaded architecture to handle concurrent operations:

```
┌─────────────────────────────────────────────────────────────┐
│                      Main Thread                            │
│                   (FastMCP Event Loop)                      │
│  - Handles MCP tool invocations from Q CLI                  │
│  - Enqueues requests to Vim                                 │
│  - Waits on response queues for request-response patterns   │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       │ Shared State: VimState
                       │ - request_queue (thread-safe Queue)
                       │ - response_queues (dict of Queues)
                       │ - current_context (protected by lock)
                       │ - vim_connected (protected by lock)
                       │
┌──────────────────────▼───────────────────────────────────────┐
│                  Socket Accept Thread                        │
│                    (Daemon Thread)                           │
│  - Accepts incoming Vim connections                          │
│  - Spawns listener thread per connection                     │
└──────────────────────┬───────────────────────────────────────┘
                       │
                       │ Spawns
                       │
┌──────────────────────▼───────────────────────────────────────┐
│                  Socket Listener Thread                      │
│                    (Daemon Thread)                           │
│  - Reads incoming messages from Vim                          │
│  - Sends outgoing requests to Vim                            │
│  - Non-blocking with 0.1s timeout                            │
└──────────────────────────────────────────────────────────────┘
```

### Thread-Safe State Management

**VimState Class**:

```python
class VimState:
    def __init__(self):
        self._lock = threading.Lock()  # Protects context and connected flag
        self.request_queue = queue.Queue()  # Thread-safe by design
        self.response_queues = {}  # Dict of UUID -> Queue
        self.current_context = { ... }
        self.vim_connected = False
```

**Design Decisions**:

1. **Single Lock for Context**: Uses one lock (`_lock`) to protect both `current_context` and `vim_connected` flag
   - Simpler than multiple locks
   - No risk of deadlock
   - Context updates are atomic

2. **Queue-Based Communication**: 
   - `request_queue`: Main thread → Socket thread
   - `response_queues`: Socket thread → Main thread (per request)
   - Python's `queue.Queue` is thread-safe, no additional locking needed

3. **Non-Blocking Socket I/O**:
   ```python
   conn.settimeout(0.1)  # 100ms timeout
   ```
   - Allows checking `request_queue` frequently
   - Prevents blocking on socket reads
   - Enables graceful shutdown

### Socket Listener Loop

The socket listener thread handles bidirectional communication:

```python
while True:
    # 1. Check for outgoing requests (non-blocking)
    try:
        request_type, request_data = vim_state.request_queue.get_nowait()
        conn.send(json.dumps(request_data) + '\n')
    except queue.Empty:
        pass
    
    # 2. Check for incoming data (with timeout)
    conn.settimeout(0.1)
    try:
        data = conn.recv(65536).decode('utf-8', errors='replace')
        if not data:
            break  # Connection closed
        
        buffer += data
        # Parse complete JSON messages...
    except socket.timeout:
        pass  # Continue loop
```

**Design Decisions**:

1. **Interleaved Send/Receive**: Checks outgoing queue before reading socket
   - Ensures requests are sent promptly
   - Prevents request starvation

2. **Buffer Management**: Accumulates partial messages in `buffer`
   - Handles messages split across multiple `recv()` calls
   - Supports both complete JSON objects and newline-delimited format

3. **Error Handling**: Uses `errors='replace'` for UTF-8 decoding
   - Prevents crashes on invalid UTF-8
   - Logs errors but continues operation

### MCP Tools Exposed to Q CLI

#### 1. `get_editor_context()`

- **Purpose**: Retrieve current Vim editor state
- **Returns**: Dictionary with file content, cursor position, selection, metadata
- **Thread Safety**: Acquires lock to copy `current_context`

```python
@mcp.tool()
def get_editor_context() -> dict:
    if not vim_state.is_connected():
        return {"content": "Editor not connected", ...}
    
    context = vim_state.get_context()  # Thread-safe copy
    return {
        "content": context["context"],
        "filename": context["filename"],
        "current_line": context["line"],
        ...
    }
```

#### 2. `goto_line(line_number: int, filename: str = "")`

- **Purpose**: Navigate Vim to specific line/file
- **Returns**: Status string
- **Pattern**: Fire-and-forget (enqueues request, returns immediately)

```python
@mcp.tool()
def goto_line(line_number: int, filename: str = "") -> str:
    vim_state.request_queue.put(('goto_line', {
        "method": "goto_line",
        "params": {"line": line_number, "filename": filename}
    }))
    return f"Navigation command sent: line {line_number}"
```

#### 3. `add_virtual_text(entries: list[dict])`

- **Purpose**: Add inline annotations to Vim
- **Parameters**: List of entries with `line`/`line_number`, `text`, `emoji`
- **Pattern**: Fire-and-forget

**Design Decision**: Batch API instead of single annotation

- Reduces round-trips for multiple annotations
- More efficient for code review scenarios
- Single message to Vim

#### 4. `add_to_quickfix(entries: list[dict])`

**Purpose**: Add issues to Vim's quickfix list
**Parameters**: List of entries with `line`/`line_number`, `text`, `type`, `filename`
**Pattern**: Fire-and-forget

**Use Cases**: Linting results, test failures, security findings

#### 5. `get_annotations_above_current_position()`

- **Purpose**: Query existing annotations at cursor
- **Returns**: JSON string with annotation list
- **Pattern**: Request-response with timeout

```python
@mcp.tool()
def get_annotations_above_current_position() -> str:
    request_id = str(uuid.uuid4())
    response_queue = queue.Queue()
    vim_state.response_queues[request_id] = response_queue
    
    vim_state.request_queue.put(('get_annotations', {
        "method": "get_annotations",
        "request_id": request_id,
        "params": {}
    }))
    
    try:
        response_type, annotations = response_queue.get(timeout=5.0)
        return json.dumps(annotations)
    except queue.Empty:
        return "Timeout waiting for annotations response"
    finally:
        del vim_state.response_queues[request_id]
```

**Design Decision**: 5-second timeout

- Prevents indefinite blocking if Vim doesn't respond
- Long enough for Vim to process request
- Short enough to not frustrate users

#### 6. `get_current_quickfix_entry()`

- **Purpose**: Get the quickfix entry user is focused on
- **Returns**: Dictionary with entry details
- **Pattern**: Request-response (same as annotations)

---

## Vim Plugin Implementation

### Plugin Structure

```
plugin/vim-q-connect.vim          # Entry point, commands, highlights
autoload/vim_q_connect.vim        # Implementation (lazy-loaded)
```

**Design Decision**: Autoload pattern

- `plugin/` loads immediately on Vim startup
- `autoload/` loads only when functions are called
- Reduces Vim startup time

### Commands

```vim
:QConnect       " Start tracking and connect to MCP server
:QConnect!      " Stop tracking and disconnect
:QVirtualTextClear  " Clear all annotations from current buffer
:QQuickfixAnnotate  " Manually annotate quickfix entries
```

### Global State Variables

```vim
let g:context_active = 0           " Tracking enabled flag
let g:mcp_channel = v:null         " Vim channel handle
let g:current_filename = ''        " Tracked filename
let g:current_line = 0             " Tracked line number
let g:visual_start = 0             " Visual selection start (0 = none)
let g:visual_end = 0               " Visual selection end (0 = none)
```

**Design Decision**: Global variables without namespace prefix

- Simpler code
- Risk of conflicts with other plugins
- **TODO**: Should be prefixed with `g:vim_q_connect_*`

### Connection Lifecycle

#### Startup: `vim_q_connect#start_tracking()`

```
User runs :QConnect
        │
        ▼
┌───────────────────────────────────────────────────────────┐
│ 1. Set g:context_active = 1                               │
└───────────────────────┬───────────────────────────────────┘
                        │
                        ▼
┌───────────────────────────────────────────────────────────┐
│ 2. StartMCPServer()                                       │
│    - Connect to Unix socket                               │
│    - Open channel in 'nl' (newline) mode                  │
│    - Set callback: HandleMCPMessage()                     │
│    - Set close callback: OnMCPClose()                     │
└───────────────────────┬───────────────────────────────────┘
                        │
                        ▼
┌───────────────────────────────────────────────────────────┐
│ 3. Enable autoread                                        │
│    - Save current &autoread setting                       │
│    - Set autoread                                         │
│    - Set up AutoRead autocmd group                        │
└───────────────────────┬───────────────────────────────────┘
                        │
                        ▼
┌───────────────────────────────────────────────────────────┐
│ 4. Send initial context                                   │
│    - Call WriteContext()                                  │
└───────────────────────┬───────────────────────────────────┘
                        │
                        ▼
┌───────────────────────────────────────────────────────────┐
│ 5. Set up VimLLMContext autocmd group                     │
│    - CursorMoved, CursorMovedI, ModeChanged               │
│    - TextChanged, TextChangedI                            │
│    - All call WriteContext()                              │
└───────────────────────────────────────────────────────────┘
```

#### Shutdown: `vim_q_connect#stop_tracking()`

```
User runs :QConnect!
        │
        ▼
┌───────────────────────────────────────────────────────────┐
│ 1. Send disconnect message to MCP server                  │
│    {"method": "disconnect", "params": {}}                 │
└───────────────────────┬───────────────────────────────────┘
                        │
                        ▼
┌───────────────────────────────────────────────────────────┐
│ 2. Close channel                                          │
│    - ch_close(g:mcp_channel)                              │
│    - Set g:mcp_channel = v:null                           │
└───────────────────────┬───────────────────────────────────┘
                        │
                        ▼
┌───────────────────────────────────────────────────────────┐
│ 3. Restore autoread settings                              │
│    - Restore saved &autoread value                        │
│    - Remove AutoRead autocmd group if we created it       │
└───────────────────────┬───────────────────────────────────┘
                        │
                        ▼
┌───────────────────────────────────────────────────────────┐
│ 4. Remove VimLLMContext autocmd group                     │
│    - Clear all context tracking autocmds                  │
└───────────────────────────────────────────────────────────┘
```

### Autoread Behavior

**Purpose**: Automatically reload files changed externally (e.g., by Q CLI or git)

**Implementation**:

```vim
augroup AutoRead
  autocmd!
  autocmd FocusGained,BufEnter,CursorHold,CursorHoldI * checktime
  autocmd FileChangedShellPost * call s:AnnotateCurrentBuffer()
augroup END
```

**Design Decisions**:

1. **`checktime` Triggers**: Multiple events to catch all reload scenarios
   - `FocusGained`: When Vim window gains focus
   - `BufEnter`: When switching buffers
   - `CursorHold`: After cursor stops moving (updatetime)
   - `CursorHoldI`: Same, but in insert mode

2. **`FileChangedShellPost` Hook**: Fires AFTER file is reloaded
   - Re-annotates quickfix entries after external changes
   - Critical for maintaining annotations when file is modified externally
   - Without this, annotations would disappear on reload

3. **Saved Settings**: Preserves user's original autoread configuration
   - Stores `&autoread` value before enabling
   - Stores whether `AutoRead` group existed
   - Restores on disconnect

### Channel and Socket Handling

**Channel Mode**: `'nl'` (newline-delimited)

```vim
let g:mcp_channel = ch_open('unix:' . socket_path, {
  \ 'mode': 'nl',
  \ 'callback': 'HandleMCPMessage',
  \ 'close_cb': 'OnMCPClose'
\ })
```

**Design Decision**: Newline mode vs Raw mode

- `'nl'` mode: Vim automatically splits on newlines
- Callback receives complete messages
- Simpler than manual buffering
- Matches MCP server's newline-delimited format

**Message Handling**: `HandleMCPMessage(channel, msg)`

Dispatches incoming messages to appropriate handlers:

```vim
function! HandleMCPMessage(channel, msg)
  let data = json_decode(a:msg)
  
  if data.method == 'goto_line'
    call timer_start(0, {-> s:DoGotoLine(...)})
  elseif data.method == 'add_virtual_text_batch'
    call timer_start(0, {-> s:DoAddVirtualTextBatch(...)})
  elseif data.method == 'add_to_quickfix'
    call timer_start(0, {-> s:DoAddToQuickfix(...)})
  elseif data.method == 'get_annotations'
    call timer_start(0, {-> s:DoGetAnnotations(...)})
  elseif data.method == 'get_current_quickfix'
    call timer_start(0, {-> s:DoGetCurrentQuickfix(...)})
  endif
endfunction
```

**Design Decision**: `timer_start(0, ...)` for all handlers

- Executes handler outside callback context
- Prevents issues with Vim's callback restrictions
- Allows handlers to modify buffers, windows, etc.
- 0ms delay = execute ASAP on next event loop iteration

### Context Tracking

**Autocmd Group**: `VimLLMContext`

```vim
augroup VimLLMContext
  autocmd!
  autocmd CursorMoved,CursorMovedI,ModeChanged * call WriteContext()
  autocmd TextChanged,TextChangedI * call WriteContext()
augroup END
```

**Context Update Flow**:

```
Cursor moves or text changes
        │
        ▼
WriteContext() called
        │
        ▼
┌───────────────────────────────────────────────────────────┐
│ Update global state:                                      │
│ - g:current_filename = expand('%:.')                      │
│ - g:current_line = line('.')                              │
│ - g:visual_start, g:visual_end (if in visual mode)        │
└───────────────────────┬───────────────────────────────────┘
                        │
                        ▼
┌───────────────────────────────────────────────────────────┐
│ Build context string:                                     │
│ - Terminal buffer: "Terminal buffer - no context"         │
│ - NERDTree: "NERDTree file browser - no context"          │
│ - Visual selection: Lines X-Y with content                │
│ - Normal mode: Current line with content                  │
└───────────────────────┬───────────────────────────────────┘
                        │
                        ▼
┌───────────────────────────────────────────────────────────┐
│ PushContextUpdate()                                       │
│ - Build JSON message                                      │
│ - Send via ch_sendraw(g:mcp_channel, json + "\n")         │
└───────────────────────────────────────────────────────────┘
```

**Design Decision**: High-frequency updates

- Sends context on every cursor move
- Ensures Q CLI always has latest state
- Network overhead minimal (Unix socket, local)
- MCP server updates state atomically

---

## Annotation System

### Virtual Text Implementation

Vim's text properties system (`:help text-prop-intro`):

- Attach virtual text to buffer lines
- Text appears above/below/inline with actual content
- Survives buffer modifications (within limits)

**Property Type Definition**:

```vim
call prop_type_add('q_virtual_text', {'highlight': 'qtext'})
```

**Highlight Group**:

```vim
highlight qtext ctermbg=237 ctermfg=250 cterm=italic 
                guibg=#2a2a2a guifg=#d0d0d0 gui=italic
```

### Adding Annotations: `s:DoAddVirtualText(line_num, text, highlight, emoji)`

```
Input: line_num=42, text="SECURITY: Validate input\nUse schema validation", emoji="🔒"
        │
        ▼
┌───────────────────────────────────────────────────────────┐
│ 1. Check for duplicates                                   │
│    - Get existing props at line_num                       │
│    - Extract first line of new text                       │
│    - If any existing prop contains first line, return     │
└───────────────────────┬───────────────────────────────────┘
                        │
                        ▼
┌───────────────────────────────────────────────────────────┐
│ 2. Split text on newlines                                 │
│    lines = ["SECURITY: Validate input",                   │
│             "Use schema validation"]                      │
└───────────────────────┬───────────────────────────────────┘
                        │
                        ▼
┌───────────────────────────────────────────────────────────┐
│ 3. Format each line                                       │
│    Line 0: " 🔒 ┤ SECURITY: Validate input"               │
│    Line 1: "     │ Use schema validation"                 │
│    (Continuation lines aligned with first line text)      │
└───────────────────────┬───────────────────────────────────┘
                        │
                        ▼
┌───────────────────────────────────────────────────────────┐
│ 4. Pad to window width + 30                               │
│    - Ensures full-line background color                   │
│    - Handles window resizing gracefully                   │
└───────────────────────┬───────────────────────────────────┘
                        │
                        ▼
┌───────────────────────────────────────────────────────────┐
│ 5. Add text property for each line                        │
│    call prop_add(line_num, 0, {                           │
│      'type': 'q_virtual_text',                            │
│      'text': padded_text,                                 │
│      'text_align': 'above'                                │
│    })                                                     │
└───────────────────────────────────────────────────────────┘
```

**Design Decisions**:

1. **Duplicate Detection**: Checks first line only
   - Multi-line annotations add multiple props
   - First line is unique identifier
   - Prevents duplicate annotations on repeated calls

2. **Emoji Handling**: 
   - Default: `'Ｑ'` (fullwidth Q)
   - Custom emoji extracted from text if present
   - Displayed on first line only

3. **Alignment**: Continuation lines aligned with first line text
4. 
   ```
    🔒 ┤ SECURITY: Validate input
       │ Use schema validation
       │ Consider using JSON Schema
   ```

4. **Padding**: Window width + 30 characters
   - Ensures background extends beyond visible text
   - Handles window resizing without re-rendering
   - Trade-off: Uses more memory for longer strings

### Batch Annotations: `s:DoAddVirtualTextBatch(entries)`

Processes multiple annotation requests efficiently:

```
Input: entries = [
  {line: "def process():", text: "Add validation", emoji: "🔒"},
  {line: "return data", text: "Cache this", emoji: "⚡"}
]
        │
        ▼
For each entry:
┌───────────────────────────────────────────────────────────┐
│ 1. Extract emoji from text if not provided                │
│    - Check Unicode codepoints for emoji ranges            │
│    - Remove emoji from text if found                      │
└───────────────────────┬───────────────────────────────────┘
                        │
                        ▼
┌───────────────────────────────────────────────────────────┐
│ 2. Find line number by text content                       │
│    - Call s:FindAllLinesByText(entry.line)                │
│    - Returns array of matching line numbers               │
└───────────────────────┬───────────────────────────────────┘
                        │
                        ▼
┌───────────────────────────────────────────────────────────┐
│ 3. Handle multiple matches                                │
│    - 1 match: Use it                                      │
│    - Multiple matches: Use line_number_hint if provided   │
│    - No matches: Use line_number_hint or skip             │
└───────────────────────┬───────────────────────────────────┘
                        │
                        ▼
┌───────────────────────────────────────────────────────────┐
│ 4. Call s:DoAddVirtualText(line_num, text, hl, emoji)     │
└───────────────────────────────────────────────────────────┘
```

**Design Decision**: Pattern-based line matching

- **Why**: Line numbers change when file is edited
- **How**: Store line text content, search for it later
- **Fallback**: `line_number_hint` for disambiguation or when text not found

### Line Matching Strategies

#### Strategy 1: Exact Match
```vim
if getline(i) ==# a:line_text
  return i
endif
```

#### Strategy 2: Trimmed Match
```vim
if trim(getline(i)) ==# trim(a:line_text)
  return i
endif
```

#### Strategy 3: Substring Match (for partial lines)
```vim
if stridx(getline(i), a:line_text) >= 0
  return i
endif
```

**Design Decision**: Three-tier matching

- Exact match: Fastest, most reliable
- Trimmed match: Handles whitespace differences
- Substring match: Handles partial line specifications
- Order matters: Try exact first, then progressively looser

---

## Quickfix Integration

### Overview

Quickfix list is Vim's built-in error/issue tracking system. vim-q-connect automatically annotates quickfix entries with virtual text.

### Workflow

```
Q CLI calls add_to_quickfix()
        │
        ▼
┌───────────────────────────────────────────────────────────┐
│ MCP Server enqueues request                               │
└───────────────────────┬───────────────────────────────────┘
                        │
                        ▼
┌───────────────────────────────────────────────────────────┐
│ Vim receives add_to_quickfix message                      │
│ Calls s:DoAddToQuickfix(entries)                          │
└───────────────────────┬───────────────────────────────────┘
                        │
                        ▼
┌───────────────────────────────────────────────────────────┐
│ Pass 1: Resolve line numbers                              │
│ - For each entry with 'line' field:                       │
│   - Call s:FindLineByTextInFile(line, filename)           │
│   - Store line_text in user_data for later reindexing     │
│ - For entries with 'line_number': Use directly            │
└───────────────────────┬───────────────────────────────────┘
                        │
                        ▼
┌───────────────────────────────────────────────────────────┐
│ Pass 2: Sort entries                                      │
│ - Sort by filename, then line number                      │
│ - Groups entries by file for better navigation            │
└───────────────────────┬───────────────────────────────────┘
                        │
                        ▼
┌───────────────────────────────────────────────────────────┐
│ Pass 3: Add to quickfix list                              │
│ - call setqflist(qf_list, 'a')  # 'a' = append            │
│ - Open quickfix window if not already open                │
│ - Set up QQuickfixAnnotate autocmd group                  │
└───────────────────────────────────────────────────────────┘
```

### Annotation on Buffer Load

**Autocmd Setup**:

```vim
augroup QQuickfixAnnotate
  autocmd!
  autocmd BufEnter * call s:AnnotateCurrentBuffer()
augroup END
```

**Annotation Flow**:

```
User navigates to quickfix entry (or switches buffers)
        │
        ▼
BufEnter event fires
        │
        ▼
s:AnnotateCurrentBuffer() called
        │
        ▼
┌───────────────────────────────────────────────────────────┐
│ 1. Check preconditions                                    │
│    - Quickfix list not empty                              │
│    - Current buffer is normal (not terminal, etc.)        │
└───────────────────────┬───────────────────────────────────┘
                        │
                        ▼
┌───────────────────────────────────────────────────────────┐
│ 2. Refresh quickfix patterns                              │
│    call s:RefreshQuickfixPatterns()                       │
│    (See "Pattern Reindexing" below)                       │
└───────────────────────┬───────────────────────────────────┘
                        │
                        ▼
┌───────────────────────────────────────────────────────────┐
│ 3. Get quickfix entries for current buffer                │
│    - Filter by entry.bufnr == current_buf                 │
└───────────────────────┬───────────────────────────────────┘
                        │
                        ▼
┌───────────────────────────────────────────────────────────┐
│ 4. For each entry:                                        │
│    - Extract emoji from text or use type-based default    │
│      (E='🔴', W='🔶', I='🟢')                            │
│    - Call s:DoAddVirtualText(entry.lnum, text, emoji)     │
└───────────────────────────────────────────────────────────┘
```

### Pattern Reindexing

**Problem**: File modified externally → line numbers in quickfix list are stale

**Solution**: Reindex using stored line text patterns

```
s:RefreshQuickfixPatterns() called
        │
        ▼
┌───────────────────────────────────────────────────────────┐
│ Get all quickfix entries                                  │
│ let items = getqflist({'all': 1}).items                   │
└───────────────────────┬───────────────────────────────────┘
                        │
                        ▼
For each entry in current file:
┌───────────────────────────────────────────────────────────┐
│ 1. Check if entry has line_text in user_data              │
│    - Only entries added via add_to_quickfix have this     │
│    - Manual quickfix entries don't get reindexed          │
└───────────────────────┬───────────────────────────────────┘
                        │
                        ▼
┌───────────────────────────────────────────────────────────┐
│ 2. Search for line_text in current file                   │
│    line_num = s:FindLineByTextInFile(line_text, file)     │
└───────────────────────┬───────────────────────────────────┘
                        │
                        ▼
┌───────────────────────────────────────────────────────────┐
│ 3. Update entry if line number changed                    │
│    if line_num > 0 && line_num != entry.lnum:             │
│      items[i].lnum = line_num                             │
│      updated += 1                                         │
└───────────────────────┬───────────────────────────────────┘
                        │
                        ▼
┌───────────────────────────────────────────────────────────┐
│ 4. Update quickfix list if any changes                    │
│    if updated > 0:                                        │
│      call setqflist([], 'r', {'items': items})            │
└───────────────────────────────────────────────────────────┘
```

**Design Decisions**:

1. **Selective Reindexing**: Only entries with `user_data.line_text`
   - Preserves manual quickfix entries
   - Only reindexes programmatically-added entries
   - Prevents breaking user's workflow

2. **File Reading**: Uses `readfile()` instead of buffer APIs
   - Works even if file not loaded in buffer
   - Reads latest file content from disk
   - Handles external modifications correctly

3. **Reindex Timing**: Before annotation
   - Ensures annotations appear at correct lines
   - Handles case where file changed since quickfix was populated
   - Critical for external file modifications (git, build tools, etc.)

### Special Cases Handled

#### Case 1: Multiple Matches for Same Line Text

**Problem**: Same line appears multiple times in file

```python
return None  # Line 10
return None  # Line 25
return None  # Line 40
```

**Solution**: Use `line_number_hint` to disambiguate

```vim
let line_matches = s:FindAllLinesByText(entry.line)
if len(line_matches) > 1 && has_key(entry, 'line_number_hint')
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
endif
```

#### Case 2: Line Not Found After File Modification

**Problem**: Line was deleted or significantly changed

**Solution**: Skip annotation for that entry

```vim
if line_num == 0
  let skipped += 1
  continue
endif
```

**Alternative**: Could use `line_number_hint` as fallback, but risks annotating wrong line

#### Case 3: File Not Yet Loaded

**Problem**: Quickfix entry for file not in any buffer

**Solution**: Read file directly from disk

```vim
function! s:FindLineByTextInFile(line_text, filename)
  if !filereadable(a:filename)
    return 0
  endif
  
  let lines = readfile(a:filename)
  " Search through lines...
endfunction
```

#### Case 4: Annotations Disappear on External File Change

**Problem**: Vim reloads file → text properties lost

**Solution**: `FileChangedShellPost` autocmd

```vim
augroup AutoRead
  autocmd FileChangedShellPost * call s:AnnotateCurrentBuffer()
augroup END
```

**Flow**:

```
External tool modifies file (e.g., git checkout)
        │
        ▼
Vim detects change (via checktime)
        │
        ▼
Vim reloads file (autoread)
        │
        ▼
FileChangedShellPost event fires
        │
        ▼
s:AnnotateCurrentBuffer() called
        │
        ▼
Quickfix patterns reindexed
        │
        ▼
Annotations re-added at new line numbers
```

#### Case 5: Navigating Within Same File

**Problem**: `BufEnter` fires on every quickfix navigation, even within same file

**Solution**: Idempotent annotation function

```vim
" In s:DoAddVirtualText():
let existing_props = prop_list(a:line_num, {'type': l:prop_type})
let first_line = split(a:text, '\n', 1)[0]
for prop in existing_props
  if has_key(prop, 'text') && stridx(prop.text, first_line) >= 0
    return  " Already annotated, skip
  endif
endfor
```

**Why This Works**:

- Checks if annotation already exists before adding
- Uses first line of text as unique identifier
- Prevents duplicate annotations on repeated `BufEnter`
- No need to clear and re-add annotations

---

## Performance Considerations

### Context Update Frequency

**High-frequency events**: `CursorMoved`, `CursorMovedI`

- Fires on every cursor movement
- Sends JSON message over Unix socket
- **Mitigation**: Unix sockets are very fast (local IPC)
- **Alternative considered**: Debouncing with timer
  - Rejected: Adds complexity, delays context updates
  - Current approach: Simple, responsive, fast enough

### Annotation Rendering

**Text properties are efficient**:

- Vim's native implementation
- No custom rendering logic needed
- Survives buffer modifications (within limits)

**Padding trade-off**:

- Pads to window width + 30 for full-line background
- Uses more memory for longer strings
- **Alternative**: Dynamic padding on window resize
  - Rejected: Requires autocmd, re-rendering, complexity

### File Reading for Pattern Matching

**`readfile()` on every reindex**:

- Reads entire file from disk
- Could be slow for large files
- **Mitigation**: Only reads files with quickfix entries
- **Alternative**: Use buffer APIs
  - Problem: Doesn't work for unloaded buffers
  - Problem: Doesn't reflect external changes

---

## Future Improvements

### Security

1. **Input Validation**: Validate socket paths, file paths, message sizes
2. **Rate Limiting**: Prevent DoS via rapid message sending
3. **Sanitize Logs**: Prevent sensitive data leakage in error messages

### Code Quality

1. **Namespace Global Variables**: Prefix with `g:vim_q_connect_*`
2. **Specific Exception Handling**: Catch specific exceptions instead of `Exception`
3. **Configurable Timeouts**: Make socket timeout configurable via environment variable

### Features

1. **Annotation Persistence**: Save annotations to file, restore on reload
2. **Annotation Management**: Commands to list, filter, clear specific annotations
3. **Multi-line Context**: Send more context lines around cursor
4. **Incremental Context**: Only send changed portions of file

### Performance

1. **Debounced Context Updates**: Reduce update frequency with timer
2. **Lazy File Reading**: Cache file contents, invalidate on modification
3. **Partial Reindexing**: Only reindex changed regions of file

---

## Debugging Tips

### Enable Verbose Logging

**MCP Server**:

```python
logging.basicConfig(level=logging.DEBUG)
```

**Vim**:

```vim
:set verbose=9
:set verbosefile=/tmp/vim-debug.log
```

### Inspect Channel Status

```vim
:echo ch_status(g:mcp_channel)  " Should be 'open'
:echo ch_info(g:mcp_channel)    " Detailed info
```

### View Text Properties

```vim
:call prop_list(line('.'))  " Properties on current line
:call prop_type_list()      " All property types
```

### Check Quickfix User Data

```vim
:echo getqflist({'all': 1}).items[0].user_data
```

### Monitor Socket Communication

```bash
# Terminal 1: Start MCP server
cd mcp-server && python main.py

# Terminal 2: Monitor socket
socat -v UNIX-CONNECT:.vim-q-mcp.sock -
```

---

## Glossary

- **MCP**: Model Context Protocol - standardized protocol for LLM context sharing
- **Unix Domain Socket**: IPC mechanism for local process communication
- **Text Property**: Vim's system for attaching metadata/virtual text to buffer lines
- **Quickfix List**: Vim's built-in list for errors, warnings, search results, etc.
- **Autoread**: Vim feature to automatically reload files changed externally
- **Channel**: Vim's asynchronous I/O mechanism for communicating with external processes
- **Autocmd**: Vim's event system for triggering actions on specific events
- **Virtual Text**: Text displayed in editor but not part of actual file content

