## 1.1.0

 - **FEAT**: add example applications and update client instantiation syntax in documentation. ([6d9080e8](https://github.com/Tuanpluss02/interceptly/commit/6d9080e80088c70132e476a11086010ef2af680e))

## 1.0.0

Initial release of the `package:http` adapter for Interceptly.

- Captures HTTP traffic via `InterceptlyHttpClient` wrapper while preserving single-subscription response streams.
- Honors global network simulation profiles and `InterceptlySettings.shouldCapture`.
- Requires `interceptly: ^2.1.0`.
