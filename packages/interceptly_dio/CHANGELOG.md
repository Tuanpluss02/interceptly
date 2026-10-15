## 1.0.0

Initial release of the Dio adapter for Interceptly.

- Captures Dio requests, responses and errors via `InterceptlyDioInterceptor` without breaking app flow.
- Supports `CancelToken`, JSON, form-encoded, multipart `FormData` and binary payloads.
- Honors global network simulation profiles and `InterceptlySettings.shouldCapture`.
- Requires `interceptly: ^2.1.0`.
