## 1.4.0

 - **REFACTOR**: InspectorSession to Interceptly and clean up tests ([#17](https://github.com/Tuanpluss02/interceptly/issues/17)). ([3a9020ce](https://github.com/Tuanpluss02/interceptly/commit/3a9020ce7b4de4cd80430ed1836aaa042df4f778))
 - **FIX**: comprehensive hardening across engine lifecycle, storage, replay security, and surfaces ([#21](https://github.com/Tuanpluss02/interceptly/issues/21)). ([70f59607](https://github.com/Tuanpluss02/interceptly/commit/70f59607a0d75682ff37919ba13210a925f34b49))
 - **FEAT**: add interceptly_mcp package and Dart VM Service protocol extensions ([#19](https://github.com/Tuanpluss02/interceptly/issues/19)). ([0395dac0](https://github.com/Tuanpluss02/interceptly/commit/0395dac050cae566070a3c09668748c0633d0ef0))

## 1.3.0

 - **REFACTOR**: InspectorSession to Interceptly and clean up tests ([#17](https://github.com/Tuanpluss02/interceptly/issues/17)). ([3a9020ce](https://github.com/Tuanpluss02/interceptly/commit/3a9020ce7b4de4cd80430ed1836aaa042df4f778))
 - **FIX**: comprehensive hardening across engine lifecycle, storage, replay security, and surfaces ([#21](https://github.com/Tuanpluss02/interceptly/issues/21)). ([70f59607](https://github.com/Tuanpluss02/interceptly/commit/70f59607a0d75682ff37919ba13210a925f34b49))
 - **FEAT**: add interceptly_mcp package and Dart VM Service protocol extensions ([#19](https://github.com/Tuanpluss02/interceptly/issues/19)). ([0395dac0](https://github.com/Tuanpluss02/interceptly/commit/0395dac050cae566070a3c09668748c0633d0ef0))

## 1.2.0

 - **FEAT**(interceptly): clear logs per active tab ([#16](https://github.com/Tuanpluss02/interceptly/issues/16)). ([49e78f0d](https://github.com/Tuanpluss02/interceptly/commit/49e78f0d1769cbe69aacc7451afc6935a4232541))

## 1.1.0

 - **FEAT**: add example applications and update client instantiation syntax in documentation. ([6d9080e8](https://github.com/Tuanpluss02/interceptly/commit/6d9080e80088c70132e476a11086010ef2af680e))

## 1.0.0

Initial release of the Chopper adapter for Interceptly.

- Captures Chopper traffic via `InterceptlyChopperInterceptor` for requests, responses and errors.
- Honors global network simulation profiles and `InterceptlySettings.shouldCapture`.
- Requires `interceptly: ^2.1.0`.
