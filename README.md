# vim-q-connect

**Seamlessly integrate Amazon Q CLI with Vim for AI-powered coding assistance**

vim-q-connect bridges the gap between Vim and Amazon Q CLI, enabling real-time context sharing and intelligent code assistance directly in your editor. Ask Q about your code, get inline suggestions, navigate to issues, and receive AI-powered code reviews—all without leaving Vim.

## What Does It Do?

vim-q-connect creates a bidirectional connection between Vim and Q CLI using the Model Context Protocol (MCP):

- **🔍 Context Awareness**: Q CLI automatically knows what code you're looking at—no need to copy-paste
- **🎯 Smart Navigation**: Q can jump your cursor to specific lines and files
- **💬 Inline Annotations**: Get code reviews, security findings, and suggestions displayed directly above relevant lines
- **⚡ Real-time**: Updates happen instantly as you move through your code
- **🔗 Quickfix Integration**: Code analysis results automatically populate Vim's quickfix list with inline annotations

### Example Workflows

**Code Review**:

```
You (to Q): "Review this function for security issues"
Q: [Analyzes code, adds inline annotations in Vim]
```

```python
def process_user_input(data):
    # 🔒 SECURITY: Missing input validation
    # Validate and sanitize user input before processing
    # Consider using a schema validation library
    return database.query(data)
```

**Navigate to Issues**:

```
You (to Q): "Check this codebase for quality issues"
Q: [Populates quickfix list with findings im Vim]
```

Navigate through issues with `:cnext`/`:cprev`, annotations appear automatically.

**Explain Code**:

```
You (to Q): "What does this function do?"
Q: [Reads your current cursor position im Vim and explains the code]
```

**Fix Quickfix Issues**:

```
You (to Q): "Check this codebase for issues"
Q: [Populates quickfix list with findings]
You (in Vim): [Navigate to a quickfix issue with :cnext]
You (to Q): "Fix this issue"
Q: [Reads the current quickfix entry and applies the fix]
```

## Requirements

### Vim
- **Version**: Vim 8.1+ or Neovim 0.5+
- **Feature**: Text properties support (`:echo has('textprop')` should return 1)
- **OS**: Linux or macOS (Unix domain sockets required)

### MCP Server
- **Python**: 3.8 or higher
- **Dependencies**: FastMCP library (installed via `uv` or `pip`)

### Q CLI
- Amazon Q CLI installed and configured
- MCP server configuration (see [Configuration](#configuration) below)

## Installation

### Step 1: Install the Vim Plugin

#### Using vim-plug

Add to your `.vimrc` or `init.vim`:

```vim
Plug 'edouardp/vim-q-connect'
```

Then run:
```vim
:PlugInstall
```

#### Using Vundle

Add to your `.vimrc`:
```vim
Plugin 'edouardp/vim-q-connect'
```

Then run:
```vim
:PluginInstall
```

#### Manual Installation

```bash
git clone https://github.com/edouardp/vim-q-connect.git ~/.vim/pack/plugins/start/vim-q-connect
```

### Step 2: Install MCP Server Dependencies

The MCP server requires Python 3.8+ and the FastMCP library.

#### Using uv (recommended)

```bash
cd ~/.vim/pack/plugins/start/vim-q-connect/mcp-server
uv sync
```

#### Using pip

```bash
cd ~/.vim/pack/plugins/start/vim-q-connect/mcp-server
pip install fastmcp
```

### Step 3: Configure Q CLI

Q CLI needs to know about the MCP server. Add the server configuration to your Q CLI MCP settings.

#### Option A: Using mcp.json (if supported)

Create or edit `~/.aws/amazonq/mcp.json`:

```json
{
  "mcpServers": {
    "vim-q-connect": {
      "command": "~/.vim/plugged/vim-q-connect/mcp-server/run-mcp.sh",
      "args": [],
      "env": {},
      "disabled": false,
      "autoApprove": [],
      "capabilities": ["prompts"]
    }
  }
}
```

#### Option B: Using CLI Agents Directory

Create `~/.aws/amazonq/cli-agents/vim-q-connect.json`:

```json
{
  "name": "vim-q-connect",
  "command": "~/.vim/plugged/vim-q-connect/mcp-server/run-mcp.sh",
  "args": [],
  "env": {},
  "disabled": false,
  "autoApprove": [],
  "capabilities": ["prompts"]
}
```

**Note**: Adjust the path based on your plugin manager:
- **vim-plug**: `~/.vim/plugged/vim-q-connect/mcp-server/run-mcp.sh`
- **Vundle**: `~/.vim/bundle/vim-q-connect/mcp-server/run-mcp.sh`
- **Manual**: `~/.vim/pack/plugins/start/vim-q-connect/mcp-server/run-mcp.sh`

## Configuration

### Socket Location

The MCP server automatically creates a Unix socket in `/tmp/vim-q-connect/{SHA256}/sock` where `{SHA256}` is the hash of the current working directory. This approach ensures:

- Socket paths never exceed Unix domain socket length limits
- Each project directory gets its own unique socket
- Sockets are automatically cleaned up on system restart

The `run-mcp.sh` script handles socket path configuration automatically.

### Vim Settings

The plugin works out of the box with no configuration required. However, you can customize various aspects:

```vim
" Optional: Override socket path (default: /tmp/vim-q-connect/{hash}/sock)
let g:vim_q_connect_socket_path = '/custom/path/.vim-q-mcp.sock'

" Optional: Customize annotation display characters
let g:vim_q_connect_first_line_char = '┤'      " Character after emoji on first line
let g:vim_q_connect_continuation_char = '│'    " Character for continuation lines

" Or:
let g:vim_q_connect_first_line_char = '●'      " Character after emoji on first line
let g:vim_q_connect_continuation_char = '┊'    " Character for continuation lines
```

### MCP Server Logging

To enable debug logging, edit `mcp-server/main.py`:

```python
# Change INFO to DEBUG for verbose logging
logging.basicConfig(level=logging.DEBUG, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
```

## Usage

### Starting the Connection

1. **Start Q CLI** (this automatically starts the MCP server)

   ```bash
   q chat
   ```

2. **In Vim, connect to the MCP server**

   ```vim
   :QConnect
   ```

   You should see: `Q MCP channel connected`

3. **Start coding!** Q CLI now has real-time access to your editor context.

### Stopping the Connection

```vim
:QConnect!
```

This disconnects from the MCP server and stops sending context updates.

### Available Commands

| Command | Description |
|---------|-------------|
| `:QConnect` | Connect to Q CLI MCP server and start context tracking |
| `:QConnect!` | Disconnect and stop context tracking |
| `:QVirtualTextClear` | Clear all inline annotations from current buffer |
| `:QHighlightsClear` | Clear all background highlights from current buffer |
| `:QQuickfixAnnotate` | Manually annotate quickfix entries (usually automatic) |
| `:QQuickfixAutoAnnotate` | Enable auto-annotation mode for quickfix entries |
| `:QQuickfixAutoAnnotate!` | Disable auto-annotation mode |
| `:QQuickfixClear` | Clear all quickfix entries |

### Available Prompts

vim-q-connect provides pre-built prompts that you can use with Q CLI. Access them by typing `@` in Q CLI:

| Prompt | Description | Best Used When |
|--------|-------------|----------------|
| `@review` | Comprehensive code review for security, quality, performance, and best practices. Populates quickfix list with issues and adds inline annotations. | You want a thorough analysis of your code with actionable findings |
| `@explain` | Detailed explanation of what the current code does, how it works, and important details. | You're reading unfamiliar code or need to understand complex logic |
| `@fix` | Intelligently fixes code issues. Auto-detects current quickfix issue or analyzes current code context. | You have a specific issue to resolve or want to fix problems in your current code |
| `@doc` | Adds comprehensive documentation including docstrings, inline comments, and type hints. | Your code lacks documentation or you want to improve maintainability |

**Key Features**:
- **Context-aware**: All prompts automatically know your current file, cursor position, and selected text
- **Quickfix integration**: `@review` populates Vim's quickfix list for easy navigation
- **Smart targeting**: Use optional parameters (e.g., `@fix "performance issues"`) for specific focus
- **Inline annotations**: Visual feedback appears directly in your editor

**Example workflows**:
```
# Comprehensive code review
You: @review
Q: [Analyzes code, adds quickfix entries and inline annotations]
You: :cnext  [Navigate to first issue]
You: @fix    [Fix the current quickfix issue]

# Understanding unfamiliar code
You: [Select a complex function]
You: @explain
Q: [Explains the selected function in detail]

# Adding documentation
You: [Position cursor in undocumented function]
You: @doc
Q: [Adds docstrings, comments, and type hints]
```

## How to Use with Q CLI

Once connected, Q CLI can access your editor context through several tools:

### Available MCP Tools

| Tool | Description |
|------|-------------|
| `get_editor_context` | Retrieve current file, cursor position, selection, and metadata |
| `goto_line` | Navigate cursor to specific line/file in Vim |
| `add_virtual_text` | Add inline annotations and virtual text above code lines |
| `highlight_text` | Add background color highlights with optional hover text |
| `clear_highlights` | Remove all highlights from buffer or specific file |
| `add_to_quickfix` | Populate Vim's quickfix list with findings |
| `get_current_quickfix_entry` | Get the quickfix entry at cursor position |
| `clear_quickfix` | Clear all quickfix entries |
| `get_annotations_above_current_position` | Retrieve annotations near cursor |
| `clear_annotations` | Remove all virtual text annotations |

### 1. Ask Questions About Your Code

Q automatically knows what code you're looking at:

```
You: "What does this function do?"
You: "How can I optimize this?"
You: "Are there any security issues here?"
```

Q will use `get_editor_context` to read your current file, cursor position, and any selected text.

### 2. Get Code Reviews with Inline Annotations

```
You: "Review this code for best practices"
You: "Check for security vulnerabilities"
You: "Analyze performance bottlenecks"
```

Q will add inline annotations above relevant lines using `add_virtual_text`:

```python
def authenticate(username, password):
    # 🔒 SECURITY: Password stored in plain text
    # Use a secure hashing algorithm like bcrypt or Argon2
    # Never store passwords in plain text
    if users[username] == password:
        return True
```

### 3. Navigate to Specific Code

Q can move your cursor to specific locations:

```
You: "Show me the main function"
You: "Go to line 42"
```

Q uses `goto_line` to navigate your editor.

### 4. Populate Quickfix List

```
You: "Find all TODO comments"
You: "Check this codebase for issues"
```

Q can add findings to Vim's quickfix list using `add_to_quickfix`. Navigate with:

- `:cnext` - Next issue
- `:cprev` - Previous issue
- `:copen` - Open quickfix window
- `:cclose` - Close quickfix window

Annotations appear automatically when you navigate to each issue.

## Features in Detail

### Real-time Context Sharing

The plugin automatically sends your editor state to Q CLI whenever you:

- Move the cursor
- Change files
- Select text (visual mode)
- Edit content

Q always knows:

- What file you're viewing
- What line your cursor is on
- What text you have selected
- File metadata (encoding, line endings, modification status)

### Inline Annotations

Annotations appear as virtual text above code lines with:

- **Emoji indicators** for visual categorization (🔒 security, ⚡ performance, etc.)
- **Multi-line support** for detailed explanations
- **Syntax highlighting** with customizable colors
- **Persistence** across buffer switches (until cleared)

**Customizing Annotation Colors**:

```vim
" Add to your .vimrc
highlight qtext ctermbg=235 ctermfg=248 cterm=italic guibg=#1c1c1c guifg=#a8a8a8 gui=italic
```

### Quickfix Integration

When Q adds entries to the quickfix list:

1. Entries are automatically sorted by file and line number
2. Annotations appear when you navigate to each entry
3. Line numbers update automatically if files are modified externally
4. Annotations persist across file reloads (via autoread)

### Autoread Support

The plugin enables Vim's `autoread` feature and automatically:

- Detects when files change externally (git checkout, build tools, etc.)
- Reloads files automatically
- Re-applies annotations at correct line numbers
- Updates quickfix entries to match new line numbers

## Troubleshooting

### "Q MCP channel connected" doesn't appear

**Check MCP server is running**:

```bash
ps aux | grep "python.*main.py"
```

**Check socket exists**:

```bash
ls -la /tmp/vim-q-connect/$(echo -n $(pwd) | shasum -a 256 | cut -d' ' -f1)/sock
```

**Check Q CLI configuration**:

```bash
cat ~/.aws/amazonq/cli-agents/vim-context.json
```

### Annotations don't appear

**Verify text properties support**:

```vim
:echo has('textprop')
```
Should return `1`. If not, upgrade Vim to 8.1+.

**Check for conflicting plugins**:

Temporarily disable other plugins to isolate the issue.

**Verify connection**:

```vim
:echo ch_status(g:mcp_channel)
```
Should return `open`.

### Q CLI doesn't see my code

**Trigger a context update**:

Move your cursor or switch buffers to send a fresh context update.

**Reconnect**:

```vim
:QConnect!
:QConnect
```

**Check you're in a normal buffer**:
The plugin doesn't send context for terminal buffers, NERDTree, or other special buffers.

### Annotations appear in wrong locations after file changes

This should be handled automatically. If not:

**Manually refresh**:

```vim
:QQuickfixAnnotate
```

**Check autoread is enabled**:

```vim
:set autoread?
```
Should show `autoread`.

## Advanced Usage

### Custom Socket Path

If you need to use a specific socket path:

```vim
let g:vim_q_connect_socket_path = '/custom/path/.vim-q-mcp.sock'
```

Make sure to update the socket path in Vim as well.

### Running MCP Server Standalone

For testing or development:

```bash
cd mcp-server
./run-mcp.sh
```

Then connect from Vim with `:QConnect`.

### Debugging

**Enable verbose Vim logging**:

```vim
:set verbose=9
:set verbosefile=/tmp/vim-debug.log
```

**Enable MCP server debug logging**:

Edit `mcp-server/main.py`:
```python
logging.basicConfig(level=logging.DEBUG)
```

**Inspect text properties**:

```vim
:call prop_list(line('.'))
```

**View quickfix user data**:

```vim
:echo getqflist({'all': 1}).items[0].user_data
```

## Technical Details

For developers interested in how vim-q-connect works internally, see [DESIGN_DECISIONS.md](DESIGN_DECISIONS.md) for:

- Architecture and communication protocols
- Threading model and state management
- Annotation system implementation
- Quickfix integration details
- Performance considerations

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

For bug reports and feature requests, please open an issue on GitHub.

## License

MIT License - see LICENSE file for details.

## Support

- **Issues**: https://github.com/edouardp/vim-q-connect/issues
- **Documentation**: See [DESIGN_DECISIONS.md](DESIGN_DECISIONS.md) for technical details
- **Q CLI Documentation**: https://docs.aws.amazon.com/amazonq/

## Acknowledgments

Built with:

- [FastMCP](https://github.com/jlowin/fastmcp) - MCP server framework
- Vim's text properties system
- Amazon Q CLI and Model Context Protocol
