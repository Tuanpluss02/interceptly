## 1.2.0

 - **FEAT**(interceptly): clear logs per active tab ([#16](https://github.com/Tuanpluss02/interceptly/issues/16)). ([49e78f0d](https://github.com/Tuanpluss02/interceptly/commit/49e78f0d1769cbe69aacc7451afc6935a4232541))

## 1.1.0

 - **FEAT**: add example applications and update client instantiation syntax in documentation. ([6d9080e8](https://github.com/Tuanpluss02/interceptly/commit/6d9080e80088c70132e476a11086010ef2af680e))

## 1.0.0

Initial release of the WebSocket adapter for Interceptly.

- Captures bidirectional text/binary frames in real time via `InterceptlyWebSocketChannel`.
- Tracks connections, frames and close codes through `RealtimeTrafficCollector`.
- Supports live inspection and bidirectional message sending from the inspector UI.
- Requires `interceptly: ^2.1.0`.
