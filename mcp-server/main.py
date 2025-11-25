"""
MCP Server for vim-q-connect plugin

This server provides Model Context Protocol (MCP) integration between Vim and Q CLI.
It enables bidirectional communication for editor context sharing and remote control.

Key Features:
- Real-time editor context reception from vim-q-connect plugin
- Virtual text annotation and highlight support with navigation
- Unix domain socket communication for low-latency IPC
- Thread-safe message handling and client management

MCP Tools Provided:
- get_editor_context: Retrieve current Vim editor state and context
- goto_line: Navigate to specific line/file in Vim editor
- add_virtual_text: Add annotations and virtual text to editor
- highlight_text: Add background color highlights with hover text
- clear_highlights: Remove all highlights from buffer or file
- add_to_quickfix: Populate Vim's quickfix list with findings
- clear_quickfix: Clear all quickfix entries
- get_current_quickfix_entry: Get the quickfix entry at cursor
- clear_annotations: Remove all virtual text annotations
- get_annotations_above_current_position: Get annotations at current position

Usage:
    python main.py [socket_path]

The server listens on a Unix domain socket and handles JSON-RPC messages
from both the vim-q-connect plugin and Q CLI MCP client.
"""

import sys
import signal
from typing import Optional
from fastmcp import FastMCP

# Import modules
from config import logger
from vim_state import VimState
from socket_server import start_socket_server
from tools import (
    get_editor_context,
    goto_line,
    add_to_quickfix,
    get_current_quickfix_entry,
    clear_quickfix,
)
from annotations_tools import (
    add_virtual_text,
    get_annotations_above_current_position,
    clear_annotations,
)
from highlights_tools import (
    highlight_text,
    clear_highlights,
)
from prompts import review_prompt, explain_prompt, fix_prompt, doc_prompt

# Initialize MCP server and global vim_state
mcp = FastMCP("vim-context")
vim_state = VimState()


# ============================================================================
# MCP Tools
# ============================================================================


@mcp.tool()
def get_editor_context_tool() -> dict:
    """Get the current editor context from Vim via channel. Use this tool
    whenever the user refers to code they are looking at in their editor, such
    as: "what is this", "explain this function", "how does this work", "what's
    wrong with this code", "optimize this", "add tests for this", "refactor
    this", "this file", "the current file", "this code", "the code I'm looking
    at", "can you help me with this", "review this", or any reference to
    current editor content.
    """
    return get_editor_context(vim_state)


@mcp.tool()
def goto_line_tool(line_number: int, filename: Optional[str] = None) -> str:
    """Navigate to a specific line in Vim."""
    return goto_line(vim_state, line_number, filename)


@mcp.tool()
def add_virtual_text_tool(entries: list[dict]) -> str:
    """Add multiple virtual text entries efficiently to annotate the user's file in their editor.

    Use this tool when you have analysis data that would be valuable as in-line annotations or virtual text in the user's editor.

    Common use cases:
    - Code reviews: Add security findings, performance notes, best practice suggestions
    - Static analysis: Show type information, complexity metrics, potential bugs
    - Documentation: Add explanations, examples, or API usage notes
    - Debugging: Highlight problematic lines with explanations
    - Refactoring suggestions: Mark areas for improvement with specific recommendations
    - Test coverage: Show which lines need testing or have coverage gaps

    Args:
        entries: List of dictionaries, each containing:
            - line (str): Exact text content of the line to search for. Use this line argument in preference to line_number because it's more robust.
            - line_number (int): Alternative to line. 1-indexed line number to add virtual text above.
            - text (str): The annotation text to display (supports multi-line with \\n).
            - highlight (str, optional): Vim highlight group
            - emoji (str, optional): Single emoji character for visual emphasis
    """
    return add_virtual_text(vim_state, entries)


@mcp.tool()
def add_to_quickfix_tool(entries: list[dict]) -> str:
    """Add multiple entries to Vim's quickfix list for navigation and issue tracking.

    Use this tool when you have findings that users should navigate through, such as:
    - Compilation errors or warnings
    - Linting issues
    - Test failures
    - Code review findings
    - Security vulnerabilities
    - Performance bottlenecks

    Args:
        entries: List of dictionaries, each containing:
            - line (str): Exact text content of the line to search for (preferred)
            - line_number (int): Alternative to line. 1-indexed line number
            - text (str): Description of the issue or finding
            - filename (str, optional): File path (defaults to current file)
            - type (str, optional): Entry type - 'E' (error), 'W' (warning), 'I' (info), 'N' (note)
            - line_number_hint (int, optional): Hint for tie-breaking when multiple matches exist
    """
    return add_to_quickfix(vim_state, entries)


@mcp.tool()
def get_current_quickfix_entry_tool() -> dict:
    """Get the current quickfix entry that the user is focused on.

    Use this tool when the user says "fix this", "fix this issue", "fix this quickfix issue",
    or any reference to fixing the current problem they're looking at.

    Returns:
        Dictionary containing:
        - text: The full quickfix entry text (may be multi-line)
        - filename: The file path
        - line_number: The line number in the file
        - type: Error level ('E' for error, 'W' for warning, 'I' for info, 'N' for note)
        - error: Error message if quickfix is empty or Vim not connected
    """
    return get_current_quickfix_entry(vim_state)


@mcp.tool()
def clear_quickfix_tool() -> str:
    """Clear all entries from Vim's quickfix list.

    Removes all quickfix entries and closes the quickfix window if open.
    Useful for cleaning up after resolving issues or starting fresh analysis.

    Returns:
        Status message indicating success or failure
    """
    return clear_quickfix(vim_state)


@mcp.tool()
def get_annotations_above_current_position_tool() -> str:
    """Get all text property annotations above the current cursor position.

    Returns all virtual text annotations (text props) that are displayed above
    the line where the cursor is currently positioned in Vim.

    Returns:
        JSON string containing list of annotations with their text content and metadata
    """
    return get_annotations_above_current_position(vim_state)


@mcp.tool()
def clear_annotations_tool(filename: Optional[str] = None) -> str:
    """Clear all virtual text annotations from a specific file or current buffer in Vim.

    Removes all inline annotations and virtual text that were previously added
    using add_virtual_text. This is useful for cleaning up after code reviews
    or when annotations are no longer needed.

    Args:
        filename (str, optional): File path to clear annotations from.
                                 If empty, clears from current buffer.

    Returns:
        Status message indicating success or failure
    """
    return clear_annotations(vim_state, filename)


@mcp.tool()
def highlight_text_tool(entries: list[dict]) -> str:
    """Add multiple background color highlights to code regions with optional hover text.

    Args:
        entries: List of dictionaries, each containing:
            - start_line (int): Starting line number (1-indexed)
            - end_line (int, optional): Ending line number. If not provided, highlights single line
            - start_col (int, optional): Starting column (1-indexed, default: 1)
            - end_col (int, optional): Ending column. If not provided, highlights to end of line
            - color (str): Highlight color - yellow, orange, pink, green, blue, purple (default: yellow)
            - virtual_text (str, optional): Text to show above highlight when cursor is on it
    """
    return highlight_text(vim_state, entries)


@mcp.tool()
def clear_highlights_tool(filename: Optional[str] = None) -> str:
    """Clear all text highlights from a specific file or current buffer in Vim.

    Removes all background highlights that were previously added using highlight_text.
    This does not affect virtual text annotations added via add_virtual_text.

    Args:
        filename (str, optional): File path to clear highlights from.
                                 If empty, clears from current buffer.

    Returns:
        Status message indicating success or failure
    """
    return clear_highlights(vim_state, filename)


# ============================================================================
# MCP Prompts
# ============================================================================


@mcp.prompt()
def review(target: Optional[str] = None):
    """Review the code for quality, security, and best practices"""
    return review_prompt(vim_state, target)


@mcp.prompt()
def explain(target: Optional[str] = None):
    """Explain what the current code does by adding detailed annotations

    Provides comprehensive explanations as inline annotations using add_virtual_text,
    with overview and detailed technical explanations for senior developers.
    """
    return explain_prompt(vim_state, target)


@mcp.prompt()
def fix(target: Optional[str] = None):
    """Fix issues in code or the current quickfix issue"""
    return fix_prompt(vim_state, target)


@mcp.prompt()
def doc(target: Optional[str] = None):
    """Add documentation to the current code

    Adds appropriate documentation (docstrings, comments) to the code
    """
    return doc_prompt(vim_state, target)


# ============================================================================
# Lifecycle Management
# ============================================================================


def cleanup_and_exit():
    """Clean up resources and exit gracefully"""
    logger.info("Shutting down MCP server...")

    if vim_state.socket_server:
        try:
            vim_state.socket_server.close()
        except Exception as e:
            logger.error(f"Error closing socket server: {e}")

    if vim_state.vim_channel:
        try:
            vim_state.vim_channel.close()
        except Exception as e:
            logger.error(f"Error closing vim channel: {e}")

    sys.exit(0)


def signal_handler(signum, frame):
    """Handle shutdown signals"""
    logger.info(f"Received signal {signum}, shutting down...")
    cleanup_and_exit()


if __name__ == "__main__":
    # Set up signal handlers for graceful shutdown
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

    logger.info("Starting MCP server for vim-q-connect")
    start_socket_server(vim_state)
    mcp.run()
