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


def _validate_vim_message(data: Any) -> bool:
    """
    Validate incoming message structure from Vim.

    Expected structure:
    {
        "method": str,
        "params": dict (optional),
        "request_id": str (optional)
    }

    Args:
        data: Parsed JSON data to validate

    Returns:
        True if message is valid, False otherwise
    """
    # Must be a dictionary
    if not isinstance(data, dict):
        logger.warning(f"Message is not a dict: {type(data)}")
        return False

    # Must have a 'method' field that is a string
    method = data.get("method")
    if not isinstance(method, str):
        logger.warning(f"Message has invalid or missing method field: {method}")
        return False

    # If 'params' exists, it must be a dict
    if "params" in data and not isinstance(data["params"], dict):
        logger.warning(f"Message params is not a dict: {type(data.get('params'))}")
        return False

    # If 'request_id' exists, it must be a string
    if "request_id" in data and not isinstance(data["request_id"], str):
        logger.warning(
            f"Message request_id is not a string: {type(data.get('request_id'))}"
        )
        return False

    return True


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
                conn.send(message.encode("utf-8"))
                logger.info(f"Sent {request_type} request to Vim")
            except queue.Empty:
                pass

            # Then check for incoming data
            conn.settimeout(0.1)  # Non-blocking with short timeout
            try:
                raw_data = conn.recv(65536)
                if not raw_data:
                    vim_state.set_connected(False)
                    logger.info("Vim disconnected from MCP socket")
                    break

                # Strict UTF-8 decoding - reject malformed sequences
                try:
                    data = raw_data.decode("utf-8")
                except UnicodeDecodeError as e:
                    logger.error(f"Received malformed UTF-8 data, rejecting: {e}")
                    continue

                buffer += data
                logger.info(f"Received data from Vim: {data}")

                # Handle complete newline-delimited JSON messages
                # Protocol: each message ends with \n
                while "\n" in buffer:
                    line, buffer = buffer.split("\n", 1)
                    if not line.strip():
                        # Skip empty lines
                        continue

                    try:
                        message = json.loads(line.strip())
                        # Validate message structure before processing
                        if _validate_vim_message(message):
                            handle_vim_message(line.strip(), vim_state)
                        else:
                            logger.warning(
                                f"Received invalid message structure: {message}"
                            )
                    except json.JSONDecodeError as e:
                        logger.warning(
                            f"Failed to parse JSON line: {line.strip()}, error: {e}"
                        )
            except socket.timeout:
                pass  # Continue loop to check request queue

        except Exception as e:
            logger.error(f"Error in Vim communication: {e}")
            vim_state.set_connected(False)
            break
