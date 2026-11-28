import 'package:cloud_firestore/cloud_firestore.dart';

/// Shared-device policy for new Firestore clients. Must run before data I/O.
/// Does not erase old disk caches, Auth persistence or pending SDK requests.
abstract final class FirestoreCachePolicy {
  static final _configured = Expando<bool>();

  static void configure(FirebaseFirestore database) {
    if (_configured[database] == true) return;
    database.settings = const Settings(persistenceEnabled: false);
    _configured[database] = true;
  }
}
