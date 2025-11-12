#!/usr/bin/env python3
"""
Test file to demonstrate the new emoji handling behavior in vim-q-connect.

This file shows how annotations work with different emoji configurations:
1. Emoji only in text field (extracted and consumed)
2. Emoji in both emoji field and text field (emoji field takes precedence, text emoji consumed)
3. Emoji only in emoji field (used as-is)
4. No emoji (defaults to Ｑ)
"""

def function_with_security_issue():
    """This function has a security vulnerability."""
    password = "hardcoded_password"  # 🔒 This should be extracted from text
    return password

def function_with_performance_issue():
    """This function has performance problems."""
    result = []
    for i in range(1000):  # This line will get emoji from field, text emoji consumed
        result.append(i * 2)
    return result

def function_with_quality_issue():
    """This function has code quality issues."""
    x = 1  # This will use emoji field only
    y = 2
    return x + y

def function_with_no_emoji():
    """This function will get default emoji."""
    return "hello world"  # This will use default Ｑ emoji

if __name__ == "__main__":
    print("Test file for emoji behavior demonstration")
