import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:cloud_functions/cloud_functions.dart';
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
          }
        },
        builder: (context, state) {
          if (state is OperatorInitial) {
            return _buildInitialView(context);
          } else if (state is OperatorDiscovering) {
            return _buildDiscoveringView(context);
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

  Widget _buildInitialView(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.settings_input_antenna_rounded, size: 80, color: Colors.deepPurpleAccent),
              const SizedBox(height: 24),
              const Text(
                'Connect to Go Coordinator',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 12),
              Text(
                'Auto-discover the coordinator on the local subnet or enter its IP address manually.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade400, height: 1.4),
              ),
              const SizedBox(height: 40),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  backgroundColor: Colors.deepPurple,
                ),
                icon: const Icon(Icons.youtube_searched_for_rounded, color: Colors.white),
                label: const Text('Start Auto-Discovery', style: TextStyle(fontSize: 16, color: Colors.white)),
                onPressed: () {
                  context.read<OperatorBloc>().add(StartDiscoveryEvent());
                },
              ),
              const SizedBox(height: 32),
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
              const SizedBox(height: 32),
              TextField(
                controller: _ipController,
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
                  backgroundColor: Colors.white.withOpacity(0.08),
                  side: BorderSide(color: Colors.white.withOpacity(0.12)),
                ),
                child: const Text('Connect Manually', style: TextStyle(fontSize: 16, color: Colors.white)),
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

  Widget _buildDiscoveringView(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 80,
              height: 80,
              child: CircularProgressIndicator(
                strokeWidth: 6,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.deepPurpleAccent),
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'Searching for Coordinator...',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 12),
            Text(
              'Scanning subnet using mDNS...',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
            ),
            const SizedBox(height: 48),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white.withOpacity(0.08),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Cancel & Enter IP'),
              onPressed: () {
                context.read<OperatorBloc>().add(DisconnectOperatorEvent());
              },
            ),
          ],
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
                  Text(
                    isTriggerable
                        ? 'System Ready: $readyCount Camera Nodes Paired'
                        : 'System Inactive: $readyCount camera nodes paired (minimum 3, maximum 10 required)',
                    style: TextStyle(
                      fontSize: 14,
                      color: isTriggerable ? Colors.greenAccent : Colors.amberAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Share section if session active/complete
            if (state.activeSession != null && state.activeSession!.status == 'done') ...[
              _buildShareSection(state.activeSession!.sessionId),
              const SizedBox(height: 24),
            ],

            // System Status / Pairing Info
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Camera Status Grid
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'CAMERA NODE STATUS',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: Colors.grey),
                      ),
                      const SizedBox(height: 12),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 1.5,
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
                const SizedBox(width: 16),

                // Pairing QR side panel
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.02),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.04)),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'PAIRING CLIENTS',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: Colors.grey),
                        ),
                        const SizedBox(height: 16),
                        QrImageView(
                          data: state.url,
                          version: QrVersions.auto,
                          size: 140,
                          eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.white),
                          dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.white),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Scan with Camera nodes to connect',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          state.url,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
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

  Widget _buildShareSection(String sessionId) {
    final gifUrl = 'https://firebasestorage.googleapis.com/v0/b/moment-aad8b.firebasestorage.app/o/stitched%2F$sessionId.gif?alt=media';

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
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Looping GIF preview
              Expanded(
                flex: 1,
                child: Container(
                  height: 160,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      gifUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const Center(child: Icon(Icons.broken_image_outlined, color: Colors.grey));
                      },
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const Center(child: CircularProgressIndicator());
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Sharing QR code
              Expanded(
                flex: 1,
                child: Column(
                  children: [
                    QrImageView(
                      data: gifUrl,
                      version: QrVersions.auto,
                      size: 120,
                      eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.white),
                      dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Scan to download/share',
                      style: TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Divider(color: Colors.white.withOpacity(0.06)),
          const SizedBox(height: 16),

          // Email delivery input
          const Text(
            'Deliver GIF to Guest Email',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    hintText: 'Enter guest email address',
                    hintStyle: TextStyle(color: Colors.grey.shade600),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.04),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.05)),
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.emailAddress,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurpleAccent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _isSendingEmail
                      ? null
                      : () => _sendEmail(sessionId, gifUrl),
                  child: _isSendingEmail
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Send'),
                ),
              ),
            ],
          ),
          if (_emailStatus == 'success') ...[
            const SizedBox(height: 8),
            const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 16),
                SizedBox(width: 6),
                Text('Email shared successfully!', style: TextStyle(color: Colors.greenAccent, fontSize: 12)),
              ],
            ),
          ] else if (_emailStatus == 'error') ...[
            const SizedBox(height: 8),
            const Row(
              children: [
                Icon(Icons.error_rounded, color: Colors.redAccent, size: 16),
                SizedBox(width: 6),
                Text('Failed to share email. Please try again.', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
