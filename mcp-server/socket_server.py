"""
Unix domain socket server for Vim communication.

Manages socket lifecycle and bidirectional message handling with Vim.
"""

import os
import socket
import json
import threading
import logging
import hashlib
from pathlib import Path
from typing import Any

from message_handler import handle_vim_message

logger = logging.getLogger("vim-context")


def get_socket_path() -> str:
    """Get socket path, using hashed directory structure for long paths."""
    cwd_hash = hashlib.sha256(
        os.environ.get("SOCKET_DIR", os.getcwd()).encode()
    ).hexdigest()
    socket_dir = Path(f"/tmp/vim-q-connect/{cwd_hash}")
    socket_dir.mkdir(parents=True, exist_ok=True)
    return str(socket_dir / "sock")


def start_socket_server(vim_state: Any) -> None:
    """Start Unix domain socket server for Vim communication."""
    socket_path = get_socket_path()
    logger.info(f"Creating MCP socket at: {socket_path}")

    # Remove existing socket
    try:
        os.unlink(socket_path)
    except FileNotFoundError:
        pass

    vim_state.socket_server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    vim_state.socket_server.bind(socket_path)
    os.chmod(socket_path, 0o600)
    vim_state.socket_server.listen(1)

    def accept_connections() -> None:
        while True:
            try:
                conn, addr = vim_state.socket_server.accept()
                vim_state.vim_channel = conn
                vim_state.set_connected(True)
                logger.info("Vim connected to MCP socket")

                # Listen for messages from Vim
                threading.Thread(
                    target=_listen_to_vim, args=(conn, vim_state), daemon=True
                ).start()

            except Exception as e:
                logger.error(f"Error accepting connection: {e}")
                break

    threading.Thread(target=accept_connections, daemon=True).start()


def _listen_to_vim(conn: socket.socket, vim_state: Any) -> None:
    """Listen for messages from Vim and handle outgoing requests."""
    import queue

    buffer = ""
    while True:
        try:
            # Check for outgoing requests first
            try:
                request_type, request_data = vim_state.request_queue.get_nowait()
                message = json.dumps(request_data) + "\n"
                conn.send(message.encode())
                logger.info(f"Sent {request_type} request to Vim")
            except queue.Empty:
                pass

            # Then check for incoming data
            conn.settimeout(0.1)  # Non-blocking with short timeout
            try:
                data = conn.recv(65536).decode("utf-8", errors="replace")
                if not data:
                    vim_state.set_connected(False)
                    logger.info("Vim disconnected from MCP socket")
                    break

                buffer += data
                logger.info(f"Received data from Vim: {data}")

                # Handle complete messages
                while buffer:
                    try:
                        # Try to parse as complete JSON
                        message = json.loads(buffer)
                        handle_vim_message(json.dumps(message), vim_state)
                        buffer = ""
                        break
                    except json.JSONDecodeError:
                        # Look for newline-delimited messages
                        if "\n" in buffer:
                            line, buffer = buffer.split("\n", 1)
                            if line.strip():
                                handle_vim_message(line.strip(), vim_state)
                        else:
                            break
            except socket.timeout:
                pass  # Continue loop to check request queue

        except Exception as e:
            logger.error(f"Error in Vim communication: {e}")
            vim_state.set_connected(False)
            break
