#!/usr/bin/env python3
"""
Test file for vim-q-connect highlighting functionality
"""

def example_function():
    """This is an example function that can be highlighted"""
    print("Hello, world!")
    return True

def another_function():
    """Another function for testing multi-line highlights"""
    x = 1
    y = 2
    z = x + y
    return z

# This is a comment that could be highlighted
important_variable = "This line could have a highlight with hover text"

class ExampleClass:
    """Example class for testing"""
    
    def __init__(self):
        self.value = 42
    
    def method(self):
        """A method that could be highlighted"""
        return self.value * 2

if __name__ == "__main__":
    func = example_function()
    obj = ExampleClass()
    result = obj.method()
    print(f"Result: {result}")
