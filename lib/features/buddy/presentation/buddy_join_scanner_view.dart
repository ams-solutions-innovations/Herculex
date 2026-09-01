import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/features/buddy/application/buddy_providers.dart';
import 'package:herculex/features/buddy/domain/buddy_join_payload.dart';
import 'package:herculex/theme/colors.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

/// Camera scanner screen for joining a Gym Buddy workout via QR code.
class BuddyJoinScannerView extends ConsumerStatefulWidget {
  const BuddyJoinScannerView({super.key});

  @override
  ConsumerState<BuddyJoinScannerView> createState() =>
      _BuddyJoinScannerViewState();
}

class _BuddyJoinScannerViewState extends ConsumerState<BuddyJoinScannerView>
    with WidgetsBindingObserver {
  MobileScannerController? _controller;
  PermissionStatus? _permissionStatus;
  bool _isProcessing = false;
  String? _statusMessage;
  bool _isErrorMessage = false;

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
      formats: const [BarcodeFormat.qrCode],
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
    if (_isProcessing || !mounted) return;

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.trim().isEmpty) continue;

      final payload = BuddyJoinPayload.tryDecode(raw);
      if (payload == null) {
        setState(() {
          _statusMessage = 'Not a Gym Buddy QR code. Keep scanning...';
          _isErrorMessage = true;
        });
        return;
      }

      setState(() {
        _isProcessing = true;
        _statusMessage = 'Joining workout session...';
        _isErrorMessage = false;
      });

      try {
        await ref
            .read(buddySessionControllerProvider.notifier)
            .joinFromScan(raw);

        if (mounted) {
          Navigator.of(context).pop();
        }
        return;
      } catch (e) {
        if (mounted) {
          setState(() {
            _isProcessing = false;
            _statusMessage = 'Invalid or expired join code. Please try again.';
            _isErrorMessage = true;
          });
        }
        return;
      }
    }
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
      return _buildPermissionView(context);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          'Join Gym Buddy',
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
        ],
      ),
      body: Stack(
        children: [
          if (_controller != null)
            MobileScanner(controller: _controller!, onDetect: _onDetect),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primary, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isProcessing)
                  CircularProgressIndicator(color: AppColors.primary)
                else
                  Text(
                    _statusMessage ?? 'Point camera at host\'s QR code',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _isErrorMessage
                          ? Colors.redAccent
                          : Colors.white70,
                      fontWeight: _isErrorMessage
                          ? FontWeight.bold
                          : FontWeight.normal,
                      fontSize: 15,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionView(BuildContext context) {
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
              const Icon(
                Icons.qr_code_scanner_rounded,
                size: 80,
                color: Colors.white,
              ),
              const SizedBox(height: 32),
              const Text(
                'CAMERA PERMISSION NEEDED',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Herculex needs camera access to scan your gym buddy\'s QR code and sync your live workout choreography.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _requestPermission,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                ),
                child: const Text('GRANT CAMERA ACCESS'),
              ),
              if (_permissionStatus!.isPermanentlyDenied) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: openAppSettings,
                  child: const Text(
                    'OPEN APP SETTINGS',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
