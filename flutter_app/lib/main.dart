import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

const String kProductionUrl = 'https://sahjanand-api.onrender.com';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    await [Permission.camera, Permission.microphone, Permission.storage, Permission.notification].request();
    if (Platform.isAndroid) { await Permission.photos.request(); await Permission.videos.request(); }
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
  document.addEventListener('click',function(e){
    var t=e.target;
    if(t.tagName==='INPUT'&&t.type==='file'){e.preventDefault();e.stopPropagation();
      FlutterBridge.postMessage(JSON.stringify({action:'pickFile',accept:t.accept||'*/*'}));return false;}
  },true);
  if(navigator.mediaDevices){
    var orig=navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices);
    navigator.mediaDevices.getUserMedia=function(c){
      if(c&&c.audio&&!c.video){FlutterBridge.postMessage(JSON.stringify({action:'pickAudio'}));
        return Promise.reject(new DOMException('native','NotAllowedError'));}
      return orig(c);
    };
  }
})();
    ''');
  }

  void _onBridgeMessage(JavaScriptMessage msg) async {
    try {
      final d = jsonDecode(msg.message);
      if (d['action'] == 'pickFile') await _pickFile(d['accept'] ?? '*/*');
      else if (d['action'] == 'pickAudio') await _pickAudio();
    } catch (e) { debugPrint('[Bridge] $e'); }
  }

  Future<void> _pickFile(String accept) async {
    final picker = ImagePicker();
    if (accept.contains('image')) {
      final src = await _srcDialog();
      if (src == null) return;
      if (src == ImageSource.camera) {
        final f = await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
        if (f != null) await _upload(File(f.path), f.name);
      } else {
        final fs = await picker.pickMultiImage(imageQuality: 80);
        for (final f in fs) { await _upload(File(f.path), f.name); }
      }
    } else if (accept.contains('video')) {
      final f = await picker.pickVideo(source: ImageSource.gallery);
      if (f != null) await _upload(File(f.path), f.name);
    } else {
      final r = await FilePicker.platform.pickFiles(type: FileType.any);
      if (r != null && r.files.isNotEmpty) await _upload(File(r.files.single.path!), r.files.single.name);
    }
  }

  Future<void> _pickAudio() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.audio);
    if (r != null && r.files.isNotEmpty) await _upload(File(r.files.single.path!), r.files.single.name);
  }

  Future<ImageSource?> _srcDialog() => showDialog<ImageSource>(context: context, builder: (c) => AlertDialog(
    title: const Text('Select'), content: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.camera_alt), title: const Text('Camera'), onTap: () => Navigator.pop(c, ImageSource.camera)),
      ListTile(leading: const Icon(Icons.photo_library), title: const Text('Gallery'), onTap: () => Navigator.pop(c, ImageSource.gallery)),
    ])));

  Future<void> _upload(File file, String name) async {
    try {
      final tr = await _controller.runJavaScriptReturningResult('localStorage.getItem("sahjanand_token")');
      final token = tr.toString().replaceAll('"', '');
      if (token == 'null' || token.isEmpty) return;
      final req = http.MultipartRequest('POST', Uri.parse('$kProductionUrl/api/chat/upload'))
        ..headers['Authorization'] = 'Bearer $token'
        ..files.add(await http.MultipartFile.fromPath('file', file.path, filename: name));
      final res = await req.send();
      if (res.statusCode == 200) {
        final body = jsonDecode(await res.stream.bytesToString());
        final url = body['url'] ?? body['media_url'] ?? '';
        _controller.runJavaScript('''
(function(){
  var token=localStorage.getItem('sahjanand_token'),gid=window.currentGroupId,api=window.API||'';
  if(!gid||!token)return;
  var ext='$name'.split('.').pop().toLowerCase();
  var t='image';if(['mp4','mov','webm','avi'].indexOf(ext)>=0)t='video';
  if(['mp3','ogg','wav','m4a','webm','aac'].indexOf(ext)>=0)t='voice';
  fetch(api+'/api/chat/groups/'+gid+'/messages',{method:'POST',
    headers:{'Authorization':'Bearer '+token,'Content-Type':'application/json'},
    body:JSON.stringify({msg_type:t,media_url:'$url',media_name:'$name',content:''})
  }).then(function(){if(typeof refreshChatMessages==='function')refreshChatMessages();});
  var x=document.getElementById('reminderMediaUrl');if(x)x.value='$url';
  x=document.getElementById('reminderMediaName');if(x)x.value='$name';
  x=document.getElementById('reminderMediaInfo');if(x)x.textContent='$name';
  x=document.getElementById('rpMediaUrl');if(x)x.value='$url';
  x=document.getElementById('rpMediaName');if(x)x.value='$name';
  x=document.getElementById('rpMediaInfo');if(x)x.textContent='$name';
})();
        ''');
      }
    } catch (e) { debugPrint('[Upload] $e'); }
  }

  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); super.dispose(); }

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
      onWillPop: () async { if (await _controller.canGoBack()) { await _controller.goBack(); return false; } return true; },
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
      ]))));
  }
}
