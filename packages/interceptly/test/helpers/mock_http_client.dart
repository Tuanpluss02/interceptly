import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

class MockHttpClient extends Fake implements HttpClient {
  MockHttpClient([this.onRequest]);

  final void Function(MockHttpClientRequest request)? onRequest;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final req = MockHttpClientRequest(method, url);
    onRequest?.call(req);
    return req;
  }

  @override
  void close({bool force = false}) {}
}

class MockHttpClientRequest extends Fake implements HttpClientRequest {
  MockHttpClientRequest(this.method, this.uri);

  @override
  final String method;
  @override
  final Uri uri;
  @override
  final HttpHeaders headers = MockHttpHeaders();

  final List<int> _body = [];
  List<int> get bodyBytes => _body;
  String get body => utf8.decode(_body, allowMalformed: true);

  MockHttpClientResponse response = MockHttpClientResponse();

  @override
  void add(List<int> data) {
    _body.addAll(data);
  }

  @override
  Future<HttpClientResponse> close() async {
    return response;
  }
}

class MockHttpClientResponse extends Fake implements HttpClientResponse {
  MockHttpClientResponse({
    this.statusCode = 200,
    this.bodyStream,
  });

  @override
  final int statusCode;

  @override
  final HttpHeaders headers = MockHttpHeaders();

  final Stream<List<int>>? bodyStream;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return (bodyStream ?? const Stream<List<int>>.empty()).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

class MockHttpHeaders extends Fake implements HttpHeaders {
  final Map<String, String> _map = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _map[name.toLowerCase()] = value.toString();
  }

  @override
  void forEach(void Function(String name, List<String> values) action) {
    _map.forEach((k, v) => action(k, [v]));
  }

  @override
  String? value(String name) => _map[name.toLowerCase()];

  @override
  ContentType? get contentType {
    final ct = _map['content-type'];
    return ct != null ? ContentType.parse(ct) : null;
  }

  @override
  set contentType(ContentType? type) {
    if (type != null) {
      _map['content-type'] = type.toString();
    }
  }

  bool containsKey(String name) => _map.containsKey(name.toLowerCase());

  @override
  List<String>? operator [](String name) {
    final val = _map[name.toLowerCase()];
    return val != null ? [val] : null;
  }
}
