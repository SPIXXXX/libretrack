import 'package:firebase_messaging/firebase_messaging.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // App is terminated — no UI access here, just logging for now.
  // ignore: avoid_print
  print(
    '[FCM Background] '
    'title=${message.notification?.title} '
    'body=${message.notification?.body} '
    'type=${message.data['type']}',
  );
}
