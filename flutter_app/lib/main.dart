import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

const String kProductionUrl = 'https://sahjanand-api.onrender.com';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFC8290C)),
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

class _WebViewScreenState extends State<WebViewScreen> with WidgetsBindingObserver {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasError = false;
  int _retryCount = 0;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    await _requestPermissions();
    _initWebView();
    setState(() => _ready = true);
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.camera,
      Permission.microphone,
      Permission.storage,
      Permission.notification,
    ].request();
    if (Platform.isAndroid) {
      await Permission.photos.request();
      await Permission.videos.request();
    }
  }

  void _initWebView() {
    late final PlatformWebViewControllerCreationParams params;
    if (Platform.isAndroid) {
      params = AndroidWebViewControllerCreationParams();
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    _controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('FlutterBridge', onMessageReceived: _handleJsBridge)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() { _isLoading = true; _hasError = false; });
          },
          onPageFinished: (_) {
            if (mounted) setState(() { _isLoading = false; _retryCount = 0; });
            // Inject native file picker bridge into the page
            _injectBridge();
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? true) {
              if (mounted) {
                if (_retryCount < 3) {
                  _retryCount++;
                  Future.delayed(const Duration(seconds: 3), () {
                    if (mounted) _controller.loadRequest(Uri.parse(kProductionUrl));
                  });
                } else {
                  setState(() { _hasError = true; _isLoading = false; });
                }
              }
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(kProductionUrl));

    if (Platform.isAndroid) {
      final androidController = _controller.platform as AndroidWebViewController;
      androidController.setMediaPlaybackRequiresUserGesture(false);
      androidController.setOnPlatformPermissionRequest((request) {
        request.grant();
      });
    }
  }

  // Inject JavaScript bridge that intercepts file input clicks
  void _injectBridge() {
    _controller.runJavaScript('''
      (function() {
        // Override file inputs to use native picker
        document.addEventListener('click', function(e) {
          var target = e.target;
          // Check if clicked element is a file input or its parent triggers one
          if (target.tagName === 'INPUT' && target.type === 'file') {
            e.preventDefault();
            e.stopPropagation();
            var accept = target.accept || '*/*';
            FlutterBridge.postMessage(JSON.stringify({action: 'pickFile', accept: accept, inputId: target.id}));
            return false;
          }
        }, true);

        // Override getUserMedia for voice recording
        var origGetUserMedia = navigator.mediaDevices && navigator.mediaDevices.getUserMedia;
        if (navigator.mediaDevices) {
          navigator.mediaDevices.getUserMedia = function(constraints) {
            if (constraints && constraints.audio && !constraints.video) {
              // Audio only = voice recording, use native recorder
              FlutterBridge.postMessage(JSON.stringify({action: 'recordAudio'}));
              return Promise.reject(new DOMException('Using native recorder', 'NotAllowedError'));
            }
            return origGetUserMedia.call(navigator.mediaDevices, constraints);
          };
        }

        console.log('[FlutterBridge] Injected');
      })();
    ''');
  }

  // Handle messages from JavaScript bridge
  void _handleJsBridge(JavaScriptMessage message) async {
    try {
      final data = jsonDecode(message.message);
      final action = data['action'];

      if (action == 'pickFile') {
        final accept = data['accept'] as String? ?? '*/*';
        await _pickAndUploadFile(accept);
      } else if (action == 'recordAudio') {
        await _toggleAudioRecording();
      }
    } catch (e) {
      debugPrint('[FlutterBridge] Error: $e');
    }
  }

  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  String? _recordPath;

  // Pick file and upload immediately
  Future<void> _pickAndUploadFile(String accept) async {
    final picker = ImagePicker();
    List<XFile> files = [];

    if (accept.contains('image')) {
      final source = await _showImageSourceDialog();
      if (source == null) return;
      if (source == ImageSource.camera) {
        final img = await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
        if (img != null) files.add(img);
      } else {
        final imgs = await picker.pickMultiImage(imageQuality: 80);
        files.addAll(imgs);
      }
    } else if (accept.contains('video')) {
      final video = await picker.pickVideo(source: ImageSource.gallery);
      if (video != null) files.add(video);
    } else {
      // Generic - pick image or video
      final img = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (img != null) files.add(img);
    }

    if (files.isEmpty) return;

    // Upload each file
    for (final xfile in files) {
      await _uploadAndSend(File(xfile.path), xfile.name);
    }
  }

  // Toggle audio recording
  Future<void> _toggleAudioRecording() async {
    if (_isRecording) {
      // Stop recording and send
      final path = await _recorder.stop();
      _isRecording = false;
      if (path != null) {
        final file = File(path);
        await _uploadAndSend(file, 'voice_note.m4a');
      }
    } else {
      // Start recording
      final dir = await getTemporaryDirectory();
      _recordPath = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      if (await _recorder.hasPermission()) {
        await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: _recordPath!);
        _isRecording = true;
        // Show recording indicator in the page
        _controller.runJavaScript('''
          var btn = document.getElementById('chatRecordBtn');
          if(btn) btn.style.background='#c0392b';
          var btn2 = document.querySelector('.chat-record-btn');
          if(btn2) btn2.style.background='#c0392b';
        ''');
      }
    }
  }

  Future<ImageSource?> _showImageSourceDialog() async {
    return showDialog<ImageSource>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Select Source'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  // Upload file to server and send as chat message
  Future<void> _uploadAndSend(File file, String fileName) async {
    try {
      final tokenResult = await _controller.runJavaScriptReturningResult(
        'localStorage.getItem("sahjanand_token")'
      );
      String token = tokenResult.toString().replaceAll('"', '');
      if (token == 'null' || token.isEmpty) return;

      // Upload
      final uri = Uri.parse('$kProductionUrl/api/chat/upload');
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..files.add(await http.MultipartFile.fromPath('file', file.path, filename: fileName));

      final response = await request.send();
      if (response.statusCode == 200) {
        final respBody = await response.stream.bytesToString();
        final respData = jsonDecode(respBody);
        final mediaUrl = respData['url'] ?? respData['media_url'] ?? '';

        // Send as chat message immediately
        _controller.runJavaScript('''
          (function() {
            var token = localStorage.getItem('sahjanand_token');
            var gid = window.currentGroupId;
            var api = window.API || '';
            if (!gid || !token) return;
            
            var ext = '$fileName'.split('.').pop().toLowerCase();
            var msgType = 'image';
            if (['mp4','mov','webm','avi'].indexOf(ext) >= 0) msgType = 'video';
            if (['mp3','ogg','wav','m4a','webm','aac'].indexOf(ext) >= 0) msgType = 'voice';
            
            fetch(api + '/api/chat/groups/' + gid + '/messages', {
              method: 'POST',
              headers: {'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'},
              body: JSON.stringify({msg_type: msgType, media_url: '$mediaUrl', media_name: '$fileName', content: ''})
            }).then(function() {
              if (typeof refreshChatMessages === 'function') refreshChatMessages();
              // Reset record button color
              var btn = document.getElementById('chatRecordBtn');
              if(btn) btn.style.background='';
              var btn2 = document.querySelector('.chat-record-btn');
              if(btn2) btn2.style.background='';
            });
            
            // Also set reminder media fields
            var rmUrl = document.getElementById('reminderMediaUrl');
            if (rmUrl) rmUrl.value = '$mediaUrl';
            var rmName = document.getElementById('reminderMediaName');
            if (rmName) rmName.value = '$fileName';
            var rmInfo = document.getElementById('reminderMediaInfo');
            if (rmInfo) rmInfo.textContent = '📎 $fileName';
            var rpUrl = document.getElementById('rpMediaUrl');
            if (rpUrl) rpUrl.value = '$mediaUrl';
            var rpName = document.getElementById('rpMediaName');
            if (rpName) rpName.value = '$fileName';
            var rpInfo = document.getElementById('rpMediaInfo');
            if (rpInfo) rpInfo.textContent = '📎 $fileName';
          })();
        ''');
      }
    } catch (e) {
      debugPrint('[Upload] Error: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.runJavaScript(
        'if(typeof refreshChatMessages==="function")refreshChatMessages();'
        'if(typeof updateReminderNavBadge==="function")updateReminderNavBadge();'
        'if(typeof checkGlobalNewReminders==="function")checkGlobalNewReminders();'
      );
    }
  }

  void _retry() {
    setState(() { _hasError = false; _isLoading = true; _retryCount = 0; });
    _controller.loadRequest(Uri.parse(kProductionUrl));
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return Scaffold(
        backgroundColor: const Color(0xFFFFF9F5),
        body: const Center(child: CircularProgressIndicator(color: Color(0xFFC8290C))),
      );
    }

    return WillPopScope(
      onWillPop: () async {
        if (await _controller.canGoBack()) {
          await _controller.goBack();
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFFFF9F5),
        body: SafeArea(
          child: Stack(
            children: [
              if (_hasError)
                _buildErrorView()
              else
                WebViewWidget(controller: _controller),
              if (_isLoading) _buildLoadingView(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingView() {
    return Container(
      color: const Color(0xFFFFF9F5),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/icon.png', width: 100, height: 100, errorBuilder: (_, __, ___) =>
              const Icon(Icons.business, size: 64, color: Color(0xFFC8290C)),
            ),
            const SizedBox(height: 24),
            const Text('Sahjanand', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFFC8290C))),
            const SizedBox(height: 16),
            const SizedBox(width: 32, height: 32, child: CircularProgressIndicator(color: Color(0xFFC8290C), strokeWidth: 3)),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 64, color: Color(0xFFC8290C)),
          const SizedBox(height: 16),
          const Text('Could not connect', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _retry,
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFC8290C), foregroundColor: Colors.white),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
