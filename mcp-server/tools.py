"""
MCP tools for editor context and navigation.
"""

import json
import uuid
import queue
import logging
from typing import Dict, Any, Optional

logger = logging.getLogger("vim-context")


def get_editor_context(vim_state: Any) -> Dict[str, Any]:
    """Get the current editor context from Vim via channel. Use this tool
    whenever the user refers to code they are looking at in their editor, such
    as: "what is this", "explain this function", "how does this work", "what's
    wrong with this code", "optimize this", "add tests for this", "refactor
    this", "this file", "the current file", "this code", "the code I'm looking
    at", "can you help me with this", "review this", or any reference to
    current editor content.
    """

    if not vim_state.is_connected():
        return {
            "content": "Editor not connected - no context available",
            "filename": "",
            "current_line": 0,
            "visual_selection": None,
            "total_lines": 0,
            "modified": False,
            "encoding": "",
            "line_endings": "",
        }

    context = vim_state.get_context()
    visual_selection = None
    if context["visual_start"] > 0:
        visual_selection = {
            "start_line": context["visual_start"],
            "end_line": context["visual_end"],
        }
        # Only include column info if selection doesn't span full lines
        if context["visual_start_col"] > 0 or context["visual_end_col"] > 0:
            visual_selection["start_col"] = context["visual_start_col"]
            visual_selection["end_col"] = context["visual_end_col"]
            visual_selection["start_line_length"] = context["visual_start_line_len"]
            visual_selection["end_line_length"] = context["visual_end_line_len"]

    return {
        "content": context["context"],
        "filename": context["filename"],
        "current_line": context["line"],
        "visual_selection": visual_selection,
        "total_lines": context["total_lines"],
        "modified": context["modified"],
        "encoding": context["encoding"],
        "line_endings": context["line_endings"],
    }


def goto_line(vim_state: Any, line_number: int, filename: str = "") -> str:
    """Navigate to a specific line in Vim.

    Args:
        vim_state: Vim state object for communicating with the editor
        line_number: Line number to navigate to
        filename: Optional filename to navigate to (if not provided, navigates in current buffer)

    Returns:
        Confirmation message with navigation details, or error message if Vim is not connected
    """

    if not vim_state.is_connected():
        return "Vim not connected to MCP socket"

    try:
        vim_state.request_queue.put(
            (
                "goto_line",
                {
                    "method": "goto_line",
                    "params": {"line": line_number, "filename": filename},
                },
            )
        )

        return f"Navigation command sent: line {line_number}" + (
            f" in {filename}" if filename else ""
        )
    except Exception as e:
        logger.error(f"Error sending navigation command: {e}")
        return f"Error sending navigation command: {e}"


def add_to_quickfix(vim_state: Any, entries: list[Dict[str, Any]]) -> str:
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

    if not vim_state.is_connected():
        return "Vim not connected to MCP socket"

    try:
        vim_state.request_queue.put(
            (
                "add_to_quickfix",
                {"method": "add_to_quickfix", "params": {"entries": entries}},
            )
        )

        return f"Added {len(entries)} entries to quickfix list"
    except Exception as e:
        logger.error(f"Error sending quickfix command: {e}")
        return f"Error sending quickfix command: {e}"


def get_current_quickfix_entry(vim_state: Any) -> Dict[str, Any]:
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

    if not vim_state.is_connected():
        return {"error": "Vim not connected to MCP socket"}

    try:
        # Create unique request ID and response queue
        request_id = str(uuid.uuid4())
        response_queue: queue.Queue = queue.Queue()
        vim_state.response_queues[request_id] = response_queue

        # Put request in queue for server thread to send
        vim_state.request_queue.put(
            (
                "get_current_quickfix",
                {
                    "method": "get_current_quickfix",
                    "request_id": request_id,
                    "params": {},
                },
            )
        )

        # Wait for response
        try:
            response_type, data = response_queue.get(timeout=5.0)
            if response_type == "quickfix_entry":
                return data
            else:
                return {"error": f"Unexpected response type: {response_type}"}
        except queue.Empty:
            return {"error": "Timeout waiting for quickfix entry response"}
        finally:
            # Clean up response queue
            del vim_state.response_queues[request_id]

    except Exception as e:
        logger.error(f"Error requesting quickfix entry: {e}")
        return {"error": f"Error requesting quickfix entry: {e}"}


def clear_quickfix(vim_state: Any) -> str:
    """Clear all entries from Vim's quickfix list.

    Removes all quickfix entries and closes the quickfix window if open.
    Useful for cleaning up after resolving issues or starting fresh analysis.

    Returns:
        Status message indicating success or failure
    """

    if not vim_state.is_connected():
        return "Vim not connected to MCP socket"

    try:
        vim_state.request_queue.put(
            ("clear_quickfix", {"method": "clear_quickfix", "params": {}})
        )

        return "Cleared quickfix list"
    except Exception as e:
        logger.error(f"Error sending clear quickfix command: {e}")
        return f"Error sending clear quickfix command: {e}"
