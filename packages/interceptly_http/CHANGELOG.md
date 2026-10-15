## 1.0.0

Initial release of the `package:http` adapter for Interceptly.

- Captures HTTP traffic via `InterceptlyHttpClient` wrapper while preserving single-subscription response streams.
- Honors global network simulation profiles and `InterceptlySettings.shouldCapture`.
- Requires `interceptly: ^2.1.0`.
