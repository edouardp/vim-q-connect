# vim-q-connect

A Vim plugin that provides editor context to Q CLI via Model Context Protocol (MCP).

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

The plugin connects to Q CLI's MCP server on demand. Use `:QConnect` to start tracking editor context.

### Commands

- `:QConnect` - Start tracking and send context to Q CLI
- `:QConnect!` - Stop tracking and disconnect

## Configuration

```vim
" Custom socket path (default: plugin directory + '/.vim-q-mcp.sock')
let g:vim_q_connect_socket_path = '/path/to/custom.sock'
```

## How it Works

When connected, the plugin:
1. Tracks your cursor position and current line
2. Sends context updates via Unix socket to Q CLI's MCP server
3. Q CLI can use `get_editor_context` and `goto_line` tools

## Integration with Q CLI

Q CLI manages the MCP server lifecycle. The plugin only connects to an existing server when you run `:QConnect`.