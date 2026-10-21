/// The smoke MCP: an agent drives a running app through MCP tools
/// (screenshots, the widgets on screen, taps, drags, scrolls, keys, text,
/// waits, smoke videos) synthesized inside Flutter, never through the real
/// mouse or keyboard. [serveSmokeMcp] runs in an integration test; the
/// stdio bridge `bin/smoke_mcp_bridge.dart` launches that test and forwards
/// the agent's tool calls to it.
library;

export 'package:lumina_smoke/src/mcp/smoke_mcp_commands.dart';
export 'package:lumina_smoke/src/mcp/smoke_mcp_server.dart';
