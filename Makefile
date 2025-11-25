# Makefile for vim-q-connect development tasks
#
# Available targets:
#   tags - Generate ctags for code navigation in Vim

tags:
	ctags -R --exclude=.venv .
