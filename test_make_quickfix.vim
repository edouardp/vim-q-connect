" Test script for :make quickfix compatibility
" Usage: vim -S test_make_quickfix.vim

" Source the plugin
source autoload/vim_q_connect.vim
source plugin/vim-q-connect.vim

" Create a test C file with errors
edit test.c
call setline(1, [
  \ '#include <stdio.h>',
  \ 'int main() {',
  \ '    printf("Hello world")',  " Missing semicolon
  \ '    return 0;',
  \ '}'
\ ])
write

" Simulate :make output by creating quickfix entries like gcc would
call setqflist([
  \ {'filename': 'test.c', 'lnum': 3, 'text': 'error: expected '';'' before ''}'' token', 'type': 'E'},
  \ {'filename': 'test.c', 'lnum': 3, 'text': 'warning: unused variable', 'type': 'W'}
\ ])

echo "Test setup complete. Try these commands:"
echo ":QQuickfixAutoAnnotate    - Enable auto-annotation"
echo ":copen                    - Open quickfix window"
echo ":cnext                    - Navigate to issues"
echo ""
echo "Notice: These quickfix entries have NO user_data (like real :make output)"
