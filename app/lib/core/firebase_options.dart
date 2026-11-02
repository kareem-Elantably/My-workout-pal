import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Firebase project "fitness-app-a703a" (push notifications only). These are
/// client identifiers from google-services.json / GoogleService-Info.plist,
/// not secrets.
///
/// The apps were registered in Firebase as "com.myworkoutpal.fitnessap"
/// (missing a "p"), while the app ID is "com.myworkoutpal.fitnessapp".
/// Register both apps again with the correct ID and replace the appId and
/// apiKey values below with the new ones.
abstract final class FirebaseConfig {
  static FirebaseOptions? get current => switch (defaultTargetPlatform) {
        _ when kIsWeb => null,
        TargetPlatform.android => android,
        TargetPlatform.iOS => ios,
        _ => null,
      };

  static const android = FirebaseOptions(
    apiKey: 'AIzaSyC1uM8hXU9_QrpLQ3kp4B9BuThQ5OjN28Y',
    appId: '1:79983378095:android:0db34b17f5e65adf73de5a',
    messagingSenderId: '79983378095',
    projectId: 'fitness-app-a703a',
    storageBucket: 'fitness-app-a703a.firebasestorage.app',
  );

  static const ios = FirebaseOptions(
    apiKey: 'AIzaSyCFQa6N9UaUGmMET0hWDqmQXh0Uc1cH6o8',
    appId: '1:79983378095:ios:eaf53da124208a4a73de5a',
    messagingSenderId: '79983378095',
    projectId: 'fitness-app-a703a',
    storageBucket: 'fitness-app-a703a.firebasestorage.app',
    iosBundleId: 'com.myworkoutpal.fitnessapp',
  );
}
