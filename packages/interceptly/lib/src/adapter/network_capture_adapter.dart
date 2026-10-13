import '../session/inspector_session.dart';
import 'http_traffic_collector.dart';
import 'realtime_traffic_collector.dart';

/// Contract implemented by HTTP network capture adapters (Dio, Http, Chopper, etc.).
abstract interface class HttpCaptureAdapter {
  /// The collector coordinating HTTP capture lifecycle.
  HttpTrafficCollector get collector;

  /// The underlying inspector session.
  InspectorSession get session;
}

/// Contract implemented by realtime network capture adapters (WebSocket, SSE, etc.).
abstract interface class RealtimeCaptureAdapter {
  /// The collector coordinating realtime capture lifecycle.
  RealtimeTrafficCollector get collector;

  /// The underlying inspector session.
  InspectorSession get session;
}
