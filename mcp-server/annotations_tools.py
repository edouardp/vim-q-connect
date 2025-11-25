"""
MCP tools for annotations and highlights in the editor.
"""

import json
import logging
import queue
import uuid
from typing import Any, Dict, Optional

logger = logging.getLogger("vim-context")


def add_virtual_text(vim_state: Any, entries: list[Dict[str, Any]]) -> str:
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
            - line (str): Exact text content of the line to search for. Use this line argument in preference to line_number because it's more robust - annotations stay correct even if line numbers shift due to edits.
            - line_number (int): Alternative to line. 1-indexed line number to add virtual text above. Don't use the line_number argument unless the line is absolutely known, e.g. from an immediately preceding get_editor_context tool call.
            - text (str): The annotation text to display (supports multi-line with \n). Any emoji characters at the beginning will be extracted and consumed.
            - highlight (str, optional): Vim highlight group (ignored for now - will always uses qtext styling)
            - emoji (str, optional): Single emoji character for visual emphasis. If provided, this takes precedence over any emoji extracted from text. Any emoji at the beginning of text will still be consumed. (defaults to Ｑ)
    """

    if not vim_state.is_connected():
        return "Vim not connected to MCP socket"

    try:
        logger.info(f"Adding batch virtual text: {len(entries)} entries")
        for i, entry in enumerate(entries):
            logger.debug(f"Entry {i}: {entry}")

        vim_state.request_queue.put(
            (
                "add_virtual_text_batch",
                {"method": "add_virtual_text_batch", "params": {"entries": entries}},
            )
        )

        logger.info("Successfully queued batch virtual text command")
        return f"Batch virtual text added: {len(entries)} entries"
    except Exception as e:
        logger.error(f"Error sending batch virtual text command: {e}")
        return f"Error sending batch virtual text command: {e}"


def get_annotations_above_current_position(vim_state: Any) -> str:
    """Get all text property annotations above the current cursor position.

    Returns all virtual text annotations (text props) that are displayed above
    the line where the cursor is currently positioned in Vim.

    Returns:
        JSON string containing list of annotations with their text content and metadata
    """

    if not vim_state.is_connected():
        return "Vim not connected to MCP socket"

    try:
        # Create unique request ID and response queue
        request_id = str(uuid.uuid4())
        response_queue: queue.Queue = queue.Queue()
        vim_state.response_queues[request_id] = response_queue

        # Put request in queue for server thread to send
        vim_state.request_queue.put(
            (
                "get_annotations",
                {"method": "get_annotations", "request_id": request_id, "params": {}},
            )
        )

        # Wait for response
        try:
            response_type, annotations = response_queue.get(timeout=5.0)
            if response_type == "annotations":
                return json.dumps(annotations)
            else:
                return f"Unexpected response type: {response_type}"
        except queue.Empty:
            return "Timeout waiting for annotations response"
        finally:
            # Clean up response queue
            del vim_state.response_queues[request_id]

    except Exception as e:
        logger.error(f"Error requesting annotations: {e}")
        return f"Error requesting annotations: {e}"


def clear_annotations(vim_state: Any, filename: Optional[str] = None) -> str:
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

    if not vim_state.is_connected():
        return "Vim not connected to MCP socket"

    try:
        vim_state.request_queue.put(
            (
                "clear_annotations",
                {"method": "clear_annotations", "params": {"filename": filename}},
            )
        )

        target = f"from {filename}" if filename else "from current buffer"
        return f"Cleared all annotations {target}"
    except Exception as e:
        logger.error(f"Error sending clear annotations command: {e}")
        return f"Error sending clear annotations command: {e}"
