
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile/firebase_options.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:camera/camera.dart';
import 'package:firebase_core/firebase_core.dart';
import 'services/websocket_client.dart';
import 'services/upload_service.dart';
import 'services/session_service.dart';
import 'bloc/sync_bloc.dart';
import 'bloc/operator/operator_bloc.dart';
import 'ui/operator_dashboard_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const PhotoBoothApp());
}

class PhotoBoothApp extends StatelessWidget {
  const PhotoBoothApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<SyncBloc>(create: (context) => SyncBloc(WebSocketClient())),
        BlocProvider<OperatorBloc>(create: (context) => OperatorBloc(WebSocketClient())),
      ],
      child: MaterialApp(
        title: 'Moment',
        theme: ThemeData.dark().copyWith(
          primaryColor: Colors.deepPurple,
          scaffoldBackgroundColor: const Color(0xFF121212),
          colorScheme: const ColorScheme.dark(
            primary: Colors.deepPurple,
            secondary: Colors.amber,
          ),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _cameraIndex = 1;
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraReady = false;
  bool _isInitializing = false;
  String _uploadStatus = 'Idle';

  @override
  void initState() {
    super.initState();
    _loadCachedCameraIndex();
  }

  Future<void> _loadCachedCameraIndex() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final index = prefs.getInt('camera_position_index');
      if (index != null && index >= 1 && index <= 10 && mounted) {
        setState(() {
          _cameraIndex = index;
        });
      }
    } catch (_) {
      // Ignore cache errors
    }
  }

  Future<void> _initCamera() async {
    if (_isInitializing) return;
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      return;
    }
    _isInitializing = true;
    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        // Use back camera (typically index 0)
        _cameraController = CameraController(
          _cameras![0],
          ResolutionPreset.medium,
          enableAudio: false,
        );
        await _cameraController!.initialize();
        if (mounted) {
          setState(() {
            _isCameraReady = true;
          });
        }
      }
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    } finally {
      _isInitializing = false;
    }
  }

  void _disposeCamera() {
    if (_cameraController != null) {
      _cameraController!.dispose();
      _cameraController = null;
      if (mounted) {
        setState(() {
          _isCameraReady = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }


  void _configureEmulators(String wsUrl) {
    if (kReleaseMode) return;
    
    final uri = Uri.parse(wsUrl.replaceFirst('ws://', 'http://'));
    final host = uri.host;
    // Configure Storage (9199) and Firestore (8082) emulators
    UploadService.configureEmulator(host, 9199);
    SessionService.configureEmulator(host, 8082);
  }

  Future<void> _handleCaptureTrigger(String sessionId, int cameraIndex, int expectedFrames) async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    setState(() {
      _uploadStatus = 'Capturing...';
    });
    context.read<SyncBloc>().add(SendStatusUpdateEvent(sessionId: sessionId, status: 'capturing'));

    try {
      // 1. Shutter capture & upload raw image
      final storagePath = await UploadService.takeAndUploadPicture(
        _cameraController!,
        sessionId,
        cameraIndex,
      );

      setState(() {
        _uploadStatus = 'Uploading Frame...';
      });
      context.read<SyncBloc>().add(SendStatusUpdateEvent(sessionId: sessionId, status: 'uploading'));

      // 2. Log frame path to Firestore session document
      await SessionService.updateFrameUpload(sessionId, cameraIndex, storagePath, expectedFrames);

      setState(() {
        _uploadStatus = 'Upload Success';
      });
      context.read<SyncBloc>().add(SendStatusUpdateEvent(sessionId: sessionId, status: 'uploaded'));
    } catch (e) {
      setState(() {
        _uploadStatus = 'Error: ${e.toString()}';
      });
      context.read<SyncBloc>().add(SendStatusUpdateEvent(sessionId: sessionId, status: 'failed', errorMessage: e.toString()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      appBar: isLandscape
          ? null
          : AppBar(
              title: const Text('Moment Camera Node'),
              backgroundColor: Colors.transparent,
              elevation: 0,
            ),
      body: BlocListener<SyncBloc, SyncState>(
        listener: (context, state) {
          if (state is SyncConnecting) {
            // Setup emulators dynamically based on coordinator IP
            _configureEmulators(state.url);
            _disposeCamera();
          } else if (state is SyncConnected) {
            _initCamera();
          } else if (state is SyncCaptureTriggered) {
            _handleCaptureTrigger(state.sessionId, state.cameraIndex, state.expectedFrames);
          } else if (state is SyncInitial || state is SyncError || state is SyncPairing) {
            _disposeCamera();
          }
        },

        child: BlocBuilder<SyncBloc, SyncState>(
          builder: (context, state) {
            if (state is SyncInitial) {
              return _buildSetupView();
            } else if (state is SyncPairing) {
              return _buildScannerView();
            } else if (state is SyncConnecting) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Connecting to Coordinator...', style: TextStyle(fontSize: 16)),
                  ],
                ),
              );
            } else if (state is SyncConnected) {
              return _buildConnectedView(state);
            } else if (state is SyncError) {
              return _buildErrorView(state.message);
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  Widget _buildSetupView() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Configure Camera Node',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 32),
          const Text(
            'Camera Position Index (1 - 10)',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            value: _cameraIndex,
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF1E1E1E),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            items: List.generate(10, (index) => index + 1).map((idx) {
              return DropdownMenuItem<int>(
                value: idx,
                child: Text('Camera Node $idx'),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) {
                setState(() {
                  _cameraIndex = val;
                });
                SharedPreferences.getInstance().then((prefs) {
                  prefs.setInt('camera_position_index', val);
                }).catchError((_) {});
              }
            },
          ),
          const SizedBox(height: 48),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              backgroundColor: Colors.deepPurple,
            ),
            icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
            label: const Text('Scan Coordinator QR', style: TextStyle(fontSize: 16, color: Colors.white)),
            onPressed: () {
              context.read<SyncBloc>().add(StartPairingEvent());
            },
          ),
          const SizedBox(height: 16),
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: Text(
              'Switch to Operator Mode',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade400,
                decoration: TextDecoration.underline,
              ),
            ),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const OperatorDashboardPage()),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildScannerView() {
    return Stack(
      children: [
        MobileScanner(
          onDetect: (capture) {
            final List<Barcode> barcodes = capture.barcodes;
            for (final barcode in barcodes) {
              if (barcode.rawValue != null) {
                final wsUrl = barcode.rawValue!;
                context.read<SyncBloc>().add(ConnectEvent(
                  wsUrl: wsUrl,
                  cameraIndex: _cameraIndex,
                ));
                break;
              }
            }
          },
        ),
        Positioned(
          top: 16,
          left: 16,
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              context.read<SyncBloc>().add(DisconnectEvent());
            },
          ),
        ),
        const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.crop_free, size: 280, color: Colors.white54),
              SizedBox(height: 16),
              Text(
                'Align the Coordinator QR Code',
                style: TextStyle(fontSize: 16, color: Colors.white70, backgroundColor: Colors.black54),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildConnectedView(SyncConnected state) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.deepPurple, width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: _isCameraReady && _cameraController != null
                    ? LayoutBuilder(
                        builder: (context, constraints) {
                          final size = _cameraController!.value.previewSize;
                          if (size == null) {
                            return CameraPreview(_cameraController!);
                          }
                          final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
                          final double previewWidth = isPortrait ? size.height : size.width;
                          final double previewHeight = isPortrait ? size.width : size.height;

                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              FittedBox(
                                fit: BoxFit.cover,
                                child: SizedBox(
                                  width: previewWidth,
                                  height: previewHeight,
                                  child: CameraPreview(_cameraController!),
                                ),
                              ),
                              CustomPaint(
                                painter: CameraOverlayPainter(isPortrait: isPortrait),
                                child: Container(),
                              ),
                              Center(
                                child: Icon(
                                  Icons.center_focus_weak_rounded,
                                  size: 64,
                                  color: Colors.white.withOpacity(0.4),
                                ),
                              ),
                            ],
                          );
                        },
                      )
                    : const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('Initializing Camera Hardware...'),
                          ],
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Node ${state.cameraIndex} Status: Ready',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Drift: ${state.clockOffsetMs} ms | Upload: $_uploadStatus',
                    style: const TextStyle(fontSize: 12, color: Colors.amber),
                  ),
                ],
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                child: const Text('Disconnect', style: TextStyle(color: Colors.white)),
                onPressed: () {
                  context.read<SyncBloc>().add(DisconnectEvent());
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 80, color: Colors.redAccent),
            const SizedBox(height: 24),
            const Text(
              'Connection Error',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 48),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Back to Setup'),
              onPressed: () {
                context.read<SyncBloc>().add(DisconnectEvent());
              },
            ),
          ],
        ),
      ),
    );
  }
}

class CameraOverlayPainter extends CustomPainter {
  final bool isPortrait;

  CameraOverlayPainter({required this.isPortrait});

  @override
  void paint(Canvas canvas, Size size) {
    final double targetAspect = isPortrait ? 9.0 / 16.0 : 16.0 / 9.0;
    
    // Calculate active crop area rect centered inside the canvas size
    double rectWidth;
    double rectHeight;
    final double canvasAspect = size.width / size.height;
    
    if (canvasAspect > targetAspect) {
      rectHeight = size.height;
      rectWidth = size.height * targetAspect;
    } else {
      rectWidth = size.width;
      rectHeight = size.width / targetAspect;
    }
    
    final double left = (size.width - rectWidth) / 2;
    final double top = (size.height - rectHeight) / 2;
    final Rect activeRect = Rect.fromLTWH(left, top, rectWidth, rectHeight);
    
    // Create outer bounds path
    final Path outerPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    // Create inner active path
    final Path innerPath = Path()..addRect(activeRect);
    
    // Subtract inner path from outer path to get the shade region
    final Path shadePath = Path.combine(PathOperation.difference, outerPath, innerPath);
    
    // Paint the translucent shade
    final Paint shadePaint = Paint()
      ..color = Colors.black.withOpacity(0.5)
      ..style = PaintingStyle.fill;
    canvas.drawPath(shadePath, shadePaint);
    
    // Paint the active area thin guide border
    final Paint borderPaint = Paint()
      ..color = Colors.purpleAccent
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawRect(activeRect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CameraOverlayPainter oldDelegate) {
    return oldDelegate.isPortrait != isPortrait;
  }
}
