## 1.1.0

 - **FEAT**: add example applications and update client instantiation syntax in documentation. ([6d9080e8](https://github.com/Tuanpluss02/interceptly/commit/6d9080e80088c70132e476a11086010ef2af680e))

## 1.0.0

Initial release of the Dio adapter for Interceptly.

- Captures Dio requests, responses and errors via `InterceptlyDioInterceptor` without breaking app flow.
- Supports `CancelToken`, JSON, form-encoded, multipart `FormData` and binary payloads.
- Honors global network simulation profiles and `InterceptlySettings.shouldCapture`.
- Requires `interceptly: ^2.1.0`.
