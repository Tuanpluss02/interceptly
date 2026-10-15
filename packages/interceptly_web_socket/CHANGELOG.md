## 1.0.0

Initial release of the WebSocket adapter for Interceptly.

- Captures bidirectional text/binary frames in real time via `InterceptlyWebSocketChannel`.
- Tracks connections, frames and close codes through `RealtimeTrafficCollector`.
- Supports live inspection and bidirectional message sending from the inspector UI.
- Requires `interceptly: ^2.1.0`.
