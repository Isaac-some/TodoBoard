"""Protocol example: a real adapter must perform delivery and persist deduplication."""
import json,sys
packet=json.load(sys.stdin)
if packet.get('version')!=1:raise SystemExit('unsupported version')
# Deliberately fail instead of returning a receipt for work that was never delivered.
raise SystemExit('Implement your agent-specific submission and durable requestID receipt here.')
