#!/bin/bash
SOCKET_DIR="$PWD"
cd "$(dirname "$0")"
SOCKET_DIR="$SOCKET_DIR" uv run python main.py
