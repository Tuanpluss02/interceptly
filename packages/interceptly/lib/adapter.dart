/// Service Provider Interface (SPI) for Interceptly network capture adapters.
///
/// Import this library when creating satellite adapters (Dio, Chopper, Http, WebSocket)
/// or implementing custom network traffic collectors.
library;

export 'src/adapter/http_capture_scope.dart' show HttpCaptureScope;
export 'src/adapter/http_request_context.dart' show HttpRequestContext;
export 'src/adapter/http_traffic_collector.dart'
    show DefaultHttpTrafficCollector, HttpTrafficCollector;
export 'src/adapter/realtime_session_scope.dart' show RealtimeSessionScope;
export 'src/adapter/realtime_traffic_collector.dart'
    show DefaultRealtimeTrafficCollector, RealtimeTrafficCollector;
export 'src/capture/body_bytes.dart'
    show encodeBodyBytes, mapHeaderEntries, normalizeHeaders, truncateUtf8;
export 'src/capture/capture_guard.dart';
export 'src/capture/multipart_summary.dart'
    show MultipartFileInfo, summarizeMultipart;
export 'src/capture/stream_capture.dart'
    show CappedBytesBuilder, teeStreamCapture;
export 'src/model/network_simulation.dart'
    show NetworkSimulationProfile, SimulatedNetworkException;
export 'src/model/raw_capture.dart' show RawCapture;
export 'src/model/realtime_frame.dart'
    show FrameDirection, FrameType, RealtimeFrame;
export 'src/session/inspector_session.dart' show InspectorSession;
export 'src/session/request_id.dart' show RequestId;
