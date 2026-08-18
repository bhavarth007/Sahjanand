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
import 'package:record/record.dart';

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
  bool _isLoading = true, _hasError = false, _ready = false;
  int _retryCount = 0;
  bool _isRecording = false;
  Timer? _recordingTimer;
  int _recordingSeconds = 0;
  bool _isUploading = false;
  String? _notifMessage;
  Timer? _notifTimer;

  // Audio recorder using the 'record' package (no native Kotlin needed)
  final AudioRecorder _audioRecorder = AudioRecorder();
  String? _currentRecordingPath;

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
})();
    ''');
  }

  void _onBridgeMessage(JavaScriptMessage msg) async {
    try {
      final d = jsonDecode(msg.message);
      switch (d['a']) {
        case 'file': await _pickAndUpload(d['t'] ?? '*/*'); break;
        case 'rec': await _toggleRecording(); break;
        case 'notif': _showNotif(d['s'] ?? '', d['t'] ?? '', d['m'] ?? 'text'); break;
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
        final xf = await ImagePicker().pickImage(source: src, imageQuality: 85);
        if (xf == null) return;
        file = File(xf.path);
        name = xf.name.isNotEmpty ? xf.name : 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
      } else if (a.contains('video')) {
        final src = await _pickSourceDialog('Video');
        if (src == null) return;
        final xf = await ImagePicker().pickVideo(source: src, maxDuration: const Duration(minutes: 5));
        if (xf == null) return;
        file = File(xf.path);
        name = xf.name.isNotEmpty ? xf.name : 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';
      } else {
        final r = await FilePicker.platform.pickFiles(type: FileType.any);
        if (r == null || r.files.isEmpty || r.files.single.path == null) return;
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
  // AUDIO RECORDING (using 'record' package — pure Dart, no Kotlin)
  // ═══════════════════════════════════════════════════════════════
  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopAndSend();
      return;
    }

    // Check permission
    if (!await _audioRecorder.hasPermission()) {
      _snack('Microphone permission denied');
      return;
    }

    try {
      final dir = await getTemporaryDirectory();
      _currentRecordingPath = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: _currentRecordingPath!,
      );

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
      final path = await _audioRecorder.stop();
      if (mounted) setState(() => _isRecording = false);

      if (path != null && path.isNotEmpty) {
        final file = File(path);
        if (await file.exists() && await file.length() > 100) {
          await _upload(file, 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a');
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
    try { await _audioRecorder.cancel(); } catch (_) {}
    if (mounted) setState(() => _isRecording = false);
  }

  // ═══════════════════════════════════════════════════════════════
  // UPLOAD — Sends file to server, then injects URL into page
  // ═══════════════════════════════════════════════════════════════
  Future<void> _upload(File file, String name) async {
    final tr = await _controller.runJavaScriptReturningResult(
        'localStorage.getItem("sahjanand_token")');
    final token = tr.toString().replaceAll('"', '');
    if (token == 'null' || token.isEmpty) { _snack('Not logged in'); return; }

    if (mounted) setState(() => _isUploading = true);

    try {
      final req = http.MultipartRequest('POST', Uri.parse('$kProductionUrl/api/chat/upload'))
        ..headers['Authorization'] = 'Bearer $token'
        ..files.add(await http.MultipartFile.fromPath('file', file.path, filename: name));

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
  // NOTIFICATIONS
  // ═══════════════════════════════════════════════════════════════
  void _showNotif(String sender, String text, String type) {
    if (!mounted || sender.isEmpty) return;
    String body;
    switch (type) {
      case 'image': body = '📷 Photo'; break;
      case 'video': body = '🎬 Video'; break;
      case 'voice': body = '🎤 Voice note'; break;
      default: body = text.length > 50 ? '${text.substring(0, 50)}...' : (text.isEmpty ? 'New message' : text);
    }
    setState(() => _notifMessage = '$sender: $body');
    _notifTimer?.cancel();
    _notifTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _notifMessage = null);
    });
    HapticFeedback.mediumImpact();
  }

  // ═══════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════
  void _snack(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _fmt(int s) => '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  Future<ImageSource?> _pickSourceDialog(String type) => showDialog<ImageSource>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('$type Source'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.camera_alt), title: const Text('Camera'),
            onTap: () => Navigator.pop(c, ImageSource.camera)),
        ListTile(leading: const Icon(Icons.photo_library), title: const Text('Gallery'),
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
    _audioRecorder.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.runJavaScript('if(typeof refreshChatMessages==="function")refreshChatMessages();');
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
      return const Scaffold(backgroundColor: Color(0xFFFFF9F5),
          body: Center(child: CircularProgressIndicator(color: Color(0xFFC8290C))));
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
        body: SafeArea(child: Stack(children: [
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

          if (_notifMessage != null) _buildNotif(),
          if (_isRecording) _buildRecorder(),
          if (_isUploading) _buildUploading(),
        ])),
      ),
    );
  }

  Widget _buildNotif() => Positioned(top: 0, left: 0, right: 0,
      child: Material(elevation: 4, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(color: Color(0xFF2D1B0E),
              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12))),
          child: Row(children: [
            const CircleAvatar(radius: 18, backgroundColor: Color(0xFFC8290C),
                child: Icon(Icons.chat, color: Colors.white, size: 18)),
            const SizedBox(width: 12),
            Expanded(child: Text(_notifMessage ?? '', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                maxLines: 2, overflow: TextOverflow.ellipsis)),
            GestureDetector(onTap: () => setState(() => _notifMessage = null),
                child: const Icon(Icons.close, color: Colors.white54, size: 20)),
          ]))));

  Widget _buildRecorder() => Positioned(left: 0, right: 0, bottom: 0,
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
              Text('Recording ${_fmt(_recordingSeconds)}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            ])),
            GestureDetector(onTap: _stopAndSend, child: Container(width: 48, height: 48,
                decoration: const BoxDecoration(color: Color(0xFFC8290C), shape: BoxShape.circle),
                child: const Icon(Icons.send, color: Colors.white, size: 22))),
          ]))));

  Widget _buildUploading() => Positioned(left: 0, right: 0, bottom: 0,
      child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), color: Colors.white,
          child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFC8290C))),
            SizedBox(width: 12),
            Text('Uploading...', style: TextStyle(fontSize: 14, color: Colors.black54)),
          ])));
}
