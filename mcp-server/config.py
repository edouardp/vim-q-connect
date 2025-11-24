"""
Configuration and logging setup for MCP server.
"""

import os
import logging


def setup_logging():
    """Configure logging for the MCP server."""
    log_level = os.environ.get("LOG_LEVEL", "INFO").upper()
    log_file = os.environ.get("LOG_FILE")
    log_config = {
        "level": getattr(logging, log_level, logging.INFO),
        "format": "%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    }
    if log_file:
        log_config.update({"filename": log_file, "filemode": "a"})
    logging.basicConfig(**log_config)
    return logging.getLogger("vim-context")


logger = setup_logging()
