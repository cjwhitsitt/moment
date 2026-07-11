import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../bloc/operator/operator_bloc.dart';

class OperatorDashboardPage extends StatefulWidget {
  const OperatorDashboardPage({super.key});

  @override
  State<OperatorDashboardPage> createState() => _OperatorDashboardPageState();
}

class _OperatorDashboardPageState extends State<OperatorDashboardPage> {
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  bool _isSendingEmail = false;
  String _emailStatus = ''; // '', 'success', 'error'
  bool _hasAutoOpenedPairing = false;

  @override
  void initState() {
    super.initState();
    _loadCachedIp();
    context.read<OperatorBloc>().add(StartDiscoveryEvent());
  }

  Future<void> _loadCachedIp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedIp = prefs.getString('last_connected_ip');
      if (cachedIp != null && mounted) {
        _ipController.text = cachedIp;
      }
    } catch (_) {
      // Gracefully ignore local persistence load errors
    }
  }

  @override
  void dispose() {
    _ipController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendEmail(String sessionId, String gifUrl) async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;

    setState(() {
      _isSendingEmail = true;
      _emailStatus = '';
    });

    try {
      final callable = FirebaseFunctions.instance.httpsCallable('sendGifEmail');
      await callable.call({
        'sessionId': sessionId,
        'email': email,
        'gifUrl': gifUrl,
      });

      setState(() {
        _isSendingEmail = false;
        _emailStatus = 'success';
        _emailController.clear();
      });
    } catch (e) {
      setState(() {
        _isSendingEmail = false;
        _emailStatus = 'error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0B14),
      appBar: AppBar(
        title: const Text(
          'OPERATOR DASHBOARD',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 2.0,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () {
            context.read<OperatorBloc>().add(DisconnectOperatorEvent());
            Navigator.of(context).pop();
          },
        ),
      ),
      body: BlocConsumer<OperatorBloc, OperatorState>(
        listener: (context, state) {
          if (state is OperatorError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message), backgroundColor: Colors.redAccent),
            );
          } else if (state is OperatorConnected) {
            if (state.hasSynced && state.cameras.isEmpty && !_hasAutoOpenedPairing) {
              _hasAutoOpenedPairing = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _showPairingQrDialog(context, state.url);
              });
            }
          }
        },
        builder: (context, state) {
          if (state is OperatorInitial) {
            return _buildDiscoveringView(context);
          } else if (state is OperatorDiscovering) {
            return _buildDiscoveringView(context);
          } else if (state is OperatorDiscovered) {
            return _buildDiscoveredConfirmationView(context, state);
          } else if (state is OperatorConnecting) {
            return _buildConnectingView(state.url);
          } else if (state is OperatorConnected) {
            return _buildConnectedView(context, state);
          } else if (state is OperatorError) {
            return _buildErrorView(context, state.message);
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }



  Widget _buildDiscoveringView(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: CircularProgressIndicator(
                    strokeWidth: 5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.deepPurpleAccent),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Searching for Coordinator...',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                'Scanning subnet using mDNS...',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
              ),
              const SizedBox(height: 40),
              Row(
                children: [
                  Expanded(child: Divider(color: Colors.grey.shade800)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text('OR CONNECT MANUALLY', style: TextStyle(fontSize: 10, color: Colors.grey.shade600, letterSpacing: 1.5)),
                  ),
                  Expanded(child: Divider(color: Colors.grey.shade800)),
                ],
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _ipController,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Coordinator IP (e.g. 192.168.1.100)',
                  labelStyle: TextStyle(color: Colors.grey.shade500),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.04),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
                  ),
                ),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  backgroundColor: Colors.deepPurpleAccent,
                ),
                child: const Text('Connect Manually', style: TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.bold)),
                onPressed: () {
                  final ip = _ipController.text.trim();
                  if (ip.isNotEmpty) {
                    final url = ip.startsWith('ws://') ? ip : 'ws://$ip:8080/ws';
                    context.read<OperatorBloc>().add(ConnectManualEvent(url));
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDiscoveredConfirmationView(BuildContext context, OperatorDiscovered state) {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.check_circle_outline_rounded, size: 80, color: Colors.greenAccent),
              const SizedBox(height: 24),
              const Text(
                'Coordinator Found',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 12),
              Text(
                'A coordinator was auto-discovered at:',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Text(
                  state.host,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.greenAccent, letterSpacing: 1.0),
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'Connect to Discovered Coordinator?',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white70),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  backgroundColor: Colors.deepPurpleAccent,
                ),
                child: const Text('Yes, Connect', style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
                onPressed: () {
                  context.read<OperatorBloc>().add(ConnectManualEvent(state.url));
                },
              ),
              const SizedBox(height: 12),
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Keep Searching / Reject', style: TextStyle(fontSize: 15, color: Colors.grey.shade400)),
                onPressed: () {
                  context.read<OperatorBloc>().add(IgnoreDiscoveredEvent());
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectingView(String url) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text('Connecting to $url...', style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _buildErrorView(BuildContext context, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, size: 80, color: Colors.redAccent),
            const SizedBox(height: 24),
            const Text('Connection Failed', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade400)),
            const SizedBox(height: 32),
            ElevatedButton(
              child: const Text('Back to Setup'),
              onPressed: () {
                context.read<OperatorBloc>().add(DisconnectOperatorEvent());
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectedView(BuildContext context, OperatorConnected state) {
    final activeCams = state.cameras;
    final readyCount = activeCams.where((c) => c.isReady).length;
    final isTriggerable = readyCount >= 3 && readyCount <= 10;

    final isSessionDone = state.activeSession != null && state.activeSession!.status == 'done';

    if (isSessionDone) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey.shade400,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  icon: const Icon(Icons.close_rounded, size: 20),
                  label: const Text('Back to Dashboard', style: TextStyle(fontSize: 14)),
                  onPressed: () {
                    context.read<OperatorBloc>().add(ClearActiveSessionEvent());
                  },
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _buildShareSection(state.activeSession!.sessionId, state.url),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Master Trigger Button
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: Colors.white.withOpacity(0.04),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Column(
                children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      backgroundColor: isTriggerable ? Colors.redAccent : Colors.grey.shade800,
                      shadowColor: isTriggerable ? Colors.redAccent.withOpacity(0.5) : Colors.transparent,
                      elevation: isTriggerable ? 16 : 0,
                    ),
                    onPressed: isTriggerable
                        ? () {
                            context.read<OperatorBloc>().add(TriggerCaptureEvent());
                          }
                        : null,
                    child: const Text(
                      'TRIGGER CAPTURE',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 1.5, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          isTriggerable
                              ? 'System Ready: $readyCount Camera Nodes Paired'
                              : 'System Inactive: $readyCount camera nodes paired (3-10 required)',
                          style: TextStyle(
                            fontSize: 14,
                            color: isTriggerable ? Colors.greenAccent : Colors.amberAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.purpleAccent, size: 24),
                        tooltip: 'Add Camera Node',
                        onPressed: () => _showPairingQrDialog(context, state.url),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // System Status Grid
            const Text(
              'CAMERA NODE STATUS',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.15,
              ),
              itemCount: 10,
              itemBuilder: (context, index) {
                final nodeIdx = index + 1;
                final match = activeCams.where((c) => c.cameraIndex == nodeIdx);
                final CameraNodeStatus? camNode = match.isNotEmpty ? match.first : null;
                return _buildCameraNodeCard(nodeIdx, camNode);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraNodeCard(int index, CameraNodeStatus? node) {
    final isOnline = node != null;
    Color statusColor = Colors.grey;
    String statusText = 'Offline';

    if (isOnline) {
      switch (node.state) {
        case 'idle':
          statusColor = Colors.greenAccent;
          statusText = 'Idle';
          break;
        case 'capturing':
          statusColor = Colors.amberAccent;
          statusText = 'Capturing';
          break;
        case 'uploading':
          statusColor = Colors.blueAccent;
          statusText = 'Uploading';
          break;
        case 'uploaded':
          statusColor = Colors.purpleAccent;
          statusText = 'Uploaded';
          break;
        case 'failed':
          statusColor = Colors.redAccent;
          statusText = 'Error';
          break;
      }
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isOnline ? Colors.white.withOpacity(0.06) : Colors.white.withOpacity(0.01),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isOnline
              ? statusColor.withOpacity(0.2)
              : Colors.white.withOpacity(0.03),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'CAM $index',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isOnline ? Colors.white : Colors.grey.shade700,
                ),
              ),
              if (isOnline)
                Row(
                  children: [
                    Icon(
                      node.batteryLevel < 0
                          ? Icons.battery_unknown_rounded
                          : (node.batteryLevel > 20 ? Icons.battery_charging_full_rounded : Icons.battery_alert_rounded),
                      size: 14,
                      color: node.batteryLevel < 0
                          ? Colors.grey
                          : (node.batteryLevel > 20 ? Colors.green : Colors.red),
                    ),
                    const SizedBox(width: 2),
                    Text(
                      node.batteryLevel < 0 ? '-' : '${node.batteryLevel}%',
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                statusText,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: statusColor,
                ),
              ),
              if (isOnline) ...[
                const SizedBox(height: 4),
                Text(
                  'Offset: ${node.clockOffsetMs.toStringAsFixed(1)} ms',
                  style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildShareSection(String sessionId, String wsUrl) {
    String host = 'localhost';
    try {
      final uri = Uri.parse(wsUrl);
      host = uri.host;
    } catch (_) {}

    final bool isLocal = host == 'localhost' ||
        host == '127.0.0.1' ||
        host.startsWith('192.168.') ||
        host.startsWith('10.') ||
        host.startsWith('172.');

    final gifUrl = isLocal
        ? 'http://$host:9199/v0/b/moment-aad8b.firebasestorage.app/o/stitched%2F$sessionId.gif?alt=media'
        : 'https://firebasestorage.googleapis.com/v0/b/moment-aad8b.firebasestorage.app/o/stitched%2F$sessionId.gif?alt=media';

    final hostingBaseUrl = isLocal
        ? 'http://$host:5000'
        : 'https://moment-aad8b.web.app';
    final shareLandingPageUrl = '$hostingBaseUrl/?gif=${Uri.encodeComponent(gifUrl)}';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF1E153A), Color(0xFF120E26)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border.all(color: Colors.deepPurpleAccent.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'STITCHED LOOPING GIF READY',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2.0, color: Colors.purpleAccent),
          ),
          const SizedBox(height: 12),

          // Full-width looping GIF preview
          Expanded(
            child: Center(
              child: GestureDetector(
                onTap: () => _showZoomDialog(
                  context,
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.network(gifUrl, fit: BoxFit.contain),
                  ),
                ),
                child: AdaptiveImagePreview(url: gifUrl),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Divider(color: Colors.white.withOpacity(0.06)),
          const SizedBox(height: 16),

          // Sharing options stacked cleanly below
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sharing QR code
              Expanded(
                flex: 2,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () => _showZoomDialog(
                        context,
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: QrImageView(
                            data: shareLandingPageUrl,
                            version: QrVersions.auto,
                            size: MediaQuery.of(context).size.width * 0.7,
                            eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
                            dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
                          ),
                        ),
                      ),
                      child: QrImageView(
                        data: shareLandingPageUrl,
                        version: QrVersions.auto,
                        size: 120,
                        eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.white),
                        dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Scan to download/share',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),

              // Email delivery input
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Deliver GIF to Guest Email',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _emailController,
                            decoration: InputDecoration(
                              hintText: 'guest@example.com',
                              hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.04),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: Colors.white.withOpacity(0.05)),
                              ),
                            ),
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            keyboardType: TextInputType.emailAddress,
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 40,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurpleAccent,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                            ),
                            onPressed: _isSendingEmail
                                ? null
                                : () => _sendEmail(sessionId, gifUrl),
                            child: _isSendingEmail
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                  )
                                : const Text('Send', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                          ),
                        ),
                      ],
                    ),
                    if (_emailStatus == 'success') ...[
                      const SizedBox(height: 8),
                      const Row(
                        children: [
                          Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 14),
                          SizedBox(width: 4),
                          Expanded(
                            child: Text('Email shared successfully!', style: TextStyle(color: Colors.greenAccent, fontSize: 11)),
                          ),
                        ],
                      ),
                    ] else if (_emailStatus == 'error') ...[
                      const SizedBox(height: 8),
                      const Row(
                        children: [
                          Icon(Icons.error_rounded, color: Colors.redAccent, size: 14),
                          SizedBox(width: 4),
                          Expanded(
                            child: Text('Failed to share email.', style: TextStyle(color: Colors.redAccent, fontSize: 11)),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showZoomDialog(BuildContext context, Widget child) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.9),
      builder: (context) => GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Material(
          color: Colors.transparent,
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.all(24.0),
            child: InteractiveViewer(
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  void _showPairingQrDialog(BuildContext context, String wsUrl) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.95),
      builder: (context) => GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Material(
          color: Colors.transparent,
          child: Center(
            child: GestureDetector(
              onTap: () {}, // Prevent dismissal on tapping the card itself
              child: Container(
                width: 320,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E153A),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.deepPurpleAccent.withOpacity(0.2)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'PAIRING CLIENTS',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                            color: Colors.purpleAccent,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.grey, size: 20),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: QrImageView(
                        data: wsUrl,
                        version: QrVersions.auto,
                        size: 200,
                        eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
                        dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Scan with Camera nodes to connect',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      wsUrl,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade400, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AdaptiveImagePreview extends StatefulWidget {
  final String url;

  const AdaptiveImagePreview({required this.url, super.key});

  @override
  State<AdaptiveImagePreview> createState() => _AdaptiveImagePreviewState();
}

class _AdaptiveImagePreviewState extends State<AdaptiveImagePreview> {
  double _aspectRatio = 16 / 9;

  @override
  void initState() {
    super.initState();
    _resolveImage();
  }

  @override
  void didUpdateWidget(AdaptiveImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _resolveImage();
    }
  }

  void _resolveImage() {
    final Image image = Image.network(widget.url);
    image.image.resolve(const ImageConfiguration()).addListener(
      ImageStreamListener(
        (ImageInfo info, bool _) {
          if (mounted) {
            setState(() {
              _aspectRatio = info.image.width / info.image.height;
            });
          }
        },
        onError: (_, __) {},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: _aspectRatio,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.network(
            widget.url,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return const Center(child: Icon(Icons.broken_image_outlined, color: Colors.grey, size: 48));
            },
          ),
        ),
      ),
    );
  }
}
