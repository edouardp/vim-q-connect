"""
MCP Server for vim-q-connect plugin

This server provides Model Context Protocol (MCP) integration between Vim and Q CLI.
It enables bidirectional communication for editor context sharing and remote control.

Key Features:
- Real-time editor context reception from vim-q-connect plugin
- Virtual text annotation support with goto_line navigation
- Unix domain socket communication for low-latency IPC
- Thread-safe message handling and client management

MCP Tools Provided:
- get_editor_context: Retrieve current Vim editor state and context
- goto_line: Navigate to specific line/file in Vim editor
- add_virtual_text: Add annotations and virtual text to editor

Usage:
    python main.py [socket_path]

The server listens on a Unix domain socket and handles JSON-RPC messages
from both the vim-q-connect plugin and Q CLI MCP client.
"""

import os
import socket
import json
import threading
import logging
import queue
import uuid
from pathlib import Path
from fastmcp import FastMCP

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger("vim-context")

mcp = FastMCP("vim-context")

# Global socket server and context storage
socket_server = None
vim_channel = None
vim_connected = False
request_queue = queue.Queue()
response_queues = {}  # request_id -> queue
current_context = {
    "context": "No context available",
    "filename": "",
    "line": 0,
    "visual_start": 0,
    "visual_end": 0,
    "total_lines": 0,
    "modified": False,
    "encoding": "",
    "line_endings": ""
}

def handle_vim_message(message):
    """
    Process incoming messages from vim-q-connect plugin.
    
    Handles two types of messages:
    - context_update: Updates the current editor context with file/cursor state
    - disconnect: Marks the Vim connection as disconnected
    - annotations_response: Returns annotations at current position
    
    Args:
        message: JSON string containing method and params
        
    Updates global state:
        current_context: Dictionary with editor state (filename, line, selection, etc.)
        vim_connected: Boolean flag indicating connection status
    """
    global current_context, vim_connected
    
    try:
        data = json.loads(message)
        if data.get('method') == 'context_update':
            params = data['params']
            current_context = {
                "context": params.get('context', 'No context available'),
                "filename": params.get('filename', ''),
                "line": params.get('line', 0),
                "visual_start": params.get('visual_start', 0),
                "visual_end": params.get('visual_end', 0),
                "total_lines": params.get('total_lines', 0),
                "modified": params.get('modified', False),
                "encoding": params.get('encoding', ''),
                "line_endings": params.get('line_endings', '')
            }
            vim_connected = True
            logger.info(f"Context updated: {params.get('filename', '')}:{params.get('line', 0)}")
        elif data.get('method') == 'disconnect':
            vim_connected = False
            logger.info("Vim explicitly disconnected")
        elif data.get('method') == 'annotations_response':
            annotations = data.get('params', {}).get('annotations', [])
            request_id = data.get('request_id')
            logger.info(f"Received {len(annotations)} annotations from Vim (request_id: {request_id})")
            # Put response in the correct queue
            if request_id and request_id in response_queues:
                response_queues[request_id].put(('annotations', annotations))
    except Exception as e:
        logger.error(f"Error handling Vim message: {e}")

def start_socket_server():
    global socket_server, vim_channel
    
    socket_dir = os.environ.get('SOCKET_DIR', '.')
    socket_path = os.path.join(socket_dir, '.vim-q-mcp.sock')
    
    logger.info(f"Creating MCP socket at: {socket_path}")
    
    # Remove existing socket
    if os.path.exists(socket_path):
        os.unlink(socket_path)
    
    socket_server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    socket_server.bind(socket_path)
    socket_server.listen(1)
    
    def accept_connections():
        global vim_channel, vim_connected
        while True:
            try:
                conn, addr = socket_server.accept()
                vim_channel = conn
                vim_connected = True
                logger.info("Vim connected to MCP socket")
                
                # Listen for messages from Vim
                def listen_to_vim():
                    global vim_connected
                    buffer = ""
                    while True:
                        try:
                            # Check for outgoing requests first
                            try:
                                request_type, request_data = request_queue.get_nowait()
                                message = json.dumps(request_data) + '\n'
                                conn.send(message.encode())
                                logger.info(f"Sent {request_type} request to Vim")
                            except queue.Empty:
                                pass
                            
                            # Then check for incoming data
                            conn.settimeout(0.1)  # Non-blocking with short timeout
                            try:
                                data = conn.recv(4096).decode()
                                if not data:
                                    vim_connected = False
                                    logger.info("Vim disconnected from MCP socket")
                                    break
                                
                                buffer += data
                                logger.info(f"Received data from Vim: {data}")
                                
                                # Handle complete messages
                                while buffer:
                                    try:
                                        # Try to parse as complete JSON
                                        message = json.loads(buffer)
                                        handle_vim_message(json.dumps(message))
                                        buffer = ""
                                        break
                                    except json.JSONDecodeError:
                                        # Look for newline-delimited messages
                                        if '\n' in buffer:
                                            line, buffer = buffer.split('\n', 1)
                                            if line.strip():
                                                handle_vim_message(line.strip())
                                        else:
                                            break
                            except socket.timeout:
                                pass  # Continue loop to check request queue
                                
                        except Exception as e:
                            logger.error(f"Error in Vim communication: {e}")
                            vim_connected = False
                            break
                
                threading.Thread(target=listen_to_vim, daemon=True).start()
                
            except Exception as e:
                logger.error(f"Error accepting connection: {e}")
                break
    
    threading.Thread(target=accept_connections, daemon=True).start()

# Start server on import
start_socket_server()

@mcp.tool()
def get_editor_context() -> dict:
    """Get the current editor context from Vim via channel. Use this tool whenever the user refers to code they are looking at in their editor, such as: "what is this", "explain this function", "how does this work", "what's wrong with this code", "optimize this", "add tests for this", "refactor this", "this file", "the current file", "this code", "the code I'm looking at", "can you help me with this", "review this", or any reference to current editor content."""
    global current_context, vim_connected
    
    if not vim_connected:
        return {
            "content": "Editor not connected - no context available",
            "filename": "",
            "current_line": 0,
            "visual_selection": None,
            "total_lines": 0,
            "modified": False,
            "encoding": "",
            "line_endings": ""
        }
    
    return {
        "content": current_context["context"],
        "filename": current_context["filename"],
        "current_line": current_context["line"],
        "visual_selection": {
            "start_line": current_context["visual_start"],
            "end_line": current_context["visual_end"]
        } if current_context["visual_start"] > 0 else None,
        "total_lines": current_context["total_lines"],
        "modified": current_context["modified"],
        "encoding": current_context["encoding"],
        "line_endings": current_context["line_endings"]
    }

@mcp.tool()
def goto_line(line_number: int, filename: str = "") -> str:
    """Navigate to a specific line in Vim."""
    global request_queue
    
    if not vim_connected:
        return "Vim not connected to MCP socket"
    
    try:
        request_queue.put(('goto_line', {
            "method": "goto_line",
            "params": {
                "line": line_number,
                "filename": filename
            }
        }))
        
        return f"Navigation command sent: line {line_number}" + (f" in {filename}" if filename else "")
    except Exception as e:
        logger.error(f"Error sending navigation command: {e}")
        return f"Error sending navigation command: {e}"

# @mcp.tool()
# def add_virtual_text(line: int, text: str, highlight: str = "Comment", emoji: str = "") -> str:
#     """Add virtual text above the specified line
#     
#     Args:
#         line: Line number to add virtual text above (1-indexed)
#         text: Text content to display. Use actual newlines (not \\n) for multi-line text
#         highlight: Vim highlight group (default: "Comment")
#         emoji: Optional emoji for the first line (default: uses Ｑ). Use sparingly - only when it adds semantic meaning.
#     
#     Example:
#         Single line: add_virtual_text(10, "This is a comment")
#         Multi-line: add_virtual_text(10, "Line 1\nLine 2\nLine 3")
#         With emoji: add_virtual_text(10, "Debug info", emoji="🐛")
#         
#     Common working emoji: 🤖🔥⭐💡✅❌📝🚀🎯🔧⚡🎉📊🔍💻📱🌟🎨🏆🔒🔑📈📉🎵
#     Note: Warning sign ⚠️ may not render properly in some Vim environments. Don't use
#     """
#     global vim_channel
#     
#     if not vim_channel:
#         return "Vim not connected to MCP socket"
#     
#     try:
#         command = {
#             "method": "add_virtual_text",
#             "params": {
#                 "line": line,
#                 "text": text,
#                 "highlight": highlight,
#                 "emoji": emoji
#             }
#         }
#         
#         logger.info(f"Sending add_virtual_text command: {command}")
#         message = json.dumps(command) + '\n'
#         vim_channel.send(message.encode())
#         logger.info(f"Virtual text command sent successfully")
#         return f"Virtual text added above line {line}: {text}"
#     except Exception as e:
#         logger.error(f"Error sending virtual text command: {e}")
#         return f"Error sending virtual text command: {e}"

@mcp.tool()
def add_virtual_text(entries: list[dict]) -> str:
    """Add multiple virtual text entries efficiently to annotate the user's file in their editor.
    
    Use this tool when you have analysis data that would be valuable as in-line annotations or virtual text in the user's editor. 
    
    Common use cases:
    - Code reviews: Add security findings, performance notes, best practice suggestions
    - Static analysis: Show type information, complexity metrics, potential bugs
    - Documentation: Add explanations, examples, or API usage notes
    - Debugging: Highlight problematic lines with explanations
    - Refactoring suggestions: Mark areas for improvement with specific recommendations
    - Test coverage: Show which lines need testing or have coverage gaps
    
    Trigger words from users that suggest using this tool:
    - "annotate", "add annotations", "mark up", "highlight issues"
    - "review this code", "analyze this", "check for problems"
    - "explain inline", "show me issues", "code quality check"
    - "security review", "performance analysis"
    
    Args:
        entries: List of dictionaries, each containing:
            - line (str): Exact text content of the line to search for. Use this line argument in preference to line_number because it's more robust - annotations stay correct even if line numbers shift due to edits.
            - line_number (int): Alternative to line. 1-indexed line number to add virtual text above. Don't use the line_number argument unless the line is absolutely known, e.g. from an immediately preceeding get_editor_context tool call.
            - text (str): The annotation text to display (supports multi-line with \n)
            - highlight (str, optional): Vim highlight group (ignored for now - will always uses qtext styling)
            - emoji (str, optional): Single emoji character for visual emphasis (defaults to Ｑ)
    
    Example:
        add_virtual_text_batch([
            {"line_number": 10, "text": "SECURITY: Validate input here", "highlight": "WarningMsg", "emoji": "🔒"},
            {"line": "def my_function():", "text": "PERFORMANCE: Consider caching this result\nThis function is called frequently", "highlight": "qtext"}
        ])

    If you are sending the optional emoji field, don't send the same emoji on the first line of the text.

    Use optional emoji sparingly - only when it adds semantic meaning.

    Common working emoji: 🤖🔥⭐💡✅❌📝🚀🎯🔧⚡🎉📊🔍💻📱🌟🎨🏆🔒🔑📈📉🎵
    Note: Warning sign ⚠️ may not render properly in some Vim environments. Do not use.
    """
    global vim_channel
    
    if not vim_connected:
        return "Vim not connected to MCP socket"
    
    try:
        request_queue.put(('add_virtual_text_batch', {
            "method": "add_virtual_text_batch",
            "params": {"entries": entries}
        }))
        
        return f"Batch virtual text added: {len(entries)} entries"
    except Exception as e:
        logger.error(f"Error sending batch virtual text command: {e}")
        return f"Error sending batch virtual text command: {e}"

@mcp.tool()
def get_annotations_above_current_position() -> str:
    """Get all text property annotations above the current cursor position.
    
    Returns all virtual text annotations (text props) that are displayed above
    the line where the cursor is currently positioned in Vim.
    
    Returns:
        JSON string containing list of annotations with their text content and metadata
    """
    global request_queue, response_queues
    
    if not vim_connected:
        return "Vim not connected to MCP socket"
    
    try:
        # Create unique request ID and response queue
        request_id = str(uuid.uuid4())
        response_queue = queue.Queue()
        response_queues[request_id] = response_queue
        
        # Put request in queue for server thread to send
        request_queue.put(('get_annotations', {
            "method": "get_annotations",
            "request_id": request_id,
            "params": {}
        }))
        
        # Wait for response
        try:
            response_type, annotations = response_queue.get(timeout=5.0)
            if response_type == 'annotations':
                return json.dumps(annotations)
            else:
                return f"Unexpected response type: {response_type}"
        except queue.Empty:
            return "Timeout waiting for annotations response"
        finally:
            # Clean up response queue
            del response_queues[request_id]
            
    except Exception as e:
        logger.error(f"Error requesting annotations: {e}")
        return f"Error requesting annotations: {e}"

if __name__ == "__main__":
    mcp.run()
