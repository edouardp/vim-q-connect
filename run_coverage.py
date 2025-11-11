#!/usr/bin/env python3
"""
Fake coverage script for vim-q-connect demo
Generates realistic coverage data for main.py functions
"""

import json

def main():
    print("Running coverage analysis...")
    print("Analyzing main.py...")
    print("Processing 847 lines of code...")
    print("Found 15 functions and 3 classes...")
    print("")
    
    # Function coverage data
    functions = [
        {"name": "review", "lines_covered": 42, "lines_total": 45, "branches_covered": 8, "branches_total": 12},
        {"name": "explain", "lines_covered": 38, "lines_total": 41, "branches_covered": 6, "branches_total": 8},
        {"name": "fix", "lines_covered": 28, "lines_total": 35, "branches_covered": 4, "branches_total": 9},
        {"name": "doc", "lines_covered": 31, "lines_total": 33, "branches_covered": 5, "branches_total": 6},
        {"name": "handle_vim_message", "lines_covered": 45, "lines_total": 52, "branches_covered": 12, "branches_total": 15},
        {"name": "start_socket_server", "lines_covered": 67, "lines_total": 78, "branches_covered": 18, "branches_total": 22},
        {"name": "get_editor_context", "lines_covered": 18, "lines_total": 18, "branches_covered": 3, "branches_total": 3},
        {"name": "goto_line", "lines_covered": 12, "lines_total": 15, "branches_covered": 2, "branches_total": 4},
        {"name": "add_virtual_text", "lines_covered": 22, "lines_total": 28, "branches_covered": 4, "branches_total": 6},
        {"name": "add_to_quickfix", "lines_covered": 15, "lines_total": 18, "branches_covered": 2, "branches_total": 4},
        {"name": "get_current_quickfix_entry", "lines_covered": 25, "lines_total": 32, "branches_covered": 6, "branches_total": 8},
        {"name": "clear_quickfix", "lines_covered": 8, "lines_total": 12, "branches_covered": 1, "branches_total": 3},
        {"name": "get_annotations_above_current_position", "lines_covered": 20, "lines_total": 28, "branches_covered": 4, "branches_total": 7},
        {"name": "clear_annotations", "lines_covered": 10, "lines_total": 15, "branches_covered": 2, "branches_total": 4},
        {"name": "cleanup_and_exit", "lines_covered": 0, "lines_total": 12, "branches_covered": 0, "branches_total": 4}
    ]
    
    for func in functions:
        line_pct = (func["lines_covered"] / func["lines_total"]) * 100
        branch_pct = (func["branches_covered"] / func["branches_total"]) * 100
        print(f"  {func['name']:<35} {func['lines_covered']:>3}/{func['lines_total']:<3} ({line_pct:>5.1f}%)  {func['branches_covered']:>2}/{func['branches_total']:<2} ({branch_pct:>5.1f}%)")
    
    print("")
    print("Class coverage:")
    print("  VimState                          45/48  (93.8%)   12/14 (85.7%)")
    print("")
    
    # Calculate totals
    total_lines_covered = sum(f["lines_covered"] for f in functions) + 45
    total_lines = sum(f["lines_total"] for f in functions) + 48
    total_branches_covered = sum(f["branches_covered"] for f in functions) + 12
    total_branches = sum(f["branches_total"] for f in functions) + 14
    
    total_line_pct = (total_lines_covered / total_lines) * 100
    total_branch_pct = (total_branches_covered / total_branches) * 100
    
    print(f"TOTAL                               {total_lines_covered}/{total_lines} ({total_line_pct:.1f}%)  {total_branches_covered}/{total_branches} ({total_branch_pct:.1f}%)")
    print("")
    print("Coverage report written to coverage.json")

if __name__ == "__main__":
    main()
