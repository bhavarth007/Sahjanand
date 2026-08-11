import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() { _isLoading = true; _hasError = false; });
          },
          onPageFinished: (_) {
            if (mounted) setState(() { _isLoading = false; _retryCount = 0; });
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

    // Enable file upload and media permissions on Android
    final androidController = _controller.platform;
    if (androidController is AndroidWebViewController) {
      androidController.setMediaPlaybackRequiresUserGesture(false);
      androidController.setOnShowFileSelector((params) async {
        return [];
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // When app comes back from background, refresh the page to get latest messages
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Run JS to trigger chat refresh instead of full page reload
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
            const SizedBox(height: 12),
            Text(
              _retryCount > 0 ? 'Server is waking up... ($_retryCount/3)' : 'Loading...',
              style: const TextStyle(fontSize: 13, color: Color(0xFF6B5E54)),
            ),
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
          const Text('Could not connect to server', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Please check your internet\nor try again in a moment.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF6B5E54))),
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
