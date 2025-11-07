# vim-q-connect

A Vim plugin that provides bidirectional editor integration with Q CLI via Model Context Protocol (MCP). Enables real-time context sharing, remote navigation, and virtual text annotations.

## Features

- **Real-time Context Sharing**: Automatically sends cursor position, file content, and visual selections to Q CLI
- **Remote Navigation**: Q CLI can navigate to specific lines and files in your editor
- **Virtual Text Annotations**: Display inline code review comments, suggestions, and analysis results
- **Low-latency Communication**: Unix domain socket for fast IPC between Vim and Q CLI
- **Thread-safe**: Handles concurrent requests and multiple annotation operations

## Installation

### Using vim-plug

Add to your `.vimrc`:

```vim
Plug 'edouardp/vim-q-connect'
```

Then run `:PlugInstall`

### Manual Installation

Clone this repository to your Vim plugin directory:

```bash
git clone https://github.com/edouardp/vim-q-connect.git ~/.vim/plugged/vim-q-connect
```

## Usage

### Basic Commands

- `:QConnect` - Start tracking and send context to Q CLI
- `:QConnect!` - Stop tracking and disconnect
- `:QVirtualTextClear` - Clear all virtual text annotations from the current buffer

### Workflow

1. Start Q CLI with MCP server support
2. In Vim, run `:QConnect` to establish connection
3. Q CLI can now:
   - Read your current editor context with `get_editor_context`
   - Navigate to specific lines with `goto_line`
   - Add inline annotations with `add_virtual_text`
   - Query existing annotations with `get_annotations_above_current_position`

## MCP Tools Provided

### get_editor_context

Retrieves current editor state including:
- Current filename and line number
- Visible content around cursor
- Visual selection range (if active)
- File metadata (total lines, modified status, encoding, line endings)

**Use cases**: Code review, debugging, context-aware assistance

### goto_line

Navigate to a specific line in Vim, optionally opening a different file.

**Parameters**:
- `line_number` (int): Target line number (1-indexed)
- `filename` (str, optional): File to open before navigation

**Use cases**: Jump to error locations, navigate to definitions, follow references

### add_virtual_text

Add inline annotations above specific lines. Supports batch operations for efficiency.

**Parameters**:
- `entries` (list[dict]): List of annotation entries, each containing:
  - `line` (str): Exact line content to match (preferred - robust to edits)
  - `line_number` (int): Alternative line number (use only when line content unknown)
  - `text` (str): Annotation text (supports multi-line with `\n`)
  - `highlight` (str, optional): Vim highlight group
  - `emoji` (str, optional): Single emoji for visual emphasis

**Use cases**: 
- Code reviews with inline feedback
- Static analysis results
- Security findings
- Performance suggestions
- Documentation and examples
- Test coverage gaps

**Example**:
```python
add_virtual_text([
    {
        "line": "def process_data(input):",
        "text": "SECURITY: Validate input before processing\nConsider using schema validation",
        "emoji": "🔒"
    },
    {
        "line_number": 45,
        "text": "PERFORMANCE: This loop is O(n²)\nConsider using a hash map for O(n) complexity",
        "emoji": "⚡"
    }
])
```

### get_annotations_above_current_position

Retrieves all virtual text annotations displayed above the current cursor position.

**Returns**: JSON array of annotations with line numbers, types, and text content

**Use cases**: Query existing annotations, implement annotation management, debugging

## How it Works

### Architecture

```
┌─────────────┐         Unix Socket          ┌──────────────┐
│             │◄────────────────────────────►│              │
│  Vim Plugin │   JSON-RPC Messages          │  MCP Server  │
│             │                              │              │
└─────────────┘                              └──────┬───────┘
      │                                             │
      │ Context Updates                             │ MCP Protocol
      │ Navigation Commands                         │
      │ Annotation Requests                         │
      │                                             ▼
      │                                      ┌──────────────┐
      └──────────────────────────────────────┤    Q CLI     │
                                             └──────────────┘
```

### Communication Flow

1. **Connection**: Plugin connects to MCP server's Unix socket at `.vim-q-mcp.sock`
2. **Context Updates**: On cursor movement, plugin sends `context_update` messages
3. **Tool Invocation**: Q CLI calls MCP tools which send requests to Vim via socket
4. **Response Handling**: Vim processes requests and sends responses back through socket

### Message Protocol

All messages are JSON-RPC formatted and newline-delimited:

**Context Update** (Vim → Server):
```json
{
  "method": "context_update",
  "params": {
    "filename": "main.py",
    "line": 42,
    "context": "def foo():\n    return bar",
    "visual_start": 0,
    "visual_end": 0,
    "total_lines": 100,
    "modified": false,
    "encoding": "utf-8",
    "line_endings": "unix"
  }
}
```

**Navigation Command** (Server → Vim):
```json
{
  "method": "goto_line",
  "params": {
    "line": 42,
    "filename": "main.py"
  }
}
```

**Virtual Text** (Server → Vim):
```json
{
  "method": "add_virtual_text_batch",
  "params": {
    "entries": [
      {
        "line": "def foo():",
        "text": "This function needs documentation",
        "emoji": "📝"
      }
    ]
  }
}
```

## Configuration

### Socket Location

By default, the MCP server creates the socket in the directory specified by `SOCKET_DIR` environment variable, or current directory if not set.

```bash
export SOCKET_DIR=/tmp
```

### Logging

The MCP server logs to stdout with INFO level by default. Adjust in `mcp-server/main.py`:

```python
logging.basicConfig(level=logging.DEBUG)
```

## Development

### Project Structure

```
vim-q-connect/
├── plugin/
│   └── vim_q_connect.vim    # Vim plugin implementation
├── mcp-server/
│   └── main.py              # MCP server with FastMCP
└── README.md
```

### Running the MCP Server Standalone

```bash
cd mcp-server
python main.py
```

### Testing

1. Start the MCP server
2. Open Vim and run `:QConnect`
3. Use Q CLI to interact with editor context

## Troubleshooting

### Connection Issues

**Problem**: `:QConnect` doesn't establish connection

**Solutions**:
- Ensure MCP server is running
- Check socket file exists: `ls -la .vim-q-mcp.sock`
- Verify `SOCKET_DIR` environment variable
- Check server logs for errors

### Annotations Not Appearing

**Problem**: Virtual text annotations don't show in Vim

**Solutions**:
- Ensure Vim version supports text properties (Vim 8.1+)
- Check `:echo has('textprop')` returns 1
- Verify connection with `:QConnect`
- Check for conflicting plugins

### Stale Context

**Problem**: Q CLI receives outdated editor context

**Solutions**:
- Move cursor to trigger context update
- Reconnect with `:QConnect!` then `:QConnect`
- Check Vim logs for connection errors

## Integration with Q CLI

Q CLI manages the MCP server lifecycle automatically. The plugin connects to an existing server when you run `:QConnect`.

### Typical Workflow

1. Start Q CLI (automatically starts MCP server)
2. Open Vim and run `:QConnect`
3. Ask Q CLI questions about your code: "What does this function do?"
4. Q CLI uses `get_editor_context` to read your current code
5. Q CLI can add annotations: "Review this code for security issues"
6. Annotations appear inline in your editor

## Requirements

- Vim 8.1+ with text properties support
- Python 3.8+ (for MCP server)
- FastMCP library
- Unix-like operating system (Linux, macOS)

## License

MIT

## Contributing

Contributions welcome! Please open issues or pull requests on GitHub.
