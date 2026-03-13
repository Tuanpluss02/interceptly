import '../model/request_record.dart';

class HarExporter {
  const HarExporter._();

  static Map<String, Object?> fromRecords(List<RequestRecord> records) {
    return <String, Object?>{
      'log': <String, Object?>{
        'version': '1.2',
        'creator': <String, Object?>{
          'name': 'NetSpecter',
          'version': '0.0.1',
        },
        'entries': records
            .map(
              (r) => <String, Object?>{
                'startedDateTime': r.timestamp.toIso8601String(),
                'time': r.durationMs,
                'request': <String, Object?>{
                  'method': r.method,
                  'url': r.url,
                  'headers': r.requestHeaders.entries
                      .map((e) => <String, String>{
                            'name': e.key,
                            'value': e.value,
                          })
                      .toList(),
                  'postData': r.requestBodyPreview == null
                      ? null
                      : <String, Object?>{
                          'mimeType': r.requestContentType ?? '',
                          'text': r.requestBodyPreview,
                        },
                },
                'response': <String, Object?>{
                  'status': r.statusCode,
                  'headers': r.responseHeaders.entries
                      .map((e) => <String, String>{
                            'name': e.key,
                            'value': e.value,
                          })
                      .toList(),
                  'content': <String, Object?>{
                    'mimeType': r.responseContentType ?? '',
                    'text': r.responseBodyPreview ?? '',
                  },
                },
              },
            )
            .toList(),
      },
    };
  }
}
