"""
MCP tools for highlights in the editor.
"""

import logging
from typing import Dict, Any

logger = logging.getLogger("vim-context")


def highlight_text(vim_state: Any, entries: list[Dict[str, Any]]) -> str:
    """Add multiple background color highlights to code regions with optional hover text.

    Creates highlighted regions with bold text and background color. When the cursor
    is positioned within highlighted text, optional virtual text appears above
    the first line of the highlight.

    Args:
        entries: List of dictionaries, each containing:
            - start_line (int): Starting line number (1-indexed)
            - end_line (int, optional): Ending line number. If not provided, highlights single line
            - start_col (int, optional): Starting column (1-indexed, default: 1)
            - end_col (int, optional): Ending column. If not provided, highlights to end of line
            - color (str): Highlight color - yellow, orange, pink, green, blue, purple (default: yellow)
            - virtual_text (str, optional): Text to show above highlight when cursor is on it

    Returns:
        Status message indicating success or failure
    """

    if not vim_state.is_connected():
        return "Vim not connected to MCP socket"

    valid_colors = ["yellow", "orange", "pink", "green", "blue", "purple"]

    try:
        processed = 0
        for entry in entries:
            # Validate required fields
            if "start_line" not in entry:
                logger.warning(f"Highlight entry missing start_line: {entry}")
                continue

            start_line = entry["start_line"]
            end_line = entry.get("end_line", start_line)
            start_col = entry.get("start_col", 1)
            end_col = entry.get("end_col", -1)
            color = entry.get("color", "yellow")
            virtual_text = entry.get("virtual_text", "")

            # Validate color
            if color not in valid_colors:
                logger.warning(f"Invalid highlight color '{color}': {entry}")
                continue

            vim_state.request_queue.put(
                (
                    "highlight_text",
                    {
                        "method": "highlight_text",
                        "params": {
                            "start_line": start_line,
                            "end_line": end_line,
                            "start_col": start_col,
                            "end_col": end_col,
                            "color": color,
                            "virtual_text": virtual_text,
                        },
                    },
                )
            )
            processed += 1

        return f"Added {processed} highlights"
    except Exception as e:
        logger.error(f"Error sending highlight command: {e}")
        return f"Error sending highlight command: {e}"


def clear_highlights(vim_state: Any, filename: str = "") -> str:
    """Clear all text highlights from a specific file or current buffer in Vim.

    Removes all background highlights that were previously added using highlight_text.
    This does not affect virtual text annotations added via add_virtual_text.

    Args:
        filename (str, optional): File path to clear highlights from.
                                 If empty, clears from current buffer.

    Returns:
        Status message indicating success or failure
    """

    if not vim_state.is_connected():
        return "Vim not connected to MCP socket"

    try:
        vim_state.request_queue.put(
            (
                "clear_highlights",
                {"method": "clear_highlights", "params": {"filename": filename}},
            )
        )

        target = f"from {filename}" if filename else "from current buffer"
        return f"Cleared all highlights {target}"
    except Exception as e:
        logger.error(f"Error sending clear highlights command: {e}")
        return f"Error sending clear highlights command: {e}"
