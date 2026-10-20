## 1.0.1

- Fix dependency constraint lower bound for `socket_io_client` to `>=3.0.0 <4.0.0` to ensure `onAnyOutgoing` and `offAnyOutgoing` APIs are available during dependency downgrade resolution.

## 1.0.0

Initial release of the Socket.IO adapter for Interceptly.

- Captures bidirectional Socket.IO events via `onAny` and `onAnyOutgoing`.
- Supports event badge rendering, JSON formatting, and binary payloads.
- Interactive event emission from the Interceptly inspector UI.
- Seamless attachment via `InterceptlySocketIo.attach(socket)` or `socket.attachInterceptly()`.
- Requires `interceptly: ^2.2.0` and `socket_io_client: '>=2.0.0 <4.0.0'`.
