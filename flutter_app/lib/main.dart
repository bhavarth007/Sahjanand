import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kProductionUrl = 'https://sahjanand-api.onrender.com';
const MethodChannel _recorderChannel = MethodChannel('com.sahjanand.recorder');

// ═══════════════════════════════════════════════════════════════
// NOTIFICATION CHANNELS (must match backend channel IDs)
// ═══════════════════════════════════════════════════════════════
const String _chatChannelId = 'sahjanand_chat';
const String _chatChannelName = 'Chat Messages';
const String _chatChannelDesc = 'New chat messages from groups';

const String _reminderChannelId = 'sahjanand_reminders';
const String _reminderChannelName = 'Reminders';
const String _reminderChannelDesc = 'Reminder alerts — alarm style';

// Keep-alive channel (silent, low priority, for foreground service)
const String _keepAliveChannelId = 'sahjanand_keepalive';
const String _keepAliveChannelName = 'Background Service';
const String _keepAliveChannelDesc = 'Keeps notifications working reliably';

// Reply action key
const String _replyActionId = 'reply_action';
const String _replyInputKey = 'reply_text';

// SharedPreferences keys
const String _prefFcmToken = 'fcm_token';
const String _prefAuthToken = 'auth_token';
const String _prefTokenRegistered = 'fcm_token_registered';

// ═══════════════════════════════════════════════════════════════
// FCM Background message handler (MUST be top-level function)
// ═══════════════════════════════════════════════════════════════
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // CRITICAL: WidgetsFlutterBinding must be initialized FIRST in background isolate.
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // IMPORTANT: With notification+data HYBRID messages, when the app is in
  // background/killed state, Android OS ALREADY shows the notification from
  // the 'notification' field automatically. We must NOT show a duplicate
  // notification here. We only need to:
  // 1. Send delivery ACK (so sender sees double-grey tick)
  // 2. Cancel the system notification and show our own ONLY if we need
  //    custom behavior (like reply action). But this risks not showing anything
  //    if the isolate gets killed. So we let the system notification stand.
  
  if (message.data.isNotEmpty) {
    // Send delivery ACK to server — this triggers the double-grey tick for sender
    await _sendDeliveryAck(message.data);
  }
  
  // DO NOT call _showSmartNotification here — Android OS already showed the
  // notification from the 'notification' field in the hybrid FCM message.
  // Showing another one would create duplicates.
}

/// Send delivery acknowledgement to the server (message received on device).
/// This is called both from background handler and foreground handler.
/// It tells the server "this device got the message" → triggers double-grey tick.
Future<void> _sendDeliveryAck(Map<String, dynamic> data) async {
  final messageId = data['message_id']?.toString() ?? '';
  final type = data['type']?.toString() ?? '';
  if (messageId.isEmpty || type != 'chat') return;

  try {
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString(_prefAuthToken) ?? '';
    if (authToken.isEmpty) return;

    await http.post(
      Uri.parse('$kProductionUrl/api/chat/messages/deliver'),
      headers: {
        'Authorization': 'Bearer $authToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'message_ids': [int.parse(messageId)]}),
    ).timeout(const Duration(seconds: 10));
  } catch (_) {
    // Silently fail — delivery ACK is best-effort
  }
}

// ═══════════════════════════════════════════════════════════════
// Alarm Manager callback for reminder backup (MUST be top-level)
// ═══════════════════════════════════════════════════════════════
@pragma('vm:entry-point')
Future<void> _alarmCallback() async {
  // This fires as a backup for reminders when FCM might not deliver.
  // We check pending reminders from the server and show any that are due.
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await _initLocalNotificationsMinimal();

  try {
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString(_prefAuthToken) ?? '';
    if (authToken.isEmpty) return;

    // Fetch pending reminders for this user
    final response = await http.get(
      Uri.parse('$kProductionUrl/api/chat/my-all-reminders?tab=pending'),
      headers: {'Authorization': 'Bearer $authToken'},
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final List reminders = jsonDecode(response.body);
      final now = DateTime.now();

      for (final r in reminders) {
        try {
          final dateStr = r['remind_date'] ?? '';
          final timeStr = r['remind_time'] ?? '';
          if (dateStr.isEmpty || timeStr.isEmpty) continue;

          final reminderDt = DateTime.parse('${dateStr}T$timeStr:00');
          final diff = reminderDt.difference(now).inSeconds;

          // Show notification if reminder is due within 2 minutes
          if (diff >= -60 && diff <= 120) {
            final name = r['name'] ?? 'Reminder';
            final creator = r['created_by_name'] ?? '';
            final reminderId = r['id']?.toString() ?? '';

            // Deduplication: check if we already showed this reminder notification
            // recently (within last 3 minutes). Prevents duplicates when both
            // FCM and alarm fire for the same reminder.
            final dedupeKey = '_shown_reminder_$reminderId';
            final lastShown = prefs.getInt(dedupeKey) ?? 0;
            final nowMs = now.millisecondsSinceEpoch ~/ 1000;
            if (nowMs - lastShown < 180) continue; // Skip — already shown recently

            await prefs.setInt(dedupeKey, nowMs);

            await _showReminderNotification(
              '\u26a1 Reminder Alert!',
              '$name${creator.isNotEmpty ? ' (set by $creator)' : ''} is due NOW!',
              {'type': 'reminder_alert', 'title': name},
            );
          }
        } catch (_) {}
      }

      // Cleanup old deduplication keys (older than 1 hour)
      final allKeys = prefs.getKeys();
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      for (final key in allKeys) {
        if (key.startsWith('_shown_reminder_') || key.startsWith('_shown_reminder_fcm_')) {
          final ts = prefs.getInt(key) ?? 0;
          if (nowSec - ts > 3600) {
            await prefs.remove(key);
          }
        }
        // Cleanup chat deduplication keys (message_id based)
        if (key.startsWith('_chat_msg_')) {
          await prefs.remove(key); // Always cleanup during alarm — they're short-lived
        }
      }
    } else if (response.statusCode == 401) {
      // Auth token expired — clear it so user re-authenticates on next app open.
      // Don't keep retrying with a stale token every 60 seconds.
      await prefs.remove(_prefAuthToken);
      await prefs.setBool(_prefTokenRegistered, false);
    }
  } catch (_) {}
}

// ═══════════════════════════════════════════════════════════════
// Local notifications plugin (global for background access)
// ═══════════════════════════════════════════════════════════════
final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

/// Minimal init for background isolate
Future<void> _initLocalNotificationsMinimal() async {
  const initSettings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  );
  await _localNotifications.initialize(
    initSettings,
    onDidReceiveNotificationResponse: _onNotificationResponse,
    onDidReceiveBackgroundNotificationResponse:
        _onBackgroundNotificationResponse,
  );

  // Create channels in background isolate too (they might not exist yet)
  final androidPlugin = _localNotifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
  if (androidPlugin != null) {
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _chatChannelId,
        _chatChannelName,
        description: _chatChannelDesc,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        sound: RawResourceAndroidNotificationSound('chat_tone'),
      ),
    );
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _reminderChannelId,
        _reminderChannelName,
        description: _reminderChannelDesc,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        sound: RawResourceAndroidNotificationSound('alarm_tone'),
      ),
    );
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _keepAliveChannelId,
        _keepAliveChannelName,
        description: _keepAliveChannelDesc,
        importance: Importance.min,
        playSound: false,
        enableVibration: false,
      ),
    );
  }
}

/// Handle notification tap or reply action in foreground
void _onNotificationResponse(NotificationResponse response) {
  if (response.notificationResponseType ==
      NotificationResponseType.selectedNotificationAction) {
    if (response.actionId == _replyActionId && response.input != null) {
      _sendReplyFromNotification(response.input!, response.payload);
    }
  } else if (response.notificationResponseType ==
      NotificationResponseType.selectedNotification) {
    // User tapped the notification body → store group_id for navigation
    _storeNotificationTapGroupId(response.payload);
  }
}

/// Handle notification reply in background (top-level)
@pragma('vm:entry-point')
void _onBackgroundNotificationResponse(NotificationResponse response) {
  if (response.actionId == _replyActionId && response.input != null) {
    _sendReplyFromNotification(response.input!, response.payload);
  } else if (response.notificationResponseType ==
      NotificationResponseType.selectedNotification) {
    _storeNotificationTapGroupId(response.payload);
  }
}

/// Store the group_id from notification tap for navigation on app resume
Future<void> _storeNotificationTapGroupId(String? payload) async {
  if (payload == null || payload.isEmpty) return;
  try {
    final data = jsonDecode(payload);
    final groupId = data['group_id']?.toString() ?? '';
    if (groupId.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('_pending_nav_group_id', groupId);
    }
  } catch (_) {}
}

/// Send reply directly to backend from notification action
Future<void> _sendReplyFromNotification(
    String replyText, String? payload) async {
  if (replyText.trim().isEmpty || payload == null) return;
  try {
    final data = jsonDecode(payload);
    final authToken = data['auth_token'] ?? '';
    final groupId = data['group_id'] ?? '';

    if (authToken.isEmpty || groupId.isEmpty) {
      // Try getting auth token from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final savedToken = prefs.getString(_prefAuthToken) ?? '';
      if (savedToken.isEmpty || groupId.isEmpty) return;

      await http.post(
        Uri.parse('$kProductionUrl/api/chat/groups/$groupId/messages'),
        headers: {
          'Authorization': 'Bearer $savedToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'msg_type': 'text', 'content': replyText.trim()}),
      );
      return;
    }

    await http.post(
      Uri.parse('$kProductionUrl/api/chat/groups/$groupId/messages'),
      headers: {
        'Authorization': 'Bearer $authToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'msg_type': 'text', 'content': replyText.trim()}),
    );
  } catch (_) {}
}

/// Show notification based on data payload type
Future<void> _showSmartNotification(Map<String, dynamic> data) async {
  final type = data['type'] ?? '';
  final title = data['title'] ?? 'Sahjanand';
  final body = data['body'] ?? '';

  // Skip showing if notification is too old (stale message from Doze wakeup).
  // Allow up to 10 minutes for chat; don't skip reminder_alerts.
  final sentAt = int.tryParse(data['sent_at']?.toString() ?? '');
  if (sentAt != null && type != 'reminder_alert') {
    final age = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 - sentAt;
    if (age > 600) return; // Skip notifications older than 10 minutes
  }

  // Deduplication for chat messages — use message_id as the unique key.
  // This prevents duplicates when both individual token push AND topic push arrive.
  // Also prevents sender from seeing their own message via topic delivery.
  if (type == 'chat') {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Skip if this is the sender's own device
      final senderId = data['sender_id']?.toString() ?? '';
      final myUserId = prefs.getString('_my_user_id') ?? '';
      if (myUserId.isNotEmpty && myUserId == senderId) return; // Own message

      // Deduplicate using message_id (unique per message, reliable)
      final messageId = data['message_id']?.toString() ?? '';
      if (messageId.isNotEmpty) {
        final dedupeKey = '_chat_msg_$messageId';
        final alreadyShown = prefs.getBool(dedupeKey) ?? false;
        if (alreadyShown) return; // Already shown this exact message
        await prefs.setBool(dedupeKey, true);
      }
    } catch (_) {}
  }

  // Deduplication for reminder alerts
  if (type == 'reminder_alert') {
    try {
      final reminderTitle = data['title'] ?? '';
      if (reminderTitle.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        final dedupeKey = '_shown_reminder_fcm_${reminderTitle.hashCode}';
        final lastShown = prefs.getInt(dedupeKey) ?? 0;
        final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        if (nowSec - lastShown < 180) return; // Already shown in last 3 min
        await prefs.setInt(dedupeKey, nowSec);
      }
    } catch (_) {}
  }

  if (type == 'chat') {
    await _showChatNotification(title, body, data);
  } else if (type == 'reminder_alert' || type == 'reminder') {
    await _showReminderNotification(title, body, data);
  } else {
    await _showGenericNotification(title, body);
  }
}

/// Chat notification with reply action (WhatsApp style)
Future<void> _showChatNotification(
    String title, String body, Map<String, dynamic> data) async {
  // Try to inject auth token from shared prefs for reply action
  try {
    if (!data.containsKey('auth_token') || (data['auth_token']?.isEmpty ?? true)) {
      final prefs = await SharedPreferences.getInstance();
      final savedToken = prefs.getString(_prefAuthToken) ?? '';
      if (savedToken.isNotEmpty) {
        data['auth_token'] = savedToken;
      }
    }
  } catch (_) {}

  final androidDetails = AndroidNotificationDetails(
    _chatChannelId,
    _chatChannelName,
    channelDescription: _chatChannelDesc,
    importance: Importance.max,
    priority: Priority.high,
    showWhen: true,
    enableVibration: true,
    vibrationPattern: Int64List.fromList([0, 300, 100, 300]),
    playSound: true,
    sound: const RawResourceAndroidNotificationSound('chat_tone'),
    icon: '@mipmap/ic_launcher',
    category: AndroidNotificationCategory.message,
    visibility: NotificationVisibility.public,
    styleInformation: BigTextStyleInformation(body, contentTitle: title),
    // Group notifications by group_id so each group stacks separately
    groupKey: 'chat_group_${data['group_id'] ?? '0'}',
    actions: <AndroidNotificationAction>[
      const AndroidNotificationAction(
        _replyActionId,
        'Reply',
        icon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
        showsUserInterface: false,
        inputs: <AndroidNotificationActionInput>[
          AndroidNotificationActionInput(label: 'Type a reply...'),
        ],
      ),
    ],
  );

  final payload = jsonEncode(data);

  // Use message_id as notification ID for uniqueness per message.
  // This ensures each message shows its own notification and messages from
  // different groups don't overwrite each other.
  // Fallback to group_id if message_id is not available (older behavior).
  final messageId = int.tryParse(data['message_id']?.toString() ?? '');
  final groupId = int.tryParse(data['group_id']?.toString() ?? '');
  final notifId = messageId ?? groupId ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;

  await _localNotifications.show(
    notifId,
    title,
    body,
    NotificationDetails(android: androidDetails),
    payload: payload,
  );
}

/// Reminder notification — alarm style with long vibration and full-screen intent
Future<void> _showReminderNotification(
    String title, String body, Map<String, dynamic> data) async {
  final androidDetails = AndroidNotificationDetails(
    _reminderChannelId,
    _reminderChannelName,
    channelDescription: _reminderChannelDesc,
    importance: Importance.max,
    priority: Priority.high,
    showWhen: true,
    enableVibration: true,
    // 5 second vibration pattern: vibrate 1s, pause 0.5s, vibrate 1s, pause 0.5s, vibrate 1.5s
    vibrationPattern:
        Int64List.fromList([0, 1000, 500, 1000, 500, 1500]),
    playSound: true,
    sound: const RawResourceAndroidNotificationSound('alarm_tone'),
    icon: '@mipmap/ic_launcher',
    category: AndroidNotificationCategory.alarm,
    fullScreenIntent: true,
    ongoing: true,
    autoCancel: true,
    ticker: 'Reminder Alert!',
    styleInformation: BigTextStyleInformation(body, contentTitle: title),
    // Wake up the device
    visibility: NotificationVisibility.public,
  );

  await _localNotifications.show(
    // Use title hashCode as notification ID to prevent duplicates for same reminder
    (data['title']?.toString() ?? title).hashCode.abs() % 100000,
    title,
    body,
    NotificationDetails(android: androidDetails),
  );
}

/// Generic notification fallback
Future<void> _showGenericNotification(String title, String body) async {
  const androidDetails = AndroidNotificationDetails(
    _chatChannelId,
    _chatChannelName,
    channelDescription: _chatChannelDesc,
    importance: Importance.max,
    priority: Priority.high,
    showWhen: true,
    enableVibration: true,
    playSound: true,
    icon: '@mipmap/ic_launcher',
  );

  await _localNotifications.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000,
    title,
    body,
    const NotificationDetails(android: androidDetails),
  );
}

// ═══════════════════════════════════════════════════════════════
// MAIN
// ═══════════════════════════════════════════════════════════════
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp();

  // Set up background message handler BEFORE any other FCM calls
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Initialize Android Alarm Manager (for reminder backup scheduling)
  await AndroidAlarmManager.initialize();

  // Initialize local notifications with action handling
  const initSettings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  );
  await _localNotifications.initialize(
    initSettings,
    onDidReceiveNotificationResponse: _onNotificationResponse,
    onDidReceiveBackgroundNotificationResponse:
        _onBackgroundNotificationResponse,
  );

  // Create notification channels (Android 8+)
  final androidPlugin = _localNotifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  if (androidPlugin != null) {
    // Chat channel — with reply action support and custom sound
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _chatChannelId,
        _chatChannelName,
        description: _chatChannelDesc,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        sound: RawResourceAndroidNotificationSound('chat_tone'),
      ),
    );

    // Reminder channel — alarm style, long vibration, custom alarm sound
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _reminderChannelId,
        _reminderChannelName,
        description: _reminderChannelDesc,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        sound: RawResourceAndroidNotificationSound('alarm_tone'),
      ),
    );

    // Keep-alive channel — silent, for background service
    await androidPlugin.createNotificationChannel(
      const AndroidNotificationChannel(
        _keepAliveChannelId,
        _keepAliveChannelName,
        description: _keepAliveChannelDesc,
        importance: Importance.min,
        playSound: false,
        enableVibration: false,
      ),
    );
  }

  // Schedule periodic alarm as backup for reminders (every 60 seconds)
  // This ensures reminders fire even if FCM doesn't deliver
  await AndroidAlarmManager.periodic(
    const Duration(seconds: 60),
    0, // alarm ID
    _alarmCallback,
    exact: true,
    wakeup: true,
    rescheduleOnReboot: true,
  );

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const SahjanandApp());
}

class SahjanandApp extends StatelessWidget {
  const SahjanandApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sahjanand',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme:
            ColorScheme.fromSeed(seedColor: const Color(0xFFC8290C)),
        useMaterial3: true,
      ),
      home: const WebViewScreen(),
    );
  }
}

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});
  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen>
    with WidgetsBindingObserver {
  late final WebViewController _controller;
  bool _isLoading = true, _hasError = false, _ready = false;
  int _retryCount = 0;
  bool _isRecording = false;
  Timer? _recordingTimer;
  int _recordingSeconds = 0;
  bool _isUploading = false;

  // Audio recorder using native MethodChannel (Kotlin MediaRecorder)
  String? _currentRecordingPath;

  // FCM token registration state
  Timer? _tokenRetryTimer;
  bool _fcmTokenRegistered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    await [
      Permission.camera,
      Permission.microphone,
      Permission.storage,
      Permission.notification,
    ].request();
    if (Platform.isAndroid) {
      await Permission.photos.request();
      await Permission.videos.request();
      await Permission.audio.request();
      // Request battery optimization exemption for reliable background notifications
      await Permission.ignoreBatteryOptimizations.request();
      // Request exact alarm permission for reminders (Android 12+)
      await Permission.scheduleExactAlarm.request();
    }
    _initWebView();
    _initFCM();
    setState(() => _ready = true);
  }

  // ═══════════════════════════════════════════════════════════════
  // FCM SETUP — Robust notification initialization
  // ═══════════════════════════════════════════════════════════════
  Future<void> _initFCM() async {
    final messaging = FirebaseMessaging.instance;

    // Request permission (Android 13+ requires runtime permission)
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
      criticalAlert: true, // For alarm-style reminders
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('[FCM] Notification permission denied by user');
    }

    // For data-only messages, this doesn't matter much, but set it anyway
    await messaging.setForegroundNotificationPresentationOptions(
      alert: false, // We handle foreground display ourselves
      badge: true,
      sound: false,
    );

    // Subscribe to a topic for broadcast messages
    await messaging.subscribeToTopic('all_users');

    // Get FCM token and start registration process
    final fcmToken = await messaging.getToken();
    if (fcmToken != null) {
      _startTokenRegistration(fcmToken);
    }

    // Listen for token refresh
    messaging.onTokenRefresh.listen((newToken) {
      _startTokenRegistration(newToken);
    });

    // Subscribe to user's group topics for reliable group message delivery.
    // FCM topics provide a secondary delivery path: even if individual token
    // delivery fails (device offline too long, token rotated), topic messages
    // still reach the device when it reconnects.
    _subscribeToGroupTopics();

    // ─── FOREGROUND messages ───
    // With notification+data hybrid, when app is in foreground:
    // - System notification is suppressed (we set alert:false above)
    // - onMessage fires with both notification and data fields
    // - We show a system tray notification via flutter_local_notifications
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      if (message.data.isEmpty && message.notification == null) return;

      // Use data fields if available, otherwise extract from notification
      final data = Map<String, dynamic>.from(message.data);
      if (data['title'] == null && message.notification?.title != null) {
        data['title'] = message.notification!.title!;
      }
      if (data['body'] == null && message.notification?.body != null) {
        data['body'] = message.notification!.body!;
      }

      // Inject auth token for reply action
      try {
        final prefs = await SharedPreferences.getInstance();
        final savedToken = prefs.getString(_prefAuthToken) ?? '';
        if (savedToken.isNotEmpty) {
          data['auth_token'] = savedToken;
        }
      } catch (_) {}

      // Send delivery ACK (message received on this device)
      _sendDeliveryAck(data);

      // Show system tray notification (Android notification bar, like WhatsApp).
      // _showSmartNotification handles deduplication and self-message filtering.
      await _showSmartNotification(data);
    });

    // ─── Notification tap (app was in background) ───
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleNotificationTap(message.data);
    });

    // ─── Handle initial message (app was terminated, user tapped notification) ───
    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      // App was opened from a terminated state by tapping notification
      // Store the group_id to navigate after webview loads
      final groupId = initialMessage.data['group_id']?.toString() ?? '';
      if (groupId.isNotEmpty) {
        _pendingNavigationGroupId = groupId;
      }
    }
  }

  /// Pending group navigation from terminated-state notification tap
  String? _pendingNavigationGroupId;

  /// Handle notification tap — navigate to the correct group in the webview
  void _handleNotificationTap(Map<String, dynamic> data) {
    final groupId = data['group_id']?.toString() ?? '';
    if (groupId.isNotEmpty) {
      _controller.runJavaScript(
        'if(typeof selectGroup==="function")selectGroup($groupId);'
        'else if(typeof refreshChatMessages==="function")refreshChatMessages();'
      );
    } else {
      _controller.runJavaScript(
        'if(typeof refreshChatMessages==="function")refreshChatMessages();');
    }
  }

  /// Start FCM token registration with robust retry logic.
  /// The challenge: webview needs to load first so we can get auth token.
  /// Solution: persist auth token to SharedPreferences and retry registration.
  void _startTokenRegistration(String fcmToken) async {
    // Save FCM token for later use
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefFcmToken, fcmToken);

    // Try registering immediately if we have a saved auth token
    final savedAuthToken = prefs.getString(_prefAuthToken) ?? '';
    if (savedAuthToken.isNotEmpty) {
      final success = await _registerFcmTokenWithServer(fcmToken, savedAuthToken);
      if (success) {
        _fcmTokenRegistered = true;
        return;
      }
    }

    // Retry with exponential backoff — wait for webview to load and extract token
    _tokenRetryTimer?.cancel();
    int attempt = 0;
    _tokenRetryTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      attempt++;
      if (attempt > 12 || _fcmTokenRegistered) {
        timer.cancel();
        return;
      }

      // Try to get auth token from webview
      try {
        final tr = await _controller.runJavaScriptReturningResult(
            'localStorage.getItem("sahjanand_token")');
        final token = tr.toString().replaceAll('"', '');
        if (token != 'null' && token.isNotEmpty) {
          // Save auth token for future use (background handler, reply actions)
          await prefs.setString(_prefAuthToken, token);

          final success = await _registerFcmTokenWithServer(fcmToken, token);
          if (success) {
            _fcmTokenRegistered = true;
            timer.cancel();
          }
        }
      } catch (_) {
        // Webview might not be ready yet, will retry
      }
    });
  }

  /// Actually register FCM token with the backend
  Future<bool> _registerFcmTokenWithServer(
      String fcmToken, String authToken) async {
    try {
      final response = await http.post(
        Uri.parse('$kProductionUrl/api/auth/fcm-token'),
        headers: {
          'Authorization': 'Bearer $authToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'fcm_token': fcmToken}),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('[FCM] Token registered successfully');
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_prefTokenRegistered, true);
        return true;
      } else if (response.statusCode == 401) {
        // Auth token expired, clear saved token
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_prefAuthToken);
        return false;
      }
    } catch (e) {
      debugPrint('[FCM] Token registration failed: $e');
    }
    return false;
  }

  /// Subscribe to FCM topics for user's chat groups.
  /// This provides a secondary delivery channel (inspired by Tinode's approach):
  /// - Individual token push: primary path, goes directly to device
  /// - Topic subscription: backup path, FCM manages delivery internally
  /// Even if the token-based push is delayed or lost, topic messages
  /// reach all subscribed devices when they reconnect.
  Future<void> _subscribeToGroupTopics() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final authToken = prefs.getString(_prefAuthToken) ?? '';
      if (authToken.isEmpty) return;

      final response = await http.get(
        Uri.parse('$kProductionUrl/api/chat/groups'),
        headers: {'Authorization': 'Bearer $authToken'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List groups = jsonDecode(response.body);
        final messaging = FirebaseMessaging.instance;

        // Get previously subscribed topics
        final subscribedKey = '_fcm_subscribed_groups';
        final previouslySubscribed =
            prefs.getStringList(subscribedKey) ?? [];
        final currentGroupTopics = <String>[];

        for (final group in groups) {
          final groupId = group['id']?.toString() ?? '';
          if (groupId.isNotEmpty) {
            final topic = 'chat_group_$groupId';
            currentGroupTopics.add(topic);
            if (!previouslySubscribed.contains(topic)) {
              await messaging.subscribeToTopic(topic);
              debugPrint('[FCM] Subscribed to topic: $topic');
            }
          }
        }

        // Unsubscribe from groups user is no longer a member of
        for (final oldTopic in previouslySubscribed) {
          if (!currentGroupTopics.contains(oldTopic)) {
            await messaging.unsubscribeFromTopic(oldTopic);
            debugPrint('[FCM] Unsubscribed from topic: $oldTopic');
          }
        }

        // Save current subscriptions
        await prefs.setStringList(subscribedKey, currentGroupTopics);
      }
    } catch (e) {
      debugPrint('[FCM] Group topic subscription failed: $e');
    }
  }

  void _initWebView() {
    final params = Platform.isAndroid
        ? AndroidWebViewControllerCreationParams()
        : const PlatformWebViewControllerCreationParams();

    _controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('FlutterBridge',
          onMessageReceived: _onBridgeMessage)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() { _isLoading = true; _hasError = false; });
        },
        onPageFinished: (_) {
          if (mounted) setState(() { _isLoading = false; _retryCount = 0; });
          _injectBridge();
          // After page load, try to save the auth token
          _saveAuthTokenFromWebview();
          // Handle pending notification tap (app was terminated, user tapped notif)
          _handlePendingNavigation();
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame ?? true) {
            if (_retryCount < 3) {
              _retryCount++;
              Future.delayed(const Duration(seconds: 3), () {
                if (mounted) _controller.loadRequest(Uri.parse(kProductionUrl));
              });
            } else {
              if (mounted)
                setState(() { _hasError = true; _isLoading = false; });
            }
          }
        },
      ))
      ..loadRequest(Uri.parse(kProductionUrl));

    if (Platform.isAndroid) {
      final ac = _controller.platform as AndroidWebViewController;
      ac.setMediaPlaybackRequiresUserGesture(false);
      ac.setOnPlatformPermissionRequest((r) => r.grant());
    }
  }

  /// Handle pending navigation from terminated-state notification tap
  void _handlePendingNavigation() async {
    String? gid = _pendingNavigationGroupId;
    _pendingNavigationGroupId = null;

    // Also check SharedPreferences (set by background notification tap handler)
    if (gid == null || gid.isEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        gid = prefs.getString('_pending_nav_group_id');
        if (gid != null && gid.isNotEmpty) {
          await prefs.remove('_pending_nav_group_id');
        }
      } catch (_) {}
    }

    if (gid != null && gid.isNotEmpty) {
      // Wait for page JS to initialize, then navigate to the group
      Future.delayed(const Duration(seconds: 3), () {
        _controller.runJavaScript(
          'if(typeof selectGroup==="function")selectGroup($gid);'
        );
      });
    }
  }

  /// Save auth token from webview to SharedPreferences for background use
  Future<void> _saveAuthTokenFromWebview() async {
    try {
      await Future.delayed(const Duration(seconds: 2));
      final tr = await _controller.runJavaScriptReturningResult(
          'localStorage.getItem("sahjanand_token")');
      final token = tr.toString().replaceAll('"', '');
      if (token != 'null' && token.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefAuthToken, token);

        // Extract user ID from JWT for deduplication
        try {
          final parts = token.split('.');
          if (parts.length == 3) {
            String payload = parts[1];
            while (payload.length % 4 != 0) {
              payload += '=';
            }
            final decoded = utf8.decode(base64Url.decode(payload));
            final Map<String, dynamic> claims = jsonDecode(decoded);
            final userId = claims['user_id']?.toString() ?? '';
            if (userId.isNotEmpty) {
              await prefs.setString('_my_user_id', userId);
            }
          }
        } catch (_) {}

        // If FCM token not yet registered, try now
        if (!_fcmTokenRegistered) {
          final fcmToken = prefs.getString(_prefFcmToken);
          if (fcmToken != null) {
            final success =
                await _registerFcmTokenWithServer(fcmToken, token);
            if (success) _fcmTokenRegistered = true;
          }
        }

        // Subscribe to group topics (updates subscriptions if groups changed)
        _subscribeToGroupTopics();
      }
    } catch (_) {}
  }

  // ═══════════════════════════════════════════════════════════════
  // JS BRIDGE
  // ═══════════════════════════════════════════════════════════════
  void _injectBridge() {
    _controller.runJavaScript('''
(function(){
  if(window.__SB) return;
  window.__SB = true;

  // 1. Intercept file input clicks
  var _oc = HTMLInputElement.prototype.click;
  HTMLInputElement.prototype.click = function(){
    if(this.type === 'file'){
      FlutterBridge.postMessage(JSON.stringify({a:'file', t:this.accept||'*/*'}));
      return;
    }
    _oc.apply(this, arguments);
  };
  document.addEventListener('click', function(e){
    if(e.target && e.target.tagName === 'INPUT' && e.target.type === 'file'){
      e.preventDefault(); e.stopPropagation();
      FlutterBridge.postMessage(JSON.stringify({a:'file', t:e.target.accept||'*/*'}));
    }
  }, true);

  // 2. Override recording
  window.toggleRecord = function(){ FlutterBridge.postMessage(JSON.stringify({a:'rec'})); };
  window.toggleReminderVoice = function(){ FlutterBridge.postMessage(JSON.stringify({a:'rec'})); };
  window.toggleRpVoice = function(){ FlutterBridge.postMessage(JSON.stringify({a:'rec'})); };
  if(!navigator.mediaDevices) navigator.mediaDevices = {};
  navigator.mediaDevices.getUserMedia = function(c){
    if(c && c.audio){
      FlutterBridge.postMessage(JSON.stringify({a:'rec'}));
      return Promise.reject(new DOMException('native','NotAllowedError'));
    }
    return Promise.reject(new DOMException('no','NotSupportedError'));
  };

  // 3. WebSocket hook for notifications
  var _W = window.WebSocket;
  window.WebSocket = function(u,p){
    var ws = p ? new _W(u,p) : new _W(u);
    ws.addEventListener('message', function(ev){
      try{
        var d = JSON.parse(ev.data);
        if(d.event==='message' && d.sender_name){
          FlutterBridge.postMessage(JSON.stringify({a:'notif', s:d.sender_name, t:d.content||'', m:d.msg_type||'text'}));
        }
      }catch(x){}
    });
    return ws;
  };
  window.WebSocket.prototype = _W.prototype;
  window.WebSocket.CONNECTING = _W.CONNECTING;
  window.WebSocket.OPEN = _W.OPEN;
  window.WebSocket.CLOSING = _W.CLOSING;
  window.WebSocket.CLOSED = _W.CLOSED;

  // 4. Save auth token changes to Flutter for background notification handling
  var _setItem = Storage.prototype.setItem;
  Storage.prototype.setItem = function(k, v) {
    _setItem.apply(this, arguments);
    if (k === 'sahjanand_token') {
      FlutterBridge.postMessage(JSON.stringify({a:'token', v:v}));
    }
  };
})();
    ''');
  }

  void _onBridgeMessage(JavaScriptMessage msg) async {
    try {
      final d = jsonDecode(msg.message);
      switch (d['a']) {
        case 'file':
          await _pickAndUpload(d['t'] ?? '*/*');
          break;
        case 'rec':
          await _toggleRecording();
          break;
        case 'notif':
          // No in-app banner — notifications show in Android system notification bar only.
          // The chat UI already updates in real-time via WebSocket.
          break;
        case 'token':
          // Auth token changed in webview, save it
          final token = d['v']?.toString() ?? '';
          if (token.isNotEmpty) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_prefAuthToken, token);

            // Extract user ID from JWT payload for deduplication
            // (JWT is base64url-encoded: header.payload.signature)
            try {
              final parts = token.split('.');
              if (parts.length == 3) {
                String payload = parts[1];
                // Add padding if necessary
                while (payload.length % 4 != 0) {
                  payload += '=';
                }
                final decoded = utf8.decode(base64Url.decode(payload));
                final Map<String, dynamic> claims = jsonDecode(decoded);
                final userId = claims['user_id']?.toString() ?? '';
                if (userId.isNotEmpty) {
                  await prefs.setString('_my_user_id', userId);
                }
              }
            } catch (_) {}

            // Re-register FCM token with new auth
            if (!_fcmTokenRegistered) {
              final fcmToken = prefs.getString(_prefFcmToken);
              if (fcmToken != null) {
                final success =
                    await _registerFcmTokenWithServer(fcmToken, token);
                if (success) _fcmTokenRegistered = true;
              }
            }

            // Re-subscribe to group topics with new auth
            _subscribeToGroupTopics();
          }
          break;
      }
    } catch (_) {}
  }

  // ═══════════════════════════════════════════════════════════════
  // FILE PICK + UPLOAD (Images, Videos, Files)
  // ═══════════════════════════════════════════════════════════════
  Future<void> _pickAndUpload(String accept) async {
    File? file;
    String name = '';

    try {
      final a = accept.toLowerCase();
      if (a.contains('image')) {
        final src = await _pickSourceDialog('Image');
        if (src == null) return;
        final xf =
            await ImagePicker().pickImage(source: src, imageQuality: 85);
        if (xf == null) return;
        file = File(xf.path);
        name = xf.name.isNotEmpty
            ? xf.name
            : 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
      } else if (a.contains('video')) {
        final src = await _pickSourceDialog('Video');
        if (src == null) return;
        final xf = await ImagePicker().pickVideo(
            source: src, maxDuration: const Duration(minutes: 5));
        if (xf == null) return;
        file = File(xf.path);
        name = xf.name.isNotEmpty
            ? xf.name
            : 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';
      } else {
        final r = await FilePicker.platform.pickFiles(type: FileType.any);
        if (r == null || r.files.isEmpty || r.files.single.path == null)
          return;
        file = File(r.files.single.path!);
        name = r.files.single.name;
      }
    } catch (e) {
      _snack('Could not pick file');
      return;
    }

    if (file == null || !await file.exists()) return;
    await _upload(file, name);
  }

  // ═══════════════════════════════════════════════════════════════
  // AUDIO RECORDING (native Kotlin MethodChannel)
  // ═══════════════════════════════════════════════════════════════
  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopAndSend();
      return;
    }

    // Check permission
    var mic = await Permission.microphone.status;
    if (!mic.isGranted) mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      _snack('Microphone permission denied');
      return;
    }

    try {
      final dir = await getTemporaryDirectory();
      _currentRecordingPath =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorderChannel
          .invokeMethod('startRecording', {'path': _currentRecordingPath});

      _recordingSeconds = 0;
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recordingSeconds++);
      });
      if (mounted) setState(() => _isRecording = true);
    } catch (e) {
      _snack('Cannot record: ${e.toString().split('\n').first}');
    }
  }

  Future<void> _stopAndSend() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;

    try {
      final path =
          await _recorderChannel.invokeMethod<String>('stopRecording');
      if (mounted) setState(() => _isRecording = false);

      final filePath = path ?? _currentRecordingPath;
      if (filePath != null && filePath.isNotEmpty) {
        final file = File(filePath);
        if (await file.exists() && await file.length() > 100) {
          await _upload(
              file, 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a');
        } else {
          _snack('Recording too short');
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isRecording = false);
    }
  }

  Future<void> _cancelRecording() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    try {
      await _recorderChannel.invokeMethod('cancelRecording');
    } catch (_) {}
    if (mounted) setState(() => _isRecording = false);
  }

  // ═══════════════════════════════════════════════════════════════
  // UPLOAD — Sends file to server, then injects URL into page
  // ═══════════════════════════════════════════════════════════════
  Future<void> _upload(File file, String name) async {
    final tr = await _controller.runJavaScriptReturningResult(
        'localStorage.getItem("sahjanand_token")');
    final token = tr.toString().replaceAll('"', '');
    if (token == 'null' || token.isEmpty) {
      _snack('Not logged in');
      return;
    }

    if (mounted) setState(() => _isUploading = true);

    try {
      final req = http.MultipartRequest(
          'POST', Uri.parse('$kProductionUrl/api/chat/upload'))
        ..headers['Authorization'] = 'Bearer $token'
        ..files.add(
            await http.MultipartFile.fromPath('file', file.path, filename: name));

      final res = await req.send();
      if (mounted) setState(() => _isUploading = false);

      if (res.statusCode == 200) {
        final body = jsonDecode(await res.stream.bytesToString());
        final url = body['media_url'] ?? '';
        final msgType = body['msg_type'] ?? 'file';
        if (url.isNotEmpty) {
          _injectMedia(url, name, msgType);
        }
      } else {
        _snack('Upload failed');
      }
    } catch (e) {
      if (mounted) setState(() => _isUploading = false);
      _snack('Upload error');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // INJECT — Put uploaded media into the correct place on the page
  // ═══════════════════════════════════════════════════════════════
  void _injectMedia(String url, String name, String msgType) {
    _controller.runJavaScript('''
(function(){
  var token = localStorage.getItem('sahjanand_token');
  var url = '$url';
  var name = '$name';
  var msgType = '$msgType';

  // Job Card image
  var jc = document.getElementById('jcFormPanel');
  if(jc && jc.style.display !== 'none' && jc.offsetParent && msgType === 'image'){
    var u = document.getElementById('jcImageUrl'); if(u) u.value = url;
    var p = document.getElementById('jcImagePreview');
    if(p) p.innerHTML = '<img src="'+url+'" style="max-height:80px;border-radius:8px;"/> <span style="color:green;font-size:.75rem;">Done</span>';
    return;
  }

  // Reminder form
  var rf = document.getElementById('reminderForm');
  if(rf && rf.style.display !== 'none'){
    var x = document.getElementById('reminderMediaUrl'); if(x) x.value = url;
    x = document.getElementById('reminderMediaName'); if(x) x.value = name;
    x = document.getElementById('reminderMediaInfo'); if(x) x.textContent = name;
    return;
  }
  var rp = document.getElementById('rpFormPanel');
  if(rp && rp.style.display !== 'none'){
    var x = document.getElementById('rpMediaUrl'); if(x) x.value = url;
    x = document.getElementById('rpMediaName'); if(x) x.value = name;
    x = document.getElementById('rpMediaInfo'); if(x) x.textContent = name;
    return;
  }

  // Chat — send via REST POST (server broadcasts to all via WebSocket)
  var gid = window.currentGroupId;
  if(!gid || !token) return;
  fetch('/api/chat/groups/' + gid + '/messages', {
    method: 'POST',
    headers: {'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'},
    body: JSON.stringify({msg_type: msgType, media_url: url, media_name: name, content: ''})
  }).then(function(r){ return r.json(); }).then(function(){
    if(typeof refreshChatMessages === 'function') refreshChatMessages();
  }).catch(function(){});
})();
    ''');
  }

  // ═══════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════
  void _snack(String msg) {
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
  }

  String _fmt(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  Future<ImageSource?> _pickSourceDialog(String type) =>
      showDialog<ImageSource>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('$type Source'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Camera'),
                onTap: () => Navigator.pop(c, ImageSource.camera)),
            ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Gallery'),
                onTap: () => Navigator.pop(c, ImageSource.gallery)),
          ]),
        ),
      );

  // ═══════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═══════════════════════════════════════════════════════════════
  @override
  void dispose() {
    _recordingTimer?.cancel();
    _tokenRetryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.runJavaScript(
          'if(typeof refreshChatMessages==="function")refreshChatMessages();');
      // Re-save auth token when app resumes (user might have logged in/out)
      _saveAuthTokenFromWebview();
      // Check if user tapped a notification while app was backgrounded
      _handlePendingNavigation();
      // Cleanup stale chat dedup keys on resume
      _cleanupChatDedupeKeys();
    }
  }

  /// Remove old chat deduplication keys to prevent SharedPreferences bloat
  Future<void> _cleanupChatDedupeKeys() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys().toList();
      for (final key in allKeys) {
        if (key.startsWith('_chat_msg_') || key.startsWith('_chat_shown_')) {
          await prefs.remove(key);
        }
      }
    } catch (_) {}
  }

  void _retry() {
    setState(() {
      _hasError = false;
      _isLoading = true;
      _retryCount = 0;
    });
    _controller.loadRequest(Uri.parse(kProductionUrl));
  }

  // ═══════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
          backgroundColor: Color(0xFFFFF9F5),
          body: Center(
              child:
                  CircularProgressIndicator(color: Color(0xFFC8290C))));
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_isRecording) {
          await _cancelRecording();
          return;
        }
        if (await _controller.canGoBack()) {
          await _controller.goBack();
          return;
        }
        SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFFFF9F5),
        body: SafeArea(
            child: Stack(children: [
          if (_hasError)
            Center(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  const Icon(Icons.cloud_off_rounded,
                      size: 64, color: Color(0xFFC8290C)),
                  const SizedBox(height: 16),
                  const Text('Could not connect',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 24),
                  ElevatedButton(
                      onPressed: _retry,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFC8290C),
                          foregroundColor: Colors.white),
                      child: const Text('Retry')),
                ]))
          else
            WebViewWidget(controller: _controller),
          if (_isLoading)
            Container(
                color: const Color(0xFFFFF9F5),
                child: Center(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                      Image.asset('assets/icon.png',
                          width: 100,
                          height: 100,
                          errorBuilder: (_, __, ___) => const Icon(
                              Icons.business,
                              size: 64,
                              color: Color(0xFFC8290C))),
                      const SizedBox(height: 24),
                      const Text('Sahjanand',
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFC8290C))),
                      const SizedBox(height: 16),
                      const SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(
                              color: Color(0xFFC8290C), strokeWidth: 3)),
                    ]))),
          if (_isRecording) _buildRecorder(),
          if (_isUploading) _buildUploading(),
        ])),
      ),
    );
  }

  Widget _buildRecorder() => Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 12),
          decoration: BoxDecoration(color: Colors.white, boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 10,
                offset: const Offset(0, -2))
          ]),
          child: SafeArea(
              top: false,
              child: Row(children: [
                GestureDetector(
                    onTap: _cancelRecording,
                    child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            shape: BoxShape.circle),
                        child: const Icon(Icons.delete_outline,
                            color: Colors.red, size: 24))),
                const SizedBox(width: 12),
                Expanded(
                    child: Row(children: [
                  Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                          color: Colors.red, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Text('Recording ${_fmt(_recordingSeconds)}',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w500)),
                ])),
                GestureDetector(
                    onTap: _stopAndSend,
                    child: Container(
                        width: 48,
                        height: 48,
                        decoration: const BoxDecoration(
                            color: Color(0xFFC8290C),
                            shape: BoxShape.circle),
                        child: const Icon(Icons.send,
                            color: Colors.white, size: 22))),
              ]))));

  Widget _buildUploading() => Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 14),
          color: Colors.white,
          child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFFC8290C))),
                SizedBox(width: 12),
                Text('Uploading...',
                    style:
                        TextStyle(fontSize: 14, color: Colors.black54)),
              ])));
}
