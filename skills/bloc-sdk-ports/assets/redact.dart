// Target: lib/core/logging/redact.dart

/// Keys whose values are always secret or personal.
const sensitiveKeys = {
  'access_token',
  'refresh_token',
  'id_token',
  'token',
  'authorization',
  'api_key',
  'apikey',
  'secret',
  'password',
  'pin',
  'otp',
  'signature',
  'sig',
  'session',
  'email',
  'phone',
};

final _keyValue = RegExp(
  '(["\']?\\b(?:${sensitiveKeys.join('|')})\\b["\']?\\s*[:=]\\s*)'
  '("[^"]*"|\'[^\']*\'|[^\\s&,;}\\]]+)',
  caseSensitive: false,
);
final _bearer = RegExp(
  r'\bBearer\s+[A-Za-z0-9\-._~+/]+=*',
  caseSensitive: false,
);
final _jwt = RegExp(r'\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*');
final _email = RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}');
final _phone = RegExp(r'\+?\d[\d\s().-]{7,}\d');

/// Masks secrets and personal data in free text before it reaches a log,
/// crash report or analytics property.
///
/// Errs toward over-masking: any run of 9+ digits is treated as a phone
/// number, which also hides long ids.
String redact(String input) => input
    .replaceAll(_bearer, 'Bearer ***')
    .replaceAll(_jwt, '<jwt>')
    .replaceAllMapped(_keyValue, (m) => '${m[1]}***')
    .replaceAll(_email, '<email>')
    .replaceAll(_phone, '<phone>');

/// [redact] for a property map: sensitive keys are masked whole, strings are
/// redacted, nested maps are walked.
Map<String, Object?> redactMap(Map<String, Object?> map) => {
  for (final MapEntry(:key, :value) in map.entries)
    key: sensitiveKeys.contains(key.toLowerCase())
        ? '***'
        : switch (value) {
            final String s => redact(s),
            final Map<String, Object?> m => redactMap(m),
            _ => value,
          },
};
