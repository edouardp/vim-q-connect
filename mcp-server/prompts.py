"""
MCP prompt implementations for code review, explanation, fixing, and documentation.
"""

import uuid
import queue
import logging
from typing import Any, Optional

logger = logging.getLogger("vim-context")


def review_prompt(vim_state: Any, target: Optional[str] = None) -> str:
    """Review the code for quality, security, and best practices"""

    try:
        prompt = ""

        if vim_state.is_connected():
            context = vim_state.get_context()
            prompt += f"Current context:\n"
            prompt += f"File: {context['filename']}\n"
            prompt += f"Line: {context['line']}\n"

            if context.get("visual_start", 0) > 0:
                prompt += f"Selection: lines {context['visual_start']}-{context['visual_end']}\n"

        prompt += f"Please review the code for issues."
        if target is not None:
            prompt += (
                f"The user has specifically asked for this to be reviewed: {target}"
            )
        elif vim_state.is_connected():
            prompt += "Use the context above to determine what should be reviewed. If they have a current selection, that is the most important thing."

        prompt += f"\n\nFor the code they have asked for a review for:"

        prompt += """
1. Check for security vulnerabilities
2. Check for code quality issues
3. Check for performance problems
4. Check for best practice violations

Use the add_to_quickfix tool to add each issue with:
- The exact line of code (use 'line' parameter, and add a 'line_number_hint' of the lint number that line is found on)
- A multi-line description:
  - First line: Brief issue description with emoji
  - Second line: Explanation of why it's a problem
  - Third line: Specific fix instructions
- Appropriate type ('E' for errors, 'W' for warnings, 'I' for info)

Examples of good quickfix entries:
- "🔒 SECURITY: Hardcoded password detected\nPasswords in source code can be exposed in version control\nMove to environment variables or secure configuration"
- "🚀 PERFORMANCE: Database query in loop\nExecuting queries in loops causes N+1 performance issues\nMove query outside loop or use batch operations"
- "🧹 QUALITY: Missing error handling\nUnhandled exceptions can crash the application\nAdd try-catch blocks with appropriate error responses"

The user will navigate through issues using :cnext/:cprev in Vim and can use the @fix prompt to fix individual issues."""

        return prompt

    except Exception as e:
        import traceback

        error_details = f"ERROR in review prompt:\n"
        error_details += f"Exception type: {type(e).__name__}\n"
        error_details += f"Exception message: {str(e)}\n"
        error_details += f"Traceback:\n{traceback.format_exc()}\n"
        error_details += f"Function arguments: target={target}\n"
        if vim_state.is_connected():
            error_details += f"Vim connected: True\n"
        return error_details


def explain_prompt(vim_state: Any, target: Optional[str] = None) -> str:
    """Explain what the current code does by adding detailed annotations

    Provides comprehensive explanations as inline annotations using add_virtual_text,
    with overview and detailed technical explanations for senior developers.
    """
    try:
        prompt = ""

        if vim_state.is_connected():
            context = vim_state.get_context()
            prompt += f"Current context (from get_editor_context tool, only call the tool if you require additional context):\n"
            prompt += f"File: {context['filename']}\n"
            prompt += f"Line: {context['line']}\n"

            if context.get("visual_start", 0) > 0:
                prompt += f"Selection: lines {context['visual_start']}-{context['visual_end']}\n\n"

        prompt += f"Please explain the code by adding detailed annotations directly to the editor."
        if target is not None:
            prompt += f" The user has specifically asked about: {target}"
        elif vim_state.is_connected():
            prompt += " Use the context above to determine what should be explained. If they have a current selection, that is the most important thing."

        prompt += """

Steps:
1. Analyse the code. If understanding it properly requires examining other code, then find and understand that code too.
2. Use add_virtual_text to add comprehensive annotations explaining the code

"""

        # Only add the instruction if we have context from vim_state
        if vim_state.is_connected():
            prompt += "IMPORTANT: Do not call get_editor_context - the context provided above is current and up-to-date.\n\n"

        prompt += """Annotation Guidelines:
- Start with an OVERVIEW annotation using ℹ️ emoji for cases where there is a
  function/method/class etc, or a section being explained
- Add detailed annotations using 💬 emoji for each significant line or block
- Make annotations detailed and suitable for senior developers
- Include technical context, design rationale, and implementation details
- Use blocks of text to provide comprehensive explanations if required,
  but a single line if that is all that is required
- Focus on "why" decisions were made, not just "what" the code does
- Always include the verbatum line as the "line" parameter
- Always include filename and line_number_hint parameters for better annotation placement

Example annotation structure:
- ℹ️ OVERVIEW: High-level purpose and architectural context
- 💬 TECHNICAL DETAIL: Specific implementation choices and trade-offs
- 💬 DESIGN RATIONALE: Why this approach was chosen
- 💬 EDGE CASES: Important considerations and potential issues

Make the explanations comprehensive enough that a senior developer could understand:
- The purpose and context of the code
- Key design decisions and trade-offs
- Implementation details and technical considerations
- Potential issues, edge cases, or areas for improvement"""

        return prompt

    except Exception as e:
        import traceback

        error_details = f"ERROR in explain prompt:\n"
        error_details += f"Exception type: {type(e).__name__}\n"
        error_details += f"Exception message: {str(e)}\n"
        error_details += f"Traceback:\n{traceback.format_exc()}\n"
        error_details += f"Function arguments: target={target}\n"
        if vim_state.is_connected():
            error_details += f"Vim connected: True\n"
        return error_details


def fix_prompt(vim_state: Any, target: Optional[str] = None) -> str:
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
                    response_type, data = response_queue.get(timeout=2.0)
                    if (
                        response_type == "quickfix_entry"
                        and "error" not in data
                        and "text" in data
                    ):
                        # We have a valid quickfix entry
                        issue_text = data.get("text", "").split("\n")[
                            0
                        ]  # First line only
                        return f"""Please fix the current quickfix issue: {issue_text}

The issue is at {data.get("filename", "unknown file")}:{data.get("line_number", 0)}

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

    try:
        prompt = ""

        if vim_state.is_connected():
            context = vim_state.get_context()
            prompt += f"Current context (from get_editor_context tool, only call the tool if you require additional context):\n"
            prompt += f"File: {context['filename']}\n"
            prompt += f"Line: {context['line']}\n"

            if context.get("visual_start", 0) > 0:
                prompt += f"Selection: lines {context['visual_start']}-{context['visual_end']}\n\n"

        prompt += f"Please fix the code."
        if target is not None:
            prompt += f" The user has specifically asked: {target}"
        elif vim_state.is_connected():
            prompt += " Use the context above to determine what should be fixed. If there is a current selection, that is the most important thing."

        prompt += """

Steps:
1. Identify the issues that need fixing
2. Apply appropriate fixes to resolve each issue
3. Explain what you changed and why

"""

        if vim_state.is_connected():
            prompt += "IMPORTANT: Do not call get_editor_context - the context provided above is current and up-to-date.\n\n"

        prompt += """Make sure each fix:
- Addresses the root cause, not just the symptom
- Follows best practices and coding standards
- Doesn't introduce new issues
- Is minimal and focused"""

        return prompt

    except Exception as e:
        import traceback

        error_details = f"ERROR in fix prompt:\n"
        error_details += f"Exception type: {type(e).__name__}\n"
        error_details += f"Exception message: {str(e)}\n"
        error_details += f"Traceback:\n{traceback.format_exc()}\n"
        return error_details


def doc_prompt(vim_state: Any, target: Optional[str] = None) -> str:
    """Add documentation to the current code

    Adds appropriate documentation (docstrings, comments) to the code
    """
    try:
        prompt = ""

        if vim_state.is_connected():
            context = vim_state.get_context()
            prompt += f"Current context:\n"
            prompt += f"File: {context['filename']}\n"
            prompt += f"Line: {context['line']}\n"

            if context.get("visual_start", 0) > 0:
                prompt += f"Selection: lines {context['visual_start']}-{context['visual_end']}\n"

        prompt += f"Please add documentation to the code."
        if target is not None:
            prompt += f" The user has specifically asked to document: {target}"
        elif vim_state.is_connected():
            prompt += " Use the context above to determine what should be documented. If there is a current selection, that is the most important thing."

        prompt += """

Add:
1. Docstrings for functions/classes (following language conventions)
2. Inline comments for complex logic
3. Type hints (if applicable)
4. Usage examples (if helpful)

Make the documentation:
- Clear and concise
- Focused on "why" not just "what"
- Helpful for future maintainers

Make sure to understand what the code does, and if other parts of the codebase
will assist with that, read and understand them as well.
"""

        return prompt

    except Exception as e:
        import traceback

        error_details = f"ERROR in doc prompt:\n"
        error_details += f"Exception type: {type(e).__name__}\n"
        error_details += f"Exception message: {str(e)}\n"
        error_details += f"Traceback:\n{traceback.format_exc()}\n"
        error_details += f"Function arguments: target={target}\n"
        if vim_state.is_connected():
            error_details += f"Vim connected: True\n"
        return error_details
