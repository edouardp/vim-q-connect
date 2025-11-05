import os
import socket
import json
import threading
import logging
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
                        except Exception as e:
                            logger.error(f"Error receiving from Vim: {e}")
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
    global vim_channel
    
    if not vim_channel:
        return "Vim not connected to MCP socket"
    
    try:
        command = {
            "method": "goto_line",
            "params": {
                "line": line_number,
                "filename": filename
            }
        }
        
        logger.info(f"Sending goto_line command: {command}")
        # Send as raw JSON string with newline delimiter
        message = json.dumps(command) + '\n'
        vim_channel.send(message.encode())
        logger.info(f"Command sent successfully")
        return f"Navigation command sent: line {line_number}" + (f" in {filename}" if filename else "")
    except Exception as e:
        logger.error(f"Error sending navigation command: {e}")
        return f"Error sending navigation command: {e}"

@mcp.tool()
def add_virtual_text(line: int, text: str, highlight: str = "Comment", emoji: str = "") -> str:
    """Add virtual text above the specified line
    
    Args:
        line: Line number to add virtual text above (1-indexed)
        text: Text content to display. Use actual newlines (not \\n) for multi-line text
        highlight: Vim highlight group (default: "Comment")
        emoji: Optional emoji for the first line (default: uses Ｑ). Use sparingly - only when it adds semantic meaning.
    
    Example:
        Single line: add_virtual_text(10, "This is a comment")
        Multi-line: add_virtual_text(10, "Line 1\nLine 2\nLine 3")
        With emoji: add_virtual_text(10, "Debug info", emoji="🐛")
        
    Common working emoji: 🤖🔥⭐💡✅❌📝🚀🎯🔧⚡🎉📊🔍💻📱🌟🎨🏆🔒🔑📈📉🎵
    Note: Warning sign ⚠️ may not render properly in some Vim environments. Don't use
    """
    global vim_channel
    
    if not vim_channel:
        return "Vim not connected to MCP socket"
    
    try:
        command = {
            "method": "add_virtual_text",
            "params": {
                "line": line,
                "text": text,
                "highlight": highlight,
                "emoji": emoji
            }
        }
        
        logger.info(f"Sending add_virtual_text command: {command}")
        message = json.dumps(command) + '\n'
        vim_channel.send(message.encode())
        logger.info(f"Virtual text command sent successfully")
        return f"Virtual text added above line {line}: {text}"
    except Exception as e:
        logger.error(f"Error sending virtual text command: {e}")
        return f"Error sending virtual text command: {e}"

@mcp.tool()
def add_virtual_text_batch(entries: list[dict]) -> str:
    """Add multiple virtual text entries efficiently
    
    Args:
        entries: List of dicts with keys: line_number OR line, text, highlight (optional), emoji (optional)
    
    Example:
        add_virtual_text_batch([
            {"line_number": 10, "text": "Comment 1", "emoji": "📝"},
            {"line": "def my_function():", "text": "Line 1\nLine 2", "highlight": "WarningMsg"}
        ])

    If you are sending the optional emoji field, don't send the same emoji on the first line of the text.

    Use sparingly optional emoji sparingly - only when it adds semantic meaning.
    """
    global vim_channel
    
    if not vim_channel:
        return "Vim not connected to MCP socket"
    
    try:
        command = {
            "method": "add_virtual_text_batch",
            "params": {"entries": entries}
        }
        
        logger.info(f"Sending batch virtual text command: {len(entries)} entries")
        message = json.dumps(command) + '\n'
        vim_channel.send(message.encode())
        return f"Batch virtual text added: {len(entries)} entries"
    except Exception as e:
        logger.error(f"Error sending batch virtual text command: {e}")
        return f"Error sending batch virtual text command: {e}"

if __name__ == "__main__":
    mcp.run()
