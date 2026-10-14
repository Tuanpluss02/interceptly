/// Defines the network protocol scope for filtering list views in Interceptly.
enum NetworkProtocol {
  /// Displays both REST/HTTP requests and WebSocket/realtime connections.
  all,

  /// Displays only standard HTTP/REST requests (excludes WebSocket handshakes).
  rest,

  /// Displays only WebSocket and realtime connections.
  realtime,
}
