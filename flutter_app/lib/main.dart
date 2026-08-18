import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

const String kProductionUrl = 'https://sahjanand-api.onrender.com';
const MethodChannel _recorderChannel = MethodChannel('com.sahjanand.recorder');

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
  bool _isLoading = true, _hasError = false, _ready = false;
  int _retryCount = 0;
  bool _isRecording = false;
  Timer? _recordingTimer;
  int _recordingSeconds = 0;
  bool _isUploading = false;
  String? _notifMessage;
  Timer? _notifTimer;

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
    }
    _initWebView();
    setState(() => _ready = true);
  }

  void _initWebView() {
    final params = Platform.isAndroid
        ? AndroidWebViewControllerCreationParams()
        : const PlatformWebViewControllerCreationParams();

    _controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('FlutterBridge', onMessageReceived: _onBridgeMessage)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() { _isLoading = true; _hasError = false; });
        },
        onPageFinished: (_) {
          if (mounted) setState(() { _isLoading = false; _retryCount = 0; });
          _injectBridge();
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame ?? true) {
            if (_retryCount < 3) {
              _retryCount++;
              Future.delayed(const Duration(seconds: 3), () {
                if (mounted) _controller.loadRequest(Uri.parse(kProductionUrl));
              });
            } else {
              if (mounted) setState(() { _hasError = true; _isLoading = false; });
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

  // ═══════════════════════════════════════════════════════════════
  // JS BRIDGE — Intercepts file inputs, audio recording, WebSocket messages
  // This is the ONLY reliable way on Android WebView.
  // ═══════════════════════════════════════════════════════════════
  void _injectBridge() {
    _controller.runJavaScript('''
(function(){
  if(window.__sahjanandBridge) return;
  window.__sahjanandBridge=true;

  // ─── 1. Intercept ALL file input clicks ───
  // Override .click() on file inputs so Flutter handles picking + uploading
  var _origClick = HTMLInputElement.prototype.click;
  HTMLInputElement.prototype.click = function(){
    if(this.type === 'file'){
      var accept = (this.accept || '*/*').toLowerCase();
      FlutterBridge.postMessage(JSON.stringify({action:'pickFile', accept:accept}));
      return;
    }
    return _origClick.apply(this, arguments);
  };

  // Also catch direct user clicks on file inputs
  document.addEventListener('click', function(e){
    var el = e.target;
    if(el && el.tagName === 'INPUT' && el.type === 'file'){
      e.preventDefault();
      e.stopPropagation();
      var accept = (el.accept || '*/*').toLowerCase();
      FlutterBridge.postMessage(JSON.stringify({action:'pickFile', accept:accept}));
      return false;
    }
  }, true);

  // ─── 2. Override audio recording ───
  window.toggleRecord = function(){
    FlutterBridge.postMessage(JSON.stringify({action:'recordAudio'}));
  };
  window.toggleReminderVoice = function(){
    FlutterBridge.postMessage(JSON.stringify({action:'recordAudio'}));
  };
  window.toggleRpVoice = function(){
    FlutterBridge.postMessage(JSON.stringify({action:'recordAudio'}));
  };

  // Override getUserMedia
  if(!navigator.mediaDevices) navigator.mediaDevices = {};
  navigator.mediaDevices.getUserMedia = function(c){
    if(c && c.audio && !c.video){
      FlutterBridge.postMessage(JSON.stringify({action:'recordAudio'}));
      return Promise.reject(new DOMException('Native','NotAllowedError'));
    }
    return Promise.reject(new DOMException('Not supported','NotSupportedError'));
  };

  // ─── 3. Hook WebSocket for chat notifications ───
  var _WS = window.WebSocket;
  window.WebSocket = function(url, protocols){
    var ws = protocols ? new _WS(url, protocols) : new _WS(url);
    ws.addEventListener('message', function(evt){
      try {
        var d = JSON.parse(evt.data);
        if(d.event === 'message' && d.sender_name){
          FlutterBridge.postMessage(JSON.stringify({
            action:'chatNotif',
            sender: d.sender_name || '',
            text: d.content || '',
            type: d.msg_type || 'text'
          }));
        }
      } catch(e){}
    });
    return ws;
  };
  window.WebSocket.prototype = _WS.prototype;
  window.WebSocket.CONNECTING = _WS.CONNECTING;
  window.WebSocket.OPEN = _WS.OPEN;
  window.WebSocket.CLOSING = _WS.CLOSING;
  window.WebSocket.CLOSED = _WS.CLOSED;
})();
    ''');
  }

  // ═══════════════════════════════════════════════════════════════
  // BRIDGE MESSAGE HANDLER
  // ═══════════════════════════════════════════════════════════════
  void _onBridgeMessage(JavaScriptMessage msg) async {
    try {
      final d = jsonDecode(msg.message);
      final action = d['action'] ?? '';
      switch (action) {
        case 'pickFile':
          await _handleFilePick(d['accept'] ?? '*/*');
          break;
        case 'recordAudio':
          await _showRecordingUI();
          break;
        case 'chatNotif':
          _showChatNotification(d['sender'] ?? '', d['text'] ?? '', d['type'] ?? 'text');
          break;
      }
    } catch (e) {
      debugPrint('[Bridge] $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // FILE PICKING — Pick natively, upload from Flutter, inject URL
  // ═══════════════════════════════════════════════════════════════
  Future<void> _handleFilePick(String accept) async {
    File? file;
    String? fileName;

    try {
      if (accept.contains('image')) {
        final src = await _srcDialog();
        if (src == null) return;
        final picker = ImagePicker();
        if (src == ImageSource.camera) {
          final xf = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
          if (xf != null) { file = File(xf.path); fileName = xf.name; }
        } else {
          final xf = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
          if (xf != null) { file = File(xf.path); fileName = xf.name; }
        }
      } else if (accept.contains('video')) {
        final src = await _videoSrcDialog();
        if (src == null) return;
        final picker = ImagePicker();
        final xf = await picker.pickVideo(source: src, maxDuration: const Duration(minutes: 5));
        if (xf != null) { file = File(xf.path); fileName = xf.name; }
      } else {
        final r = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: false);
        if (r != null && r.files.isNotEmpty && r.files.single.path != null) {
          file = File(r.files.single.path!);
          fileName = r.files.single.name;
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pick failed: ${e.toString().split('\n').first}')),
        );
      }
      return;
    }

    if (file == null || fileName == null) return;

    // Ensure filename has extension
    if (!fileName.contains('.')) {
      final ext = file.path.split('.').last;
      if (ext.isNotEmpty) fileName = '$fileName.$ext';
    }

    await _uploadAndSend(file, fileName);
  }

  // ═══════════════════════════════════════════════════════════════
  // UPLOAD + INJECT — Upload file to server, inject URL into page
  // ═══════════════════════════════════════════════════════════════
  Future<void> _uploadAndSend(File file, String name) async {
    if (!await file.exists() || await file.length() == 0) return;

    // Get auth token from WebView
    final tr = await _controller.runJavaScriptReturningResult(
        'localStorage.getItem("sahjanand_token")');
    final token = tr.toString().replaceAll('"', '');
    if (token == 'null' || token.isEmpty) return;

    if (mounted) setState(() => _isUploading = true);

    try {
      final req = http.MultipartRequest('POST', Uri.parse('$kProductionUrl/api/chat/upload'))
        ..headers['Authorization'] = 'Bearer $token'
        ..files.add(await http.MultipartFile.fromPath('file', file.path, filename: name));

      final res = await req.send();
      if (mounted) setState(() => _isUploading = false);

      if (res.statusCode == 200) {
        final body = jsonDecode(await res.stream.bytesToString());
        final url = body['media_url'] ?? body['url'] ?? '';
        if (url.toString().isNotEmpty) {
          _injectMedia(url.toString(), name);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Upload failed')),
          );
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isUploading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Upload error')),
        );
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // INJECT MEDIA — Put uploaded URL into the correct place on the page
  // ═══════════════════════════════════════════════════════════════
  void _injectMedia(String url, String name) {
    final ext = name.split('.').last.toLowerCase();
    final isAudio = ['m4a', 'mp3', 'ogg', 'wav', 'webm', 'aac'].contains(ext);
    final isVideo = ['mp4', 'mov', 'avi', '3gp'].contains(ext);

    String msgType = 'image';
    if (isAudio) msgType = 'voice';
    if (isVideo) msgType = 'video';

    _controller.runJavaScript('''
(function(){
  var token = localStorage.getItem('sahjanand_token');
  var api = window.API || '';
  var url = '$url';
  var name = '$name';
  var msgType = '$msgType';

  // 1. Check Job Card form
  var jcPanel = document.getElementById('jcFormPanel');
  if(jcPanel && jcPanel.style.display !== 'none' && jcPanel.offsetParent !== null && msgType === 'image'){
    var u = document.getElementById('jcImageUrl'); if(u) u.value = url;
    var p = document.getElementById('jcImagePreview');
    if(p) p.innerHTML = '<img src="'+url+'" style="max-height:80px;border-radius:8px;"/> <span style="color:green;font-size:.75rem;">Uploaded</span>';
    return;
  }

  // 2. Check Reminder form
  var rf = document.getElementById('reminderForm');
  if(rf && rf.style.display !== 'none'){
    var x = document.getElementById('reminderMediaUrl'); if(x) x.value = url;
    x = document.getElementById('reminderMediaName'); if(x) x.value = name;
    x = document.getElementById('reminderMediaInfo'); if(x) x.textContent = name;
    return;
  }
  var rpf = document.getElementById('rpFormPanel');
  if(rpf && rpf.style.display !== 'none'){
    var x = document.getElementById('rpMediaUrl'); if(x) x.value = url;
    x = document.getElementById('rpMediaName'); if(x) x.value = name;
    x = document.getElementById('rpMediaInfo'); if(x) x.textContent = name;
    return;
  }

  // 3. Send as chat message
  var gid = window.currentGroupId;
  if(!gid || !token) return;

  // Use WebSocket if connected (instant delivery)
  if(window.chatWs && window.chatWs.readyState === 1){
    window.chatWs.send(JSON.stringify({
      event: 'message',
      msg_type: msgType,
      media_url: url,
      media_name: name,
      content: ''
    }));
  } else {
    // Fallback: REST API
    fetch(api + '/api/chat/groups/' + gid + '/messages', {
      method: 'POST',
      headers: {'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'},
      body: JSON.stringify({msg_type: msgType, media_url: url, media_name: name, content: ''})
    }).then(function(){ if(typeof refreshChatMessages === 'function') refreshChatMessages(); });
  }
})();
    ''');
  }

  // ═══════════════════════════════════════════════════════════════
  // VOICE RECORDING
  // ═══════════════════════════════════════════════════════════════
  Future<void> _showRecordingUI() async {
    var micStatus = await Permission.microphone.status;
    if (!micStatus.isGranted) micStatus = await Permission.microphone.request();

    if (micStatus.isPermanentlyDenied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Microphone denied. Enable in Settings.'),
          action: SnackBarAction(label: 'Settings', onPressed: () => openAppSettings()),
        ));
      }
      return;
    }
    if (!micStatus.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission required')),
        );
      }
      return;
    }

    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorderChannel.invokeMethod('startRecording', {'path': path});
      _recordingSeconds = 0;
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recordingSeconds++);
      });
      if (mounted) setState(() => _isRecording = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Recording failed: ${e.toString().split('(').first}')),
        );
      }
    }
  }

  Future<void> _stopAndSendRecording() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    try {
      final String? path = await _recorderChannel.invokeMethod('stopRecording');
      if (mounted) setState(() => _isRecording = false);
      if (path != null && path.isNotEmpty) {
        final file = File(path);
        if (await file.exists() && await file.length() > 0) {
          await _uploadAndSend(file, 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a');
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isRecording = false);
    }
  }

  Future<void> _cancelRecording() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    try { await _recorderChannel.invokeMethod('cancelRecording'); } catch (_) {}
    if (mounted) setState(() => _isRecording = false);
  }

  // ═══════════════════════════════════════════════════════════════
  // CHAT NOTIFICATION BANNER
  // ═══════════════════════════════════════════════════════════════
  void _showChatNotification(String sender, String text, String type) {
    if (!mounted || sender.isEmpty) return;
    String body;
    switch (type) {
      case 'image': body = '📷 Photo'; break;
      case 'video': body = '🎬 Video'; break;
      case 'voice': body = '🎤 Voice note'; break;
      default: body = text.length > 50 ? '${text.substring(0, 50)}...' : text;
    }
    setState(() => _notifMessage = '$sender: $body');
    _notifTimer?.cancel();
    _notifTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _notifMessage = null);
    });
    HapticFeedback.mediumImpact();
  }

  // ═══════════════════════════════════════════════════════════════
  // DIALOGS
  // ═══════════════════════════════════════════════════════════════
  String _formatDuration(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  Future<ImageSource?> _srcDialog() => showDialog<ImageSource>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Select Source'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.camera_alt), title: const Text('Camera'),
            onTap: () => Navigator.pop(c, ImageSource.camera)),
        ListTile(leading: const Icon(Icons.photo_library), title: const Text('Gallery'),
            onTap: () => Navigator.pop(c, ImageSource.gallery)),
      ]),
    ),
  );

  Future<ImageSource?> _videoSrcDialog() => showDialog<ImageSource>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Select Video Source'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.videocam), title: const Text('Record Video'),
            onTap: () => Navigator.pop(c, ImageSource.camera)),
        ListTile(leading: const Icon(Icons.video_library), title: const Text('Gallery'),
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
    _notifTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.runJavaScript(
          'if(typeof refreshChatMessages==="function")refreshChatMessages();');
    }
  }

  void _retry() {
    setState(() { _hasError = false; _isLoading = true; _retryCount = 0; });
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
        body: Center(child: CircularProgressIndicator(color: Color(0xFFC8290C))),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_isRecording) { await _cancelRecording(); return; }
        if (await _controller.canGoBack()) { await _controller.goBack(); return; }
        SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFFFF9F5),
        body: SafeArea(
          child: Stack(children: [
            if (_hasError)
              Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.cloud_off_rounded, size: 64, color: Color(0xFFC8290C)),
                const SizedBox(height: 16),
                const Text('Could not connect', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                ElevatedButton(onPressed: _retry,
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFC8290C), foregroundColor: Colors.white),
                    child: const Text('Retry')),
              ]))
            else
              WebViewWidget(controller: _controller),

            if (_isLoading)
              Container(color: const Color(0xFFFFF9F5), child: Center(child: Column(
                mainAxisAlignment: MainAxisAlignment.center, children: [
                  Image.asset('assets/icon.png', width: 100, height: 100,
                      errorBuilder: (_, __, ___) => const Icon(Icons.business, size: 64, color: Color(0xFFC8290C))),
                  const SizedBox(height: 24),
                  const Text('Sahjanand', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFFC8290C))),
                  const SizedBox(height: 16),
                  const SizedBox(width: 32, height: 32, child: CircularProgressIndicator(color: Color(0xFFC8290C), strokeWidth: 3)),
                ]))),

            if (_notifMessage != null) _buildNotifBanner(),
            if (_isRecording) _buildRecordingOverlay(),
            if (_isUploading) _buildUploadIndicator(),
          ]),
        ),
      ),
    );
  }

  Widget _buildNotifBanner() => Positioned(top: 0, left: 0, right: 0,
    child: Material(elevation: 4, child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(color: Color(0xFF2D1B0E),
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12))),
      child: Row(children: [
        const CircleAvatar(radius: 18, backgroundColor: Color(0xFFC8290C),
            child: Icon(Icons.chat, color: Colors.white, size: 18)),
        const SizedBox(width: 12),
        Expanded(child: Text(_notifMessage ?? '',
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
            maxLines: 2, overflow: TextOverflow.ellipsis)),
        GestureDetector(onTap: () => setState(() => _notifMessage = null),
            child: const Icon(Icons.close, color: Colors.white54, size: 20)),
      ]),
    )));

  Widget _buildRecordingOverlay() => Positioned(left: 0, right: 0, bottom: 0,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10, offset: const Offset(0, -2))]),
      child: SafeArea(top: false, child: Row(children: [
        GestureDetector(onTap: _cancelRecording, child: Container(width: 44, height: 44,
            decoration: BoxDecoration(color: Colors.grey.shade200, shape: BoxShape.circle),
            child: const Icon(Icons.delete_outline, color: Colors.red, size: 24))),
        const SizedBox(width: 12),
        Expanded(child: Row(children: [
          Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text('Recording ${_formatDuration(_recordingSeconds)}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        ])),
        GestureDetector(onTap: _stopAndSendRecording, child: Container(width: 48, height: 48,
            decoration: const BoxDecoration(color: Color(0xFFC8290C), shape: BoxShape.circle),
            child: const Icon(Icons.send, color: Colors.white, size: 22))),
      ]))));

  Widget _buildUploadIndicator() => Positioned(left: 0, right: 0, bottom: 0,
    child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), color: Colors.white,
      child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFC8290C))),
        SizedBox(width: 12),
        Text('Uploading...', style: TextStyle(fontSize: 14, color: Colors.black54)),
      ])));
}
