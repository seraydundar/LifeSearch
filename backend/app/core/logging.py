"""Structured logging setup.

Rule: never log personal document/content bodies (see requirements doc,
section 53). Only log identifiers and timings: request_id, user_id, job_id,
item_id, processing_time, error.
"""

import logging
import sys


def configure_logging(debug: bool = True) -> None:
    level = logging.DEBUG if debug else logging.INFO
    logging.basicConfig(
        level=level,
        stream=sys.stdout,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
