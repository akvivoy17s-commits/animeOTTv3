import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:logging/logging.dart';

class UserFirestoreService {
  UserFirestoreService._();

  static final Logger _logger = Logger('UserFirestoreService');

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Future<void> saveSignedInUser(User user) async {
    try {
      final userReference = _firestore.collection('users').doc(user.uid);

      final data = <String, dynamic>{
        'uid': user.uid,
        'email': user.email ?? '',
        'displayName': user.displayName ?? '',
        'photoUrl': user.photoURL ?? '',
        'providerIds': user.providerData
            .map((provider) => provider.providerId)
            .toList(),

        'authCreatedAt': user.metadata.creationTime != null
            ? Timestamp.fromDate(user.metadata.creationTime!)
            : FieldValue.serverTimestamp(),

        'lastLoginAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await userReference.set(data, SetOptions(merge: true));

      _logger.info('User saved to Firestore');
    } catch (e, stackTrace) {
      _logger.severe('Firestore save error', e, stackTrace);
      rethrow;
    }
  }
}
