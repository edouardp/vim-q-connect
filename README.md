# vim-llm-mcp

A Vim plugin that provides editor context to LLM tools via Model Context Protocol (MCP).

## Installation

### Using vim-plug

Add to your `.vimrc`:

```vim
Plug 'your-username/vim-llm-mcp'
```

Then run `:PlugInstall`

### Manual Installation

Clone this repository to your Vim plugin directory:

```bash
git clone https://github.com/your-username/vim-llm-mcp.git ~/.vim/plugged/vim-llm-mcp
```

## Requirements

- `netcat` (for socket communication)

## Usage

The plugin automatically starts tracking editor context when Vim starts. It sends context updates to an MCP server via Unix socket.

## Configuration

```vim
" Disable auto-start (default: 1)
let g:vim_llm_mcp_auto_start = 0

" Custom socket path (default: plugin directory + '/.vim-q-mcp.sock')
let g:vim_llm_mcp_socket_path = '/path/to/custom.sock'
```

## How it Works

The plugin:
1. Tracks your cursor position and current line
2. Sends context updates via Unix socket to MCP server
3. MCP server provides `get_editor_context` and `goto_line` tools to LLM clients

## MCP Server

Start the MCP server separately:

```bash
cd ~/.vim/plugged/vim-llm-mcp
uv sync
./run-mcp.sh
```

## Integration with Q CLI

Add this MCP server to your Q CLI configuration to enable editor context tools.