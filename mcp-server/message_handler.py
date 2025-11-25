"""
Message handling for incoming messages from the vim-q-connect plugin.
"""

import json
import logging
from typing import Any

logger = logging.getLogger("vim-context")


def handle_vim_message(message: str, vim_state: Any) -> None:
    """
    Process incoming messages from vim-q-connect plugin.

    Handles message types:
    - context_update: Updates the current editor context with file/cursor state
    - disconnect: Marks the Vim connection as disconnected
    - annotations_response: Returns annotations at current position
    - quickfix_entry_response: Returns current quickfix entry

    Args:
        message: JSON string containing method and params
        vim_state: VimState instance to update with new context

    Updates vim_state:
        current_context: Dictionary with editor state (filename, line, selection, etc.)
        vim_connected: Boolean flag indicating connection status
    """
    try:
        data = json.loads(message)

        if data.get("method") == "context_update":
            _handle_context_update(data, vim_state)
        elif data.get("method") == "disconnect":
            vim_state.set_connected(False)
            logger.info("Vim explicitly disconnected")
        elif data.get("method") == "annotations_response":
            _handle_annotations_response(data, vim_state)
        elif data.get("method") == "quickfix_entry_response":
            _handle_quickfix_response(data, vim_state)
    except Exception as e:
        logger.error(f"Error handling Vim message: {e}")


def _handle_context_update(data: dict, vim_state: Any) -> None:
    """Handle context_update messages from Vim."""
    params = data["params"]
    # Build normalized context dict with safe defaults to prevent KeyError
    # This ensures Q CLI always has complete editor state even if Vim sends partial data
    context = {
        "context": params.get(
            "context", "No context available"
        ),  # File content or selected text
        "filename": params.get("filename", ""),  # Absolute path to current file
        "line": params.get("line", 0),  # Current cursor line (1-indexed)
        "visual_start": params.get(
            "visual_start", 0
        ),  # Selection start line (0 = no selection)
        "visual_end": params.get(
            "visual_end", 0
        ),  # Selection end line (0 = no selection)
        "visual_start_col": params.get(
            "visual_start_col", 0
        ),  # Selection start column (1-indexed, 0 = no selection)
        "visual_end_col": params.get(
            "visual_end_col", 0
        ),  # Selection end column (1-indexed, 0 = no selection)
        "visual_start_line_len": params.get(
            "visual_start_line_len", 0
        ),  # Length of start line (0 = no selection)
        "visual_end_line_len": params.get(
            "visual_end_line_len", 0
        ),  # Length of end line (0 = no selection)
        "total_lines": params.get("total_lines", 0),  # Total lines in file
        "modified": params.get("modified", False),  # True if file has unsaved changes
        "encoding": params.get("encoding", ""),  # File encoding (utf-8, latin1, etc.)
        "line_endings": params.get(
            "line_endings", ""
        ),  # unix, dos, or mac line endings
    }
    # Thread-safe update of global state for Q CLI tools to access
    vim_state.update_context(context)
    vim_state.set_connected(True)  # Mark connection as active for health checks
    logger.info(
        f"Context updated: {params.get('filename', '')}:{params.get('line', 0)}"
    )


def _handle_annotations_response(data: dict, vim_state: Any) -> None:
    """Handle annotations_response messages from Vim."""
    annotations = data.get("params", {}).get("annotations", [])
    request_id = data.get("request_id")
    logger.info(
        f"Received {len(annotations)} annotations from Vim (request_id: {request_id})"
    )
    # Put response in the correct queue
    if request_id and request_id in vim_state.response_queues:
        vim_state.response_queues[request_id].put(("annotations", annotations))


def _handle_quickfix_response(data: dict, vim_state: Any) -> None:
    """Handle quickfix_entry_response messages from Vim."""
    params = data.get("params", {})
    request_id = data.get("request_id")
    logger.info(f"Received quickfix entry from Vim (request_id: {request_id})")
    # Put response in the correct queue
    if request_id and request_id in vim_state.response_queues:
        vim_state.response_queues[request_id].put(("quickfix_entry", params))
