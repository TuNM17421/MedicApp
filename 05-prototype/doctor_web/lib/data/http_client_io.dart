import 'package:http/http.dart' as http;

/// Outside the browser (tests): a plain client.
http.Client createHttpClient() => http.Client();
