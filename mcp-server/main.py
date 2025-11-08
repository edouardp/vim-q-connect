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
import sys
import socket
import json
import threading
import logging
import queue
import uuid
import signal
from pathlib import Path
from fastmcp import FastMCP

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger("vim-context")

mcp = FastMCP("vim-context")

@mcp.prompt()
def review(target: str = None):
    """Review the code for quality, security, and best practices"""
    
    target_str = "the entire codebase (current repository or folder)"
    multifiles = True
    
    if target is None and vim_state.is_connected():
        context = vim_state.get_context()
        target_str = context["filename"]
        multifiles = False

    prompt = f"Please review {target_str} for issues."

    if multifiles:
        prompt += f"\n\nFor each code file in {target_str}:"
    else:
        prompt += f"\n\nFor the file {target_str}:"
        
    prompt += """
1. Check for security vulnerabilities
2. Check for code quality issues
3. Check for performance problems
4. Check for best practice violations

Use the add_to_quickfix tool to add each issue with:
- The exact line of code (use 'line' parameter, not 'line_number')
- A multi-line description:
  - First line: Brief issue description with emoji
  - Second line: Explanation of why it's a problem
  - Third line: Specific fix instructions
- Appropriate type ('E' for errors, 'W' for warnings, 'I' for info)

Examples of good quickfix entries:
- "🔒 SECURITY: Hardcoded password detected\nPasswords in source code can be exposed in version control\nMove to environment variables or secure configuration"
- "🚀 PERFORMANCE: Database query in loop\nExecuting queries in loops causes N+1 performance issues\nMove query outside loop or use batch operations"
- "🧹 QUALITY: Missing error handling\nUnhandled exceptions can crash the application\nAdd try-catch blocks with appropriate error responses"

The user will navigate through issues using :cnext/:cprev in Vim and can use the fix_current_issue prompt to fix individual issues."""

    return prompt



@mcp.prompt()
def explain():
    """Explain what the current code does
    
    Provides a clear explanation of the code at the current cursor position,
    including its purpose, how it works, and any important details.
    """
    return """Please explain the code I'm currently looking at in my editor.

Provide:
1. What the code does (high-level purpose)
2. How it works (step-by-step explanation)
3. Any important details or edge cases
4. Potential issues or improvements

Use the get_editor_context tool to see what code I'm looking at."""


@mcp.prompt()
def fix(target: str = None):
    """Fix issues in code or the current quickfix issue"""
    
    if target is None:
        # Check if there's a current quickfix issue
        if vim_state.is_connected():
            try:
                # Create unique request ID and response queue
                request_id = str(uuid.uuid4())
                response_queue = queue.Queue()
                vim_state.response_queues[request_id] = response_queue
                
                # Put request in queue for server thread to send
                vim_state.request_queue.put(('get_current_quickfix', {
                    "method": "get_current_quickfix",
                    "request_id": request_id,
                    "params": {}
                }))
                
                # Wait for response
                try:
                    response_type, data = response_queue.get(timeout=2.0)
                    if response_type == 'quickfix_entry' and 'error' not in data and 'text' in data:
                        # We have a valid quickfix entry
                        issue_text = data.get('text', '').split('\n')[0]  # First line only
                        return f"""Please fix the current quickfix issue: {issue_text}

The issue is at {data.get('filename', 'unknown file')}:{data.get('line_number', 0)}

Steps:
1. Read the file and understand the context around the issue
2. Apply the appropriate fix to resolve this specific issue
3. Explain what you changed and why

Make sure the fix:
- Addresses the root cause, not just the symptom
- Follows best practices and coding standards
- Doesn't introduce new issues
- Is minimal and focused"""
                finally:
                    # Clean up response queue
                    if request_id in vim_state.response_queues:
                        del vim_state.response_queues[request_id]
            except:
                pass  # Fall through to editor context
        
        # No quickfix entry or error - use current editor context
        return """Please fix the code I'm currently looking at.

Steps:
1. Use get_editor_context to see what code I'm currently viewing
2. Identify any issues that need fixing
3. Apply appropriate fixes to resolve the issues
4. Explain what you changed and why

Make sure the fix:
- Addresses the root cause, not just the symptom
- Follows best practices and coding standards
- Doesn't introduce new issues
- Is minimal and focused"""
    
    return f"""Please fix issues in {target}.

Use get_editor_context if you need to see the current code context.

Steps:
1. Identify the issues that need fixing in {target}
2. Apply appropriate fixes to resolve each issue
3. Explain what you changed and why

Make sure each fix:
- Addresses the root cause, not just the symptom
- Follows best practices and coding standards
- Doesn't introduce new issues
- Is minimal and focused"""

@mcp.prompt()
def add_documentation():
    """Add documentation to the current code
    
    Adds appropriate documentation (docstrings, comments) to the code
    at the current cursor position.
    """
    return """Please add documentation to the code I'm currently looking at.

Use the get_editor_context tool to see what code needs documentation.

Add:
1. Docstrings for functions/classes (following language conventions)
2. Inline comments for complex logic
3. Type hints (if applicable)
4. Usage examples (if helpful)

Make the documentation:
- Clear and concise
- Focused on "why" not just "what"
- Helpful for future maintainers"""



class VimState:
    """Thread-safe state manager for Vim editor connection and context.
    
    Manages shared state between MCP server thread and socket listener threads.
    Uses a single lock (_lock) to protect current_context and vim_connected flag.
    
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
        self.socket_server = None
        self.vim_channel = None
        self.vim_connected = False
        self.request_queue = queue.Queue()
        self.response_queues = {}
        self.current_context = {
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
    
    def update_context(self, context):
        with self._lock:
            self.current_context = context
    
    def get_context(self):
        with self._lock:
            return self.current_context.copy()
    
    def set_connected(self, connected):
        with self._lock:
            self.vim_connected = connected
    
    def is_connected(self):
        with self._lock:
            return self.vim_connected

vim_state = VimState()

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
    
    try:
        data = json.loads(message)
        if data.get('method') == 'context_update':
            params = data['params']
            context = {
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
            vim_state.update_context(context)
            vim_state.set_connected(True)
            logger.info(f"Context updated: {params.get('filename', '')}:{params.get('line', 0)}")
        elif data.get('method') == 'disconnect':
            vim_state.set_connected(False)
            logger.info("Vim explicitly disconnected")
        elif data.get('method') == 'annotations_response':
            annotations = data.get('params', {}).get('annotations', [])
            request_id = data.get('request_id')
            logger.info(f"Received {len(annotations)} annotations from Vim (request_id: {request_id})")
            # Put response in the correct queue
            if request_id and request_id in vim_state.response_queues:
                vim_state.response_queues[request_id].put(('annotations', annotations))
        elif data.get('method') == 'quickfix_entry_response':
            params = data.get('params', {})
            request_id = data.get('request_id')
            logger.info(f"Received quickfix entry from Vim (request_id: {request_id})")
            # Put response in the correct queue
            if request_id and request_id in vim_state.response_queues:
                vim_state.response_queues[request_id].put(('quickfix_entry', params))
    except Exception as e:
        logger.error(f"Error handling Vim message: {e}")

def start_socket_server():
    
    socket_dir = os.environ.get('SOCKET_DIR', '.')
    socket_path = os.path.join(socket_dir, '.vim-q-mcp.sock')
    
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
    
    def accept_connections():
        while True:
            try:
                conn, addr = vim_state.socket_server.accept()
                vim_state.vim_channel = conn
                vim_state.set_connected(True)
                logger.info("Vim connected to MCP socket")
                
                # Listen for messages from Vim
                def listen_to_vim():
                    buffer = ""
                    while True:
                        try:
                            # Check for outgoing requests first
                            try:
                                request_type, request_data = vim_state.request_queue.get_nowait()
                                message = json.dumps(request_data) + '\n'
                                conn.send(message.encode())
                                logger.info(f"Sent {request_type} request to Vim")
                            except queue.Empty:
                                pass
                            
                            # Then check for incoming data
                            conn.settimeout(0.1)  # Non-blocking with short timeout
                            try:
                                data = conn.recv(65536).decode('utf-8', errors='replace')
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
                            vim_state.set_connected(False)
                            break
                
                threading.Thread(target=listen_to_vim, daemon=True).start()
                
            except Exception as e:
                logger.error(f"Error accepting connection: {e}")
                break
    
    threading.Thread(target=accept_connections, daemon=True).start()


@mcp.tool()
def get_editor_context() -> dict:
    """Get the current editor context from Vim via channel. Use this tool whenever the user refers to code they are looking at in their editor, such as: "what is this", "explain this function", "how does this work", "what's wrong with this code", "optimize this", "add tests for this", "refactor this", "this file", "the current file", "this code", "the code I'm looking at", "can you help me with this", "review this", or any reference to current editor content."""
    
    if not vim_state.is_connected():
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
    
    context = vim_state.get_context()
    return {
        "content": context["context"],
        "filename": context["filename"],
        "current_line": context["line"],
        "visual_selection": {
            "start_line": context["visual_start"],
            "end_line": context["visual_end"]
        } if context["visual_start"] > 0 else None,
        "total_lines": context["total_lines"],
        "modified": context["modified"],
        "encoding": context["encoding"],
        "line_endings": context["line_endings"]
    }

@mcp.tool()
def goto_line(line_number: int, filename: str = "") -> str:
    """Navigate to a specific line in Vim."""
    
    if not vim_state.is_connected():
        return "Vim not connected to MCP socket"
    
    try:
        vim_state.request_queue.put(('goto_line', {
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
            - text (str): The annotation text to display (supports multi-line with \n). If text starts with emoji, it will be extracted as the display emoji.
            - highlight (str, optional): Vim highlight group (ignored for now - will always uses qtext styling)
            - emoji (str, optional): Single emoji character for visual emphasis (defaults to Ｑ)
    
    Example:
        add_virtual_text_batch([
            {"line_number": 10, "text": "🔒 SECURITY: Validate input here", "highlight": "WarningMsg"},
            {"line": "def my_function():", "text": "PERFORMANCE: Consider caching this result\nThis function is called frequently", "emoji": "⚡"}
        ])

    Use optional emoji sparingly - only when it adds semantic meaning.

    Common working emoji: 🤖🔥⭐💡✅❌📝🚀🎯🔧⚡🎉📊🔍💻📱🌟🎨🏆🔒🔑📈📉🎵
    Note: Warning sign ⚠️ may not render properly in some Vim environments. Do not use.
    """
    
    if not vim_state.is_connected():
        return "Vim not connected to MCP socket"
    
    try:
        vim_state.request_queue.put(('add_virtual_text_batch', {
            "method": "add_virtual_text_batch",
            "params": {"entries": entries}
        }))
        
        return f"Batch virtual text added: {len(entries)} entries"
    except Exception as e:
        logger.error(f"Error sending batch virtual text command: {e}")
        return f"Error sending batch virtual text command: {e}"

@mcp.tool()
def add_to_quickfix(entries: list[dict]) -> str:
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
    
    Example:
        add_to_quickfix([
            {"line": "def process_data(input):", "text": "Missing input validation", "type": "E"},
            {"line_number": 45, "text": "Performance issue: O(n²) complexity", "type": "W"}
        ])
    """
    
    if not vim_state.is_connected():
        return "Vim not connected to MCP socket"
    
    try:
        vim_state.request_queue.put(('add_to_quickfix', {
            "method": "add_to_quickfix",
            "params": {"entries": entries}
        }))
        
        return f"Added {len(entries)} entries to quickfix list"
    except Exception as e:
        logger.error(f"Error sending quickfix command: {e}")
        return f"Error sending quickfix command: {e}"

@mcp.tool()
def get_current_quickfix_entry() -> dict:
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
        response_queue = queue.Queue()
        vim_state.response_queues[request_id] = response_queue
        
        # Put request in queue for server thread to send
        vim_state.request_queue.put(('get_current_quickfix', {
            "method": "get_current_quickfix",
            "request_id": request_id,
            "params": {}
        }))
        
        # Wait for response
        try:
            response_type, data = response_queue.get(timeout=5.0)
            if response_type == 'quickfix_entry':
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

@mcp.tool()
def get_annotations_above_current_position() -> str:
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
        response_queue = queue.Queue()
        vim_state.response_queues[request_id] = response_queue
        
        # Put request in queue for server thread to send
        vim_state.request_queue.put(('get_annotations', {
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
            del vim_state.response_queues[request_id]
            
    except Exception as e:
        logger.error(f"Error requesting annotations: {e}")
        return f"Error requesting annotations: {e}"

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
    
    start_socket_server()
    mcp.run()
