# vim-q-connect Video Demo Script

## What We'll Demonstrate

- **Connection Setup** - Establishing the MCP bridge between Vim and Q CLI
- **Context Awareness** - Q automatically knowing your cursor position and code
- **Navigation Control** - Q moving your cursor to specific functions and lines
- **Live Code Updates** - Q modifying code directly in Vim in real-time
- **Text Selection** - Working with selected code blocks and visual mode
- **Built-in Prompts** - Using @explain for detailed code breakdowns
- **Code Review** - Finding security and quality issues with visual annotations
- **Quickfix Integration** - Navigating through issues with Vim's quickfix list
- **Intelligent Fixing** - Q detecting and fixing current context issues
- **Coverage Analysis** - Annotating functions with test coverage data
- **Language Learning** - Understanding unfamiliar syntax (Rust example)
- **CloudFormation Documentation** - Auto-documenting infrastructure code with AWS docs

## Setup (Pre-recording)
- Terminal with Q CLI ready
- Vim with vim-q-connect installed
- Sample Python file with functions
- Sample Rust file with complex syntax
- Fake coverage.json file
- Clean quickfix list

## Scene 1: Introduction (30 seconds)
**Narrator**: "vim-q-connect bridges Vim and Amazon Q CLI using the Model Context Protocol. In this video we will show real-time context sharing, live code updates, intelligent annotations, and AI-powered assistance—all without leaving your editor."

**Screen**: Show split screen - Vim on left, Q CLI on right

## Scene 2: Launch and Connect (45 seconds)

### Terminal 1 (Q CLI):
```bash
cd /path/to/demo-project
q chat
```

### Terminal 2 (Vim):
```vim
vim sample_app.py
:QConnect
```

**Show**: "Q MCP channel connected" message

**Narrator**: "Once connected, Q automatically knows what code you're looking at. No setup required."

## Scene 3: Context Awareness (60 seconds)

### In Vim:
- Position cursor on a specific function

### In Q CLI:
```
You: "What does this function do?"
```

**Show**: Q responds with detailed explanation of the exact function under cursor

**Narrator**: "Q reads your cursor position automatically. No copy-pasting needed."

## Scene 4: Navigate to File (30 seconds)

### In Q CLI:
```
You: "Go to the calculate_total function"
```

**Show**: Vim cursor jumping to that function automatically

**Narrator**: "Q can navigate your editor to specific functions and lines."

## Scene 5: Live Code Updates (60 seconds)

### In Vim:
- Position cursor on function without docstring

### In Q CLI:
```
You: "Add a docstring comment to this"
```

**Show**: Q adding docstring directly in Vim in real-time

**Narrator**: "Watch Q modify your code live. Changes appear instantly in your editor."

## Scene 6: Text Selection (45 seconds)

### In Vim:
- Select a block of code (visual mode)

### In Q CLI:
```
You: "Comment these lines"
```

**Show**: Q adding comments to the selected lines

**Narrator**: "Q works with your text selections, understanding exactly what code you've highlighted."

## Scene 7: Explain Selected Area (60 seconds)

### In Vim:
- Select a complex algorithm or code block

### In Q CLI:
```
You: "@explain"
```

**Show**: Q providing detailed explanation of the selected code

**Narrator**: "The @explain prompt gives detailed breakdowns of complex code sections."

## Scene 8: Explain Function (45 seconds)

### In Vim:
- Position cursor on different function

### In Q CLI:
```
You: "@explain this function"
```

**Show**: Q explaining the function's purpose, parameters, and logic

**Narrator**: "Context-aware explanations help you understand unfamiliar code quickly."

## Scene 9: Code Review (90 seconds)

### In Vim:
- Position cursor on function with security issues

### In Q CLI:
```
You: "@review this function"
```

**Show**: 

1. Q analyzing the code
2. Inline annotations appearing:
   ```python
   def process_payment(card_data):
       # 🔒 SECURITY: Sensitive data logged in plain text
       # Remove or encrypt sensitive information before logging
       logger.info(f"Processing card: {card_data}")
   ```
3. Quickfix list populating

**Narrator**: "The @review prompt finds security and quality issues, adding visual annotations and populating Vim's quickfix list."

## Scene 10: Quickfix Navigation (60 seconds)

### In Vim:
```vim
:copen
:cnext
:cprev
```

**Show**: 
- Quickfix window with issues
- Cursor jumping between issues
- Annotations appearing automatically

**Narrator**: "Navigate through issues with standard Vim commands. Annotations appear automatically as you move through the list."

## Scene 11: Fix Quickfix Issue (75 seconds)

### In Vim:
- Navigate to specific quickfix issue

### In Q CLI:
```
You: "@fix"
```

**Show**: Q automatically detecting the current issue and applying a fix

**Narrator**: "The @fix prompt intelligently detects your current quickfix issue and provides secure solutions."

## Scene 12: Coverage Annotation (90 seconds)

### Setup:
```bash
./run_coverage.py > coverage.json
```

### In Q CLI:
```
You: "Read the coverage data from coverage.json and annotate the current function with line-by-line coverage information"
```

**Show**: Q adding coverage annotations:

```python
def process_payment(amount, card_number):
    # ✅ COVERAGE: Line covered (executed 15 times)
    if amount <= 0:
        # ❌ COVERAGE: Line not covered (0 executions)
        raise ValueError("Invalid amount")
```

**Narrator**: "Q can integrate with external tools, annotating your code with test coverage, performance metrics, or any contextual data."

## Scene 13: Language Learning (90 seconds)

### In Vim:
- Open Rust file with complex syntax

### Sample Rust code:
```rust
fn process_data(input: &str) -> Result<Vec<String>, Box<dyn Error>> {
    match input.parse::<i32>() {
        Ok(num) if num > 0 => {
            // Complex pattern matching logic
        },
        Err(e) => return Err(Box::new(e)),
    }
}
```

### In Q CLI:
```
You: "@explain the rust syntax here to me"
```

**Narrator**: "I'm not a Rust programmer, but I need to understand this code. Let's see how Q can help explain unfamiliar language syntax."

**Show**: Q explaining ownership, pattern matching, error handling, etc.

## Scene 14: CloudFormation Documentation (90 seconds)

### In Vim:
- Open CloudFormation template with AWS resources

### Sample CloudFormation:
```yaml
Resources:
  MyBucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: my-app-bucket
      VersioningConfiguration:
        Status: Enabled
      PublicAccessBlockConfiguration:
        BlockPublicAcls: true
        BlockPublicPolicy: true
        IgnorePublicAcls: true
        RestrictPublicBuckets: true
      NotificationConfiguration:
        TopicConfigurations:
          - Topic: !Ref MyTopic
            Event: s3:ObjectCreated:*
```

### In Q CLI:
```
You: "Annotate this CloudFormation resource with field descriptions from the AWS docs"
```

**Show**: Q adding detailed annotations:

```yaml
Resources:
  MyBucket:
    # AWS::S3::Bucket - Creates an Amazon S3 bucket in the same AWS Region
    Type: AWS::S3::Bucket
    Properties:
      # BucketName - A name for the bucket (must be globally unique)
      # If not specified, AWS CloudFormation generates a unique name
      BucketName: my-app-bucket
      
      # VersioningConfiguration - Enables versioning for objects in the bucket
      # Status: Enabled | Suspended
      VersioningConfiguration:
        Status: Enabled
      
      # PublicAccessBlockConfiguration - Settings to block public access
      # Recommended for security best practices
      PublicAccessBlockConfiguration:
        BlockPublicAcls: true      # Blocks new public ACLs
        BlockPublicPolicy: true    # Blocks new public bucket policies
```

**Narrator**: "Q can pull documentation from AWS and annotate your infrastructure code with field descriptions, making CloudFormation templates self-documenting."

## Scene 15: Closing (30 seconds)

**Narrator**: "In this demo we've shown how vim-q-connect creates a seamless bridge between your editor and AI assistance. We saw real-time context sharing, live code modifications, and intelligent annotations for security and quality issues. We explored test coverage integration, cross-language syntax explanations, and AWS documentation for infrastructure code. No more copy-pasting code snippets or losing context between tools."

**Screen**: Show key benefits:

- ✅ Real-time context sharing
- ✅ Live code modifications
- ✅ Visual annotations
- ✅ Multi-language support
- ✅ External tool integration
- ✅ Zero copy-paste workflow

**Narrator**: "vim-q-connect: AI-powered coding assistance that truly knows your code. Available on GitHub."

## Technical Notes for Recording

### Sample Files Needed:
1. `sample_app.py` - Python functions for demos
2. `rust_example.rs` - Complex Rust syntax
3. `infrastructure.yaml` - CloudFormation template
4. `coverage.json` - Fake coverage data

### Key Visual Elements:
- Highlight the socket connection message
- Show cursor jumping to specific functions (navigation control)
- Zoom in on real-time code modifications appearing in Vim
- Emphasize visual selection highlighting in Vim
- Show inline annotations appearing with emoji indicators (🔒, ✅, ❌, ⚠️)
- Demonstrate quickfix list populating and navigation
- Highlight coverage annotations with different status indicators
- Show CloudFormation template being annotated with AWS docs
- Emphasize seamless context awareness across file switches
- Show split-screen view of Vim and Q CLI working together

### Timing: ~10-12 minutes total
