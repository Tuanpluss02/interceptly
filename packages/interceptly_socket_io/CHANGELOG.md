## 1.1.0

 - **FIX**: comprehensive hardening across engine lifecycle, storage, replay security, and surfaces ([#21](https://github.com/Tuanpluss02/interceptly/issues/21)). ([70f59607](https://github.com/Tuanpluss02/interceptly/commit/70f59607a0d75682ff37919ba13210a925f34b49))
 - **FIX**(socket_io): bump version to 1.0.1 and set socket_io_client lower bound to >=3.0.0. ([6cb506f3](https://github.com/Tuanpluss02/interceptly/commit/6cb506f3d656faa3b758aabc380fd2a792d340dc))
 - **FEAT**: add interceptly_mcp package and Dart VM Service protocol extensions ([#19](https://github.com/Tuanpluss02/interceptly/issues/19)). ([0395dac0](https://github.com/Tuanpluss02/interceptly/commit/0395dac050cae566070a3c09668748c0633d0ef0))
 - **FEAT**: add socket IO adapter ([#18](https://github.com/Tuanpluss02/interceptly/issues/18)). ([71e0f52a](https://github.com/Tuanpluss02/interceptly/commit/71e0f52aa6e838508ee0453d9fd20858f863eb3a))
 - **DOCS**(socket_io): fix doc reference in SocketIoSender constructor. ([070adca8](https://github.com/Tuanpluss02/interceptly/commit/070adca86f2fe5cc34ad009e04c85d132a1c4efd))

## 1.0.1

- Fix dependency constraint lower bound for `socket_io_client` to `>=3.0.0 <4.0.0` to ensure `onAnyOutgoing` and `offAnyOutgoing` APIs are available during dependency downgrade resolution.

## 1.0.0

Initial release of the Socket.IO adapter for Interceptly.

- Captures bidirectional Socket.IO events via `onAny` and `onAnyOutgoing`.
- Supports event badge rendering, JSON formatting, and binary payloads.
- Interactive event emission from the Interceptly inspector UI.
- Seamless attachment via `InterceptlySocketIo.attach(socket)` or `socket.attachInterceptly()`.
- Requires `interceptly: ^2.2.0` and `socket_io_client: '>=2.0.0 <4.0.0'`.
