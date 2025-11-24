"""
Thread-safe state management for Vim editor connection and context.

Manages shared state between MCP server thread and socket listener threads.
Uses a single lock (_lock) to protect current_context and vim_connected flag.
"""

import threading
import queue
from typing import Optional, Dict, Any


class VimState:
    """Thread-safe state manager for Vim editor connection and context.

    Thread-safe methods (use lock):
    - update_context(): Updates editor context from Vim
    - get_context(): Returns copy of current context
    - set_connected()/is_connected(): Manages connection state

    Thread-safe without lock (queue.Queue is thread-safe):
    - request_queue: Outgoing requests to Vim
    - response_queues: Incoming responses keyed by request_id
    """

    def __init__(self):
        self._lock = threading.Lock()
        self.socket_server: Optional[Any] = None
        self.vim_channel: Optional[Any] = None
        self.vim_connected = False
        self.request_queue: queue.Queue = queue.Queue()
        self.response_queues: Dict[str, queue.Queue] = {}
        self.current_context: Dict[str, Any] = {
            "context": "No context available",
            "filename": "",
            "line": 0,
            "visual_start": 0,
            "visual_end": 0,
            "visual_start_col": 0,
            "visual_end_col": 0,
            "visual_start_line_len": 0,
            "visual_end_line_len": 0,
            "total_lines": 0,
            "modified": False,
            "encoding": "",
            "line_endings": "",
        }

    def update_context(self, context: Dict[str, Any]) -> None:
        """Update the current editor context thread-safely."""
        with self._lock:
            self.current_context = context

    def get_context(self) -> Dict[str, Any]:
        """Get a copy of the current context thread-safely."""
        with self._lock:
            return self.current_context.copy()

    def set_connected(self, connected: bool) -> None:
        """Set the connection state thread-safely."""
        with self._lock:
            self.vim_connected = connected

    def is_connected(self) -> bool:
        """Check if Vim is connected thread-safely."""
        with self._lock:
            return self.vim_connected
