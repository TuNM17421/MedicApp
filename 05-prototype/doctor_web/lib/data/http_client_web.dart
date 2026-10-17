import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

/// In the browser: send the session cookie with every request, also when
/// the backend runs on another port during development.
http.Client createHttpClient() => BrowserClient()..withCredentials = true;
