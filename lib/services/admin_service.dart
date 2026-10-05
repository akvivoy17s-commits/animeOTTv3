import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Admin = users/{uid}.role == 'admin' in Firestore (live).
class AdminService {
  AdminService._();

  static final ValueNotifier<bool> notifier = ValueNotifier<bool>(false);

  static bool get isAdmin => notifier.value;

  static StreamSubscription<User?>? _authSub;
  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _docSub;

  /// Call once after Firebase.initializeApp.
  static void init() {
    _authSub?.cancel();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      _docSub?.cancel();
      _docSub = null;
      if (user == null) {
        notifier.value = false;
        return;
      }
      _docSub = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen(
            (s) => notifier.value = s.data()?['role'] == 'admin',
            onError: (_) => notifier.value = false,
          );
    });
  }
}
