import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../theme/colors.dart';

/// Returns the first detected barcode string (or null if user cancels).
class BarcodeScannerView extends StatefulWidget {
  const BarcodeScannerView({super.key});

  static Future<String?> show(BuildContext context) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerView()),
    );
  }

  @override
  State<BarcodeScannerView> createState() => _BarcodeScannerViewState();
}

class _BarcodeScannerViewState extends State<BarcodeScannerView>
    with WidgetsBindingObserver {
  MobileScannerController? _controller;
  PermissionStatus? _permissionStatus;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final status = await Permission.camera.status;
    if (mounted) {
      setState(() {
        _permissionStatus = status;
      });
      if (status.isGranted) {
        _initController();
      }
    }
  }

  void _initController() {
    _controller ??= MobileScannerController(
      autoStart: true,
      detectionSpeed: DetectionSpeed.normal,
      formats: const [
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,
        BarcodeFormat.code128,
      ],
    );
  }

  Future<void> _requestPermission() async {
    final status = await Permission.camera.request();
    if (!mounted) return;
    setState(() {
      _permissionStatus = status;
    });
    if (status.isGranted) {
      _initController();
    } else if (status.isPermanentlyDenied) {
      openAppSettings();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final controller = _controller;
    _controller = null;
    controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    switch (state) {
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        if (controller.value.isRunning) {
          controller.stop();
        }
        break;
      case AppLifecycleState.resumed:
        if (!controller.value.isRunning &&
            _permissionStatus?.isGranted == true) {
          controller.start();
        }
        break;
    }
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled || !mounted) return;
    for (final b in capture.barcodes) {
      final v = b.rawValue;
      if (v != null && v.isNotEmpty) {
        _handled = true;
        if (mounted) {
          Navigator.of(context).pop(v);
        }
        return;
      }
    }
  }

  Future<void> _enterManually() async {
    final controller = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enter barcode'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            hintText: 'EAN-13, UPC-A, EAN-8 or GTIN-14',
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Use code'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (raw != null && mounted) Navigator.of(context).pop(raw);
  }

  @override
  Widget build(BuildContext context) {
    if (_permissionStatus == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_permissionStatus!.isGranted) {
      return _buildLoudPermissionView(context);
    }

    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          'Scan barcode',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        actions: [
          if (_controller != null)
            ValueListenableBuilder<MobileScannerState>(
              valueListenable: _controller!,
              builder: (context, state, child) {
                if (!state.isInitialized || !state.isRunning) {
                  return const SizedBox.shrink();
                }
                final isTorchOn = state.torchState == TorchState.on;
                return IconButton(
                  icon: Icon(
                    isTorchOn ? Icons.flash_on : Icons.flash_off,
                    color: isTorchOn ? Colors.amber : Colors.white,
                  ),
                  onPressed: () {
                    if (_controller?.value.isInitialized == true) {
                      _controller?.toggleTorch();
                    }
                  },
                );
              },
            ),
          if (_controller != null)
            ValueListenableBuilder<MobileScannerState>(
              valueListenable: _controller!,
              builder: (context, state, child) {
                if (!state.isInitialized || !state.isRunning) {
                  return const SizedBox.shrink();
                }
                return IconButton(
                  icon: const Icon(Icons.cameraswitch, color: Colors.white),
                  onPressed: () {
                    if (_controller?.value.isInitialized == true) {
                      _controller?.switchCamera();
                    }
                  },
                );
              },
            ),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_controller == null) {
      return Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    return Stack(
      children: [
        MobileScanner(
          controller: _controller!,
          onDetect: _onDetect,
          errorBuilder: (context, error) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.videocam_off_outlined,
                      size: 48,
                      color: Colors.amberAccent,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Camera unavailable (${error.errorCode.name})',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Please ensure no other application is using your camera.',
                      style: TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        Center(
          child: Container(
            width: 260,
            height: 160,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.primary, width: 3),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const Positioned(
          left: 0,
          right: 0,
          bottom: 32,
          child: Text(
            'Hold the barcode steady inside the frame',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 72,
          child: Center(
            child: TextButton.icon(
              onPressed: _enterManually,
              icon: const Icon(Icons.keyboard, color: Colors.white),
              label: const Text(
                'Enter barcode manually',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
  Widget _buildLoudPermissionView(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              const Icon(Icons.camera_alt_rounded, size: 80, color: Colors.white),
              const SizedBox(height: 32),
              const Text(
                'WE NEED YOUR CAMERA',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Herculex uses your camera exclusively to scan food barcodes so you can quickly log your meals.\n\nWe NEVER record video, take photos silently, or save any imagery from the camera. The stream is processed locally on your device to find a barcode and is immediately discarded.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  height: 1.5,
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _requestPermission,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                child: const Text('GRANT CAMERA PERMISSION'),
              ),
              if (_permissionStatus!.isPermanentlyDenied) ...[
                const SizedBox(height: 16),
                TextButton(
                  onPressed: openAppSettings,
                  child: const Text('OPEN SETTINGS', style: TextStyle(color: Colors.white54, letterSpacing: 1.5)),
                )
              ]
            ],
          ),
        ),
      ),
    );
  }
}
