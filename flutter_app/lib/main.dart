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

  // Notification banner state
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
      // This enables the native Android file chooser for <input type="file">
      ac.setOnShowFileSelector(_androidFilePicker);
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // NATIVE FILE CHOOSER — called by Android WebView for <input type="file">
  // This is the CORRECT way to handle file uploads in Android WebView.
  // ═══════════════════════════════════════════════════════════════
  Future<List<String>> _androidFilePicker(FileSelectorParams params) async {
    try {
      final accept = params.acceptTypes.join(',').toLowerCase();

      if (accept.contains('image')) {
        return await _pickImageFiles();
      } else if (accept.contains('video')) {
        return await _pickVideoFiles();
      } else if (accept.contains('audio')) {
        // For audio inputs, show native file picker for audio files
        return await _pickAudioFiles();
      } else {
        // Generic file picker
        return await _pickGenericFiles();
      }
    } catch (e) {
      debugPrint('[FilePicker] Error: $e');
      return [];
    }
  }

  Future<List<String>> _pickImageFiles() async {
    final src = await _srcDialog();
    if (src == null) return [];

    final picker = ImagePicker();
    if (src == ImageSource.camera) {
      final f = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
      if (f != null) return [f.path];
    } else {
      final fs = await picker.pickMultiImage(imageQuality: 85);
      if (fs.isNotEmpty) return fs.map((f) => f.path).toList();
    }
    return [];
  }

  Future<List<String>> _pickVideoFiles() async {
    final src = await _videoSrcDialog();
    if (src == null) return [];

    final picker = ImagePicker();
    final f = await picker.pickVideo(source: src, maxDuration: const Duration(minutes: 5));
    if (f != null) return [f.path];
    return [];
  }

  Future<List<String>> _pickAudioFiles() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
    );
    if (r != null && r.files.isNotEmpty && r.files.single.path != null) {
      return [r.files.single.path!];
    }
    return [];
  }

  Future<List<String>> _pickGenericFiles() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: false);
    if (r != null && r.files.isNotEmpty && r.files.single.path != null) {
      return [r.files.single.path!];
    }
    return [];
  }

  // ═══════════════════════════════════════════════════════════════
  // JS BRIDGE — only needed for audio recording and notifications
  // File uploads are handled natively by Android WebView above.
  // ═══════════════════════════════════════════════════════════════
  void _injectBridge() {
    _controller.runJavaScript('''
(function(){
  if(window.__flutterBridgeV2) return;
  window.__flutterBridgeV2=true;

  // Override audio recording functions to use native recorder
  window.toggleRecord=function(){
    FlutterBridge.postMessage(JSON.stringify({action:'recordAudio'}));
  };
  window.toggleReminderVoice=function(){
    FlutterBridge.postMessage(JSON.stringify({action:'recordAudio'}));
  };
  window.toggleRpVoice=function(){
    FlutterBridge.postMessage(JSON.stringify({action:'recordAudio'}));
  };

  // Override getUserMedia to route audio to native
  if(!navigator.mediaDevices) navigator.mediaDevices={};
  var _origGUM=navigator.mediaDevices.getUserMedia;
  navigator.mediaDevices.getUserMedia=function(c){
    if(c&&c.audio&&!c.video){
      FlutterBridge.postMessage(JSON.stringify({action:'recordAudio'}));
      return Promise.reject(new DOMException('Native recording','NotAllowedError'));
    }
    if(_origGUM) return _origGUM.call(navigator.mediaDevices,c);
    return Promise.reject(new DOMException('Not supported','NotSupportedError'));
  };

  // Listen for new chat messages via WebSocket and notify Flutter
  var _origWsMsg=null;
  function hookWebSocket(){
    var _origWS=window.WebSocket;
    window.WebSocket=function(url,protocols){
      var ws=protocols?new _origWS(url,protocols):new _origWS(url);
      ws.addEventListener('message',function(evt){
        try{
          var d=JSON.parse(evt.data);
          if(d.event==='message'&&d.sender_name){
            FlutterBridge.postMessage(JSON.stringify({
              action:'chatNotif',
              sender:d.sender_name||'',
              text:d.content||'',
              type:d.msg_type||'text'
            }));
          }
        }catch(e){}
      });
      return ws;
    };
    window.WebSocket.prototype=_origWS.prototype;
    window.WebSocket.CONNECTING=_origWS.CONNECTING;
    window.WebSocket.OPEN=_origWS.OPEN;
    window.WebSocket.CLOSING=_origWS.CLOSING;
    window.WebSocket.CLOSED=_origWS.CLOSED;
  }
  hookWebSocket();
})();
    ''');
  }

  void _onBridgeMessage(JavaScriptMessage msg) async {
    try {
      final d = jsonDecode(msg.message);
      final action = d['action'] ?? '';

      switch (action) {
        case 'recordAudio':
          await _showRecordingUI();
          break;
        case 'chatNotif':
          _showChatNotification(
            d['sender'] ?? '',
            d['text'] ?? '',
            d['type'] ?? 'text',
          );
          break;
      }
    } catch (e) {
      debugPrint('[Bridge] $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // CHAT NOTIFICATION — WhatsApp-style banner on top
  // ═══════════════════════════════════════════════════════════════
  void _showChatNotification(String sender, String text, String type) {
    if (!mounted) return;
    // Don't show if sender is empty (own messages)
    if (sender.isEmpty) return;

    String body;
    switch (type) {
      case 'image':
        body = '📷 Photo';
        break;
      case 'video':
        body = '🎬 Video';
        break;
      case 'voice':
        body = '🎤 Voice note';
        break;
      default:
        body = text.length > 60 ? '${text.substring(0, 60)}...' : text;
    }

    setState(() => _notifMessage = '$sender: $body');
    _notifTimer?.cancel();
    _notifTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _notifMessage = null);
    });

    // Vibrate briefly
    HapticFeedback.mediumImpact();
  }

  // ═══════════════════════════════════════════════════════════════
  // VOICE RECORDING
  // ═══════════════════════════════════════════════════════════════
  Future<void> _showRecordingUI() async {
    var micStatus = await Permission.microphone.status;
    if (!micStatus.isGranted) {
      micStatus = await Permission.microphone.request();
    }

    if (micStatus.isPermanentlyDenied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Microphone permission denied. Enable in Settings.'),
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

    await _startRecording();
  }

  Future<void> _startRecording() async {
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
  // UPLOAD + SEND — uploads file and injects result into the page
  // ═══════════════════════════════════════════════════════════════
  Future<void> _uploadAndSend(File file, String name) async {
    if (!await file.exists() || await file.length() == 0) return;

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
          _injectUploadedMedia(url.toString(), name);
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

  void _injectUploadedMedia(String url, String name) {
    final nameLower = name.toLowerCase();
    final isAudio = nameLower.endsWith('.m4a') || nameLower.endsWith('.mp3') ||
        nameLower.endsWith('.ogg') || nameLower.endsWith('.wav') ||
        nameLower.endsWith('.webm') || nameLower.endsWith('.aac');

    _controller.runJavaScript('''
(function(){
  var token=localStorage.getItem('sahjanand_token'),api=window.API||'';
  var fullUrl='$url';
  var fileName='$name';
  var isAudio=${isAudio ? 'true' : 'false'};

  // Job Card form
  var jcPanel=document.getElementById('jcFormPanel');
  if(jcPanel&&jcPanel.style.display!=='none'&&jcPanel.offsetParent!==null&&!isAudio){
    var u=document.getElementById('jcImageUrl');if(u)u.value=fullUrl;
    var p=document.getElementById('jcImagePreview');
    if(p)p.innerHTML='<img src="'+fullUrl+'" style="max-height:80px;border-radius:8px;"/> <span style="color:green;font-size:.75rem;">Uploaded</span>';
    return;
  }

  // Reminder forms
  var rf=document.getElementById('reminderForm');
  if(rf&&rf.style.display!=='none'){
    var x=document.getElementById('reminderMediaUrl');if(x)x.value=fullUrl;
    x=document.getElementById('reminderMediaName');if(x)x.value=fileName;
    x=document.getElementById('reminderMediaInfo');if(x)x.textContent=fileName;
    return;
  }
  var rpf=document.getElementById('rpFormPanel');
  if(rpf&&rpf.style.display!=='none'){
    var x=document.getElementById('rpMediaUrl');if(x)x.value=fullUrl;
    x=document.getElementById('rpMediaName');if(x)x.value=fileName;
    x=document.getElementById('rpMediaInfo');if(x)x.textContent=fileName;
    return;
  }

  // Chat message
  var gid=window.currentGroupId;
  if(!gid||!token)return;
  var ext=fileName.split('.').pop().toLowerCase();
  var t='image';
  if(['mp4','mov','webm','avi','3gp'].indexOf(ext)>=0)t='video';
  if(isAudio||['mp3','ogg','wav','m4a','aac','amr'].indexOf(ext)>=0)t='voice';
  fetch(api+'/api/chat/groups/'+gid+'/messages',{method:'POST',
    headers:{'Authorization':'Bearer '+token,'Content-Type':'application/json'},
    body:JSON.stringify({msg_type:t,media_url:fullUrl,media_name:fileName,content:''})
  }).then(function(){if(typeof refreshChatMessages==='function')refreshChatMessages();});
})();
    ''');
  }

  // ═══════════════════════════════════════════════════════════════
  // UI
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
            // WebView
            if (_hasError)
              Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.cloud_off_rounded, size: 64, color: Color(0xFFC8290C)),
                const SizedBox(height: 16),
                const Text('Could not connect', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _retry,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFC8290C), foregroundColor: Colors.white),
                  child: const Text('Retry'),
                ),
              ]))
            else
              WebViewWidget(controller: _controller),

            // Loading splash
            if (_isLoading)
              Container(
                color: const Color(0xFFFFF9F5),
                child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Image.asset('assets/icon.png', width: 100, height: 100,
                      errorBuilder: (_, __, ___) => const Icon(Icons.business, size: 64, color: Color(0xFFC8290C))),
                  const SizedBox(height: 24),
                  const Text('Sahjanand', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFFC8290C))),
                  const SizedBox(height: 16),
                  const SizedBox(width: 32, height: 32, child: CircularProgressIndicator(color: Color(0xFFC8290C), strokeWidth: 3)),
                ])),
              ),

            // Chat notification banner (WhatsApp-style)
            if (_notifMessage != null) _buildNotifBanner(),

            // Recording overlay
            if (_isRecording) _buildRecordingOverlay(),

            // Upload indicator
            if (_isUploading) _buildUploadIndicator(),
          ]),
        ),
      ),
    );
  }

  Widget _buildNotifBanner() {
    return Positioned(
      top: 0, left: 0, right: 0,
      child: Material(
        elevation: 4,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: Color(0xFF2D1B0E),
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(12),
              bottomRight: Radius.circular(12),
            ),
          ),
          child: Row(children: [
            const CircleAvatar(
              radius: 18,
              backgroundColor: Color(0xFFC8290C),
              child: Icon(Icons.chat, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _notifMessage ?? '',
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            GestureDetector(
              onTap: () => setState(() => _notifMessage = null),
              child: const Icon(Icons.close, color: Colors.white54, size: 20),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildRecordingOverlay() {
    return Positioned(
      left: 0, right: 0, bottom: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10, offset: const Offset(0, -2))],
        ),
        child: SafeArea(
          top: false,
          child: Row(children: [
            GestureDetector(
              onTap: _cancelRecording,
              child: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: Colors.grey.shade200, shape: BoxShape.circle),
                child: const Icon(Icons.delete_outline, color: Colors.red, size: 24),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Row(children: [
              Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text('Recording ${_formatDuration(_recordingSeconds)}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            ])),
            GestureDetector(
              onTap: _stopAndSendRecording,
              child: Container(
                width: 48, height: 48,
                decoration: const BoxDecoration(color: Color(0xFFC8290C), shape: BoxShape.circle),
                child: const Icon(Icons.send, color: Colors.white, size: 22),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildUploadIndicator() {
    return Positioned(
      left: 0, right: 0, bottom: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        color: Colors.white,
        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFC8290C))),
          SizedBox(width: 12),
          Text('Uploading...', style: TextStyle(fontSize: 14, color: Colors.black54)),
        ]),
      ),
    );
  }
}
