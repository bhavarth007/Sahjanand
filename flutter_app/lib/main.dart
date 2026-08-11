import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

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

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() { _isLoading = true; _hasError = false; }),
          onPageFinished: (_) => setState(() => _isLoading = false),
          onWebResourceError: (_) => setState(() { _hasError = true; _isLoading = false; }),
        ),
      )
      ..loadRequest(Uri.parse(kProductionUrl));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop && await _controller.canGoBack()) {
          await _controller.goBack();
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              if (_hasError)
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.wifi_off_rounded, size: 64, color: Color(0xFFC8290C)),
                      const SizedBox(height: 16),
                      const Text('No Internet Connection', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () => _controller.loadRequest(Uri.parse(kProductionUrl)),
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFC8290C), foregroundColor: Colors.white),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              else
                WebViewWidget(controller: _controller),
              if (_isLoading)
                const LinearProgressIndicator(color: Color(0xFFC8290C)),
            ],
          ),
        ),
      ),
    );
  }
}
