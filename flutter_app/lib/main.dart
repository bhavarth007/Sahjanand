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

// Method channel for native audio recording
const MethodChannel _recorderChannel = MethodChannel('com.sahjanand.recorder');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown, DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  runApp(const SahjanandApp());
}

class SahjanandApp extends StatelessWidget {
  const SahjanandApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(title: 'Sahjanand', debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFC8290C)), useMaterial3: true),
      home: const WebViewScreen());
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

  // Voice recording state
  bool _isRecording = false;
  Timer? _recordingTimer;
  int _recordingSeconds = 0;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    // Request all permissions upfront
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
    final params = Platform.isAndroid ? AndroidWebViewControllerCreationParams() : const PlatformWebViewControllerCreationParams();
    _controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('FlutterBridge', onMessageReceived: _onBridgeMessage)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) { if (mounted) setState(() { _isLoading = true; _hasError = false; }); },
        onPageFinished: (_) { if (mounted) setState(() { _isLoading = false; _retryCount = 0; }); _injectBridge(); },
        onWebResourceError: (e) {
          if (e.isForMainFrame ?? true) {
            if (_retryCount < 3) { _retryCount++; Future.delayed(const Duration(seconds: 3), () { if (mounted) _controller.loadRequest(Uri.parse(kProductionUrl)); }); }
            else { if (mounted) setState(() { _hasError = true; _isLoading = false; }); }
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

  void _injectBridge() {
    _controller.runJavaScript('''
(function(){
  if(window.__flutterBridgeInjected) return;
  window.__flutterBridgeInjected=true;

  // 1) Override HTMLInputElement.click() for file inputs
  var origClick=HTMLInputElement.prototype.click;
  HTMLInputElement.prototype.click=function(){
    if(this.type==='file'){
      try{FlutterBridge.postMessage(JSON.stringify({action:'pickFile',accept:this.accept||'*/*'}));}catch(e){}
      return;
    }
    return origClick.apply(this,arguments);
  };

  // 2) Intercept click events on file inputs (fallback for direct clicks)
  document.addEventListener('click',function(e){
    var t=e.target;
    if(t&&t.tagName==='INPUT'&&t.type==='file'){
      e.preventDefault();e.stopPropagation();
      try{FlutterBridge.postMessage(JSON.stringify({action:'pickFile',accept:t.accept||'*/*'}));}catch(ex){}
      return false;
    }
  },true);

  // 3) Override getUserMedia completely - always route audio to native
  if(!navigator.mediaDevices) navigator.mediaDevices={};
  navigator.mediaDevices.getUserMedia=function(constraints){
    if(constraints&&constraints.audio){
      try{FlutterBridge.postMessage(JSON.stringify({action:'pickAudio'}));}catch(ex){}
      return Promise.reject(new DOMException('Handled by native','NotAllowedError'));
    }
    return Promise.reject(new DOMException('Not supported in app','NotSupportedError'));
  };

  // 4) Override the toggleRecord function used by chat.js
  //    This prevents the JS recorder from running and routes to native
  window.toggleRecord=function(){
    try{FlutterBridge.postMessage(JSON.stringify({action:'pickAudio'}));}catch(ex){}
  };

  // 5) Also override toggleReminderVoice and toggleRpVoice for reminder recording
  window.toggleReminderVoice=function(){
    try{FlutterBridge.postMessage(JSON.stringify({action:'pickAudio'}));}catch(ex){}
  };
  window.toggleRpVoice=function(){
    try{FlutterBridge.postMessage(JSON.stringify({action:'pickAudio'}));}catch(ex){}
  };
})();
    ''');
  }

  void _onBridgeMessage(JavaScriptMessage msg) async {
    try {
      final d = jsonDecode(msg.message);
      final action = d['action'] ?? '';
      debugPrint('[Bridge] Action: $action');
      if (action == 'pickFile') await _pickFile(d['accept'] ?? '*/*');
      else if (action == 'pickAudio') await _showRecordingUI();
    } catch (e) { debugPrint('[Bridge] Error: $e'); }
  }

  // ── Voice Recording (WhatsApp-style) ──

  Future<void> _showRecordingUI() async {
    // Force request microphone permission
    var micStatus = await Permission.microphone.status;
    if (!micStatus.isGranted) {
      micStatus = await Permission.microphone.request();
    }
    
    if (micStatus.isPermanentlyDenied) {
      // User permanently denied - need to open settings
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Microphone permission denied. Please enable in Settings.'),
            action: SnackBarAction(label: 'Settings', onPressed: () => openAppSettings()),
          ),
        );
      }
      return;
    }
    
    if (!micStatus.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission is required to record audio')),
        );
      }
      return;
    }

    await _startRecording();
  }

  Future<void> _startRecording() async {
    try {
      final dir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final path = '${dir.path}/voice_$timestamp.m4a';

      await _recorderChannel.invokeMethod('startRecording', {'path': path});

      _recordingSeconds = 0;
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (mounted) setState(() => _recordingSeconds++);
      });

      if (mounted) setState(() => _isRecording = true);
    } catch (e) {
      debugPrint('[Recording] Start error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Recording failed: ${e.toString().replaceAll('PlatformException', '').replaceAll('(', '').replaceAll(')', '')}')),
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
          final name = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
          await _upload(file, name);
        }
      }
    } catch (e) {
      debugPrint('[Recording] Stop error: $e');
      if (mounted) setState(() => _isRecording = false);
    }
  }

  Future<void> _cancelRecording() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;

    try {
      await _recorderChannel.invokeMethod('cancelRecording');
    } catch (e) {
      debugPrint('[Recording] Cancel error: $e');
    }

    if (mounted) setState(() => _isRecording = false);
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── File Picking ──

  Future<void> _pickFile(String accept) async {
    try {
      final picker = ImagePicker();
      final acceptLower = accept.toLowerCase();
      
      if (acceptLower.contains('image')) {
        final src = await _srcDialog();
        if (src == null) return;
        if (src == ImageSource.camera) {
          final f = await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
          if (f != null) await _uploadXFile(f);
        } else {
          final fs = await picker.pickMultiImage(imageQuality: 80);
          for (final f in fs) { await _uploadXFile(f); }
        }
      } else if (acceptLower.contains('video')) {
        final src = await _videoSrcDialog();
        if (src == null) return;
        final f = await picker.pickVideo(source: src, maxDuration: const Duration(minutes: 5));
        if (f != null) await _uploadXFile(f);
      } else if (acceptLower.contains('audio')) {
        // For audio file inputs, trigger native recording
        await _showRecordingUI();
      } else {
        // Generic file - use FilePicker
        final r = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: false);
        if (r != null && r.files.isNotEmpty) {
          final pf = r.files.single;
          if (pf.path != null) {
            await _upload(File(pf.path!), pf.name);
          }
        }
      }
    } catch (e) {
      debugPrint('[PickFile] Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick file: ${e.toString().split('\n').first}')),
        );
      }
    }
  }

  Future<ImageSource?> _videoSrcDialog() => showDialog<ImageSource>(context: context, builder: (c) => AlertDialog(
    title: const Text('Select Video Source'), content: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.videocam), title: const Text('Record Video'), onTap: () => Navigator.pop(c, ImageSource.camera)),
      ListTile(leading: const Icon(Icons.video_library), title: const Text('Gallery'), onTap: () => Navigator.pop(c, ImageSource.gallery)),
    ])));

  /// Upload an XFile (from image_picker) - handles content URIs properly
  Future<void> _uploadXFile(XFile xfile) async {
    try {
      // Read the file bytes directly from XFile - this handles content URIs
      final bytes = await xfile.readAsBytes();
      if (bytes.isEmpty) return;
      
      String name = xfile.name.isNotEmpty ? xfile.name : 'file_${DateTime.now().millisecondsSinceEpoch}';
      
      // Ensure file has an extension (Android content URIs sometimes don't)
      if (!name.contains('.')) {
        final mimeType = xfile.mimeType ?? '';
        if (mimeType.contains('jpeg') || mimeType.contains('jpg')) name += '.jpg';
        else if (mimeType.contains('png')) name += '.png';
        else if (mimeType.contains('gif')) name += '.gif';
        else if (mimeType.contains('webp')) name += '.webp';
        else if (mimeType.contains('mp4')) name += '.mp4';
        else if (mimeType.contains('webm')) name += '.webm';
        else if (mimeType.contains('mov') || mimeType.contains('quicktime')) name += '.mov';
        else name += '.jpg'; // default to jpg for images
      }
      
      final tr = await _controller.runJavaScriptReturningResult('localStorage.getItem("sahjanand_token")');
      final token = tr.toString().replaceAll('"', '');
      if (token == 'null' || token.isEmpty) {
        debugPrint('[Upload] No auth token');
        return;
      }

      if (mounted) setState(() => _isUploading = true);

      final req = http.MultipartRequest('POST', Uri.parse('$kProductionUrl/api/chat/upload'))
        ..headers['Authorization'] = 'Bearer $token'
        ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: name));
      
      final res = await req.send();
      
      if (mounted) setState(() => _isUploading = false);
      
      if (res.statusCode == 200) {
        final body = jsonDecode(await res.stream.bytesToString());
        final url = body['url'] ?? body['media_url'] ?? '';
        if (url.toString().isNotEmpty) {
          _sendMediaMessage(url, name);
        }
      } else {
        final errBody = await res.stream.bytesToString();
        debugPrint('[Upload] Server returned ${res.statusCode}: $errBody');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Upload failed (${res.statusCode})')),
          );
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isUploading = false);
      debugPrint('[Upload XFile] Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload error: ${e.toString().split('\n').first}')),
        );
      }
    }
  }

  Future<ImageSource?> _srcDialog() => showDialog<ImageSource>(context: context, builder: (c) => AlertDialog(
    title: const Text('Select Source'), content: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.camera_alt), title: const Text('Camera'), onTap: () => Navigator.pop(c, ImageSource.camera)),
      ListTile(leading: const Icon(Icons.photo_library), title: const Text('Gallery'), onTap: () => Navigator.pop(c, ImageSource.gallery)),
    ])));

  Future<void> _upload(File file, String name) async {
    try {
      if (!await file.exists()) return;
      final fileSize = await file.length();
      if (fileSize == 0) return;

      final tr = await _controller.runJavaScriptReturningResult('localStorage.getItem("sahjanand_token")');
      final token = tr.toString().replaceAll('"', '');
      if (token == 'null' || token.isEmpty) return;

      if (mounted) setState(() => _isUploading = true);

      final req = http.MultipartRequest('POST', Uri.parse('$kProductionUrl/api/chat/upload'))
        ..headers['Authorization'] = 'Bearer $token'
        ..files.add(await http.MultipartFile.fromPath('file', file.path, filename: name));
      final res = await req.send();

      if (mounted) setState(() => _isUploading = false);

      if (res.statusCode == 200) {
        final body = jsonDecode(await res.stream.bytesToString());
        final url = body['url'] ?? body['media_url'] ?? '';
        if (url.toString().isNotEmpty) {
          _sendMediaMessage(url, name);
        }
      } else {
        debugPrint('[Upload] Server returned ${res.statusCode}');
      }
    } catch (e) {
      if (mounted) setState(() => _isUploading = false);
      debugPrint('[Upload] Error: $e');
    }
  }

  void _sendMediaMessage(String url, String name) {
    // Determine if this is an audio file
    final nameLower = name.toLowerCase();
    final isAudio = nameLower.endsWith('.m4a') || nameLower.endsWith('.mp3') || 
                    nameLower.endsWith('.ogg') || nameLower.endsWith('.wav') || 
                    nameLower.endsWith('.webm') || nameLower.endsWith('.aac');
    
    _controller.runJavaScript('''
(function(){
  var token=localStorage.getItem('sahjanand_token'),api=window.API||'';
  var fullUrl='$url';
  var fileName='$name';
  var isAudioFile=${isAudio ? 'true' : 'false'};

  // Determine which section is active
  var jcPanel=document.getElementById('jcFormPanel');
  var jcVisible=jcPanel&&jcPanel.style.display!=='none'&&jcPanel.offsetParent!==null;

  // If Job Card form is open AND it's not an audio file, set image there
  if(jcVisible&&!isAudioFile){
    var jcUrl=document.getElementById('jcImageUrl');
    if(jcUrl){jcUrl.value=fullUrl;}
    var jcPreview=document.getElementById('jcImagePreview');
    if(jcPreview){jcPreview.innerHTML='<img src="'+fullUrl+'" style="max-height:80px;border-radius:8px;" /> <span style="color:green;font-size:.75rem;">Uploaded</span>';}
    return;
  }

  // Set reminder media fields (for reminder forms if visible)
  var reminderForm=document.getElementById('reminderForm');
  var reminderVisible=reminderForm&&reminderForm.style.display!=='none';
  var rpForm=document.getElementById('rpFormPanel');
  var rpVisible=rpForm&&rpForm.style.display!=='none';

  if(reminderVisible){
    var x=document.getElementById('reminderMediaUrl');if(x)x.value=fullUrl;
    x=document.getElementById('reminderMediaName');if(x)x.value=fileName;
    x=document.getElementById('reminderMediaInfo');if(x)x.textContent=fileName;
    return;
  }
  if(rpVisible){
    var x=document.getElementById('rpMediaUrl');if(x)x.value=fullUrl;
    x=document.getElementById('rpMediaName');if(x)x.value=fileName;
    x=document.getElementById('rpMediaInfo');if(x)x.textContent=fileName;
    return;
  }

  // Default: send as chat message if in a group chat
  var gid=window.currentGroupId;
  if(!gid||!token)return;
  var ext=fileName.split('.').pop().toLowerCase();
  var t='image';
  if(['mp4','mov','webm','avi','3gp'].indexOf(ext)>=0)t='video';
  if(['mp3','ogg','wav','m4a','aac','amr','webm'].indexOf(ext)>=0)t='voice';
  if(isAudioFile)t='voice';
  fetch(api+'/api/chat/groups/'+gid+'/messages',{method:'POST',
    headers:{'Authorization':'Bearer '+token,'Content-Type':'application/json'},
    body:JSON.stringify({msg_type:t,media_url:fullUrl,media_name:fileName,content:''})
  }).then(function(){if(typeof refreshChatMessages==='function')refreshChatMessages();});
})();
    ''');
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.runJavaScript('if(typeof refreshChatMessages==="function")refreshChatMessages();if(typeof updateReminderNavBadge==="function")updateReminderNavBadge();');
    }
  }

  void _retry() { setState(() { _hasError = false; _isLoading = true; _retryCount = 0; }); _controller.loadRequest(Uri.parse(kProductionUrl)); }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return Scaffold(backgroundColor: const Color(0xFFFFF9F5), body: const Center(child: CircularProgressIndicator(color: Color(0xFFC8290C))));
    return WillPopScope(
      onWillPop: () async {
        if (_isRecording) { await _cancelRecording(); return false; }
        if (await _controller.canGoBack()) { await _controller.goBack(); return false; }
        return true;
      },
      child: Scaffold(backgroundColor: const Color(0xFFFFF9F5), body: SafeArea(child: Stack(children: [
        if (_hasError) Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.cloud_off_rounded, size: 64, color: Color(0xFFC8290C)), const SizedBox(height: 16),
          const Text('Could not connect', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 24),
          ElevatedButton(onPressed: _retry, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFC8290C), foregroundColor: Colors.white), child: const Text('Retry'))]))
        else WebViewWidget(controller: _controller),
        if (_isLoading) Container(color: const Color(0xFFFFF9F5), child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Image.asset('assets/icon.png', width: 100, height: 100, errorBuilder: (_, __, ___) => const Icon(Icons.business, size: 64, color: Color(0xFFC8290C))),
          const SizedBox(height: 24), const Text('Sahjanand', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFFC8290C))),
          const SizedBox(height: 16), const SizedBox(width: 32, height: 32, child: CircularProgressIndicator(color: Color(0xFFC8290C), strokeWidth: 3))]))),

        // Voice Recording Overlay (WhatsApp-style)
        if (_isRecording) _buildRecordingOverlay(),

        // Upload indicator
        if (_isUploading) _buildUploadIndicator(),
      ]))));
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
            // Cancel button
            GestureDetector(
              onTap: _cancelRecording,
              child: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: Colors.grey.shade200, shape: BoxShape.circle),
                child: const Icon(Icons.delete_outline, color: Colors.red, size: 24),
              ),
            ),
            const SizedBox(width: 12),
            // Recording indicator + timer
            Expanded(
              child: Row(children: [
                Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text('Recording ${_formatDuration(_recordingSeconds)}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.black87)),
              ]),
            ),
            // Send button
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
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFC8290C))),
            SizedBox(width: 12),
            Text('Uploading...', style: TextStyle(fontSize: 14, color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}
