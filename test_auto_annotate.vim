" Test script for auto-annotation functionality
" Usage: vim -S test_auto_annotate.vim

" Source the plugin
source autoload/vim_q_connect.vim
source plugin/vim-q-connect.vim

" Create a test file
edit test_file.txt
call setline(1, ['function test() {', '  console.log("hello");', '}'])
write

" Create some quickfix entries
call setqflist([
  \ {'filename': 'test_file.txt', 'lnum': 1, 'text': 'Missing documentation'},
  \ {'filename': 'test_file.txt', 'lnum': 2, 'text': 'Use const instead of var'}
\ ])

echo "Test setup complete. Try these commands:"
echo ":QQuickfixAutoAnnotate    - Enable auto-annotation"
echo ":QQuickfixAutoAnnotate!   - Disable auto-annotation"
echo ":copen                    - Open quickfix window"
echo ":cnext                    - Navigate to next issue"
