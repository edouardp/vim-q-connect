# Agent Instructions for vim-q-connect

This document provides specific instructions for AI agents (like Amazon Q) when working with vim-q-connect features.

## Coverage Annotation Rendering

When asked to annotate code with test coverage data, follow these precise formatting guidelines:

### Data Source
Read coverage data from `coverage.json` which contains:
- Function-level coverage percentages
- Line execution counts  
- Missing/covered lines data

### Annotation Format
Use `add_virtual_text` with this exact multi-line format:

```
emoji Coverage: │bar│ percentage text
execution info
```

**Format Components:**
- **emoji**: Coverage-based status indicator
- **"Coverage:"**: Literal text with colon and space
- **│**: Box drawing character (U+2502) as separators
- **bar**: 24-character fixed-width progress bar
- **percentage text**: Coverage percentage and fraction
- **execution info**: Second line with execution statistics

### Example Output
```
✅ Coverage: │████████████████████▌   │ 93.3% lines covered (42/45)
Function executed 15 times
```

### Progress Bar Construction
Create exactly 24-character bars using:
- **█** (U+2588): Full block for covered portions
- **▌** (U+258C): Half block for partial coverage  
- **spaces**: For uncovered portions

Calculate bar length: `int(percentage * 24 / 100)`

### Emoji Selection Rules
- **✅** 90% and above (excellent coverage)
- **⚠️** 70% and above (moderate coverage)
- **❌** Below 70% (poor/no coverage)

### Execution Information Format
Second line should use:
- Functions: `"Function executed X times"`
- Classes: `"Class instantiated X times"`
- Never executed: `"Function never executed"`

### Placement Guidelines
- Use `line_number_hint` for precise positioning
- Place annotations above function/class definitions
- Include exact line text in `line` parameter for robustness

### Complete Implementation Example

```python
add_virtual_text([
    {
        "line": "def process_data():",
        "line_number_hint": 42,
        "text": "✅ Coverage: │████████████████████▌   │ 93.3% lines covered (42/45)\nFunction executed 15 times"
    },
    {
        "line": "def cleanup_and_exit():",
        "line_number_hint": 867,
        "text": "❌ Coverage: │                        │ 0.0% lines covered (0/12)\nFunction never executed"
    }
])
```

### Processing Guidelines
- Process all functions/classes found in coverage data
- Create one annotation per function with both visualization and statistics
- Maintain consistent formatting across all annotations
- Use multi-line text with `\n` separator for execution info
