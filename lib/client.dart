import 'dart:async';

import 'package:service_worker/window.dart' as sw;

/// PWA client that is running in the window scope.
abstract class Client {
  /// Initializes a PWA client instance, also triggering the registration of
  /// the ServiceWorker on the given [scriptUrl].
  factory Client({String scriptUrl: './pwa.g.dart.js'}) =>
      new _PwaClient(scriptUrl);

  /// Whether the PWA is supported on this client.
  bool get isSupported;
}

/// PWA client that is running in the window scope.
@Deprecated('Use Client instead. PwaClient will be removed in 0.1')
abstract class PwaClient extends Client {
  /// Initializes a PWA client instance, also triggering the registration of
  /// the ServiceWorker on the given [scriptUrl].
  @Deprecated('Use Client instead. PwaClient will be removed in 0.1')
  factory PwaClient({String scriptUrl: './pwa.g.dart.js'}) =>
      new _PwaClient(scriptUrl);
}

// ignore: deprecated_member_use
class _PwaClient implements PwaClient {
  // Future<sw.ServiceWorkerRegistration> _registration;

  _PwaClient(String scriptUrl) {
    if (isSupported) {
      // _registration =
      _register(scriptUrl);
    }
  }

  @override
  bool get isSupported => sw.isSupported;

  Future<sw.ServiceWorkerRegistration> _register(String url) async {
    await sw.register(url);
    return await sw.ready;
  }
}
