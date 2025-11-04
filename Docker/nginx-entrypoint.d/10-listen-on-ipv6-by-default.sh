#!/usr/bin/env sh
# Override the default Nginx helper that mutates default.conf so the read-only
# mount from the host does not generate warnings during container start.
exit 0
