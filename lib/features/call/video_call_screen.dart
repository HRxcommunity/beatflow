import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import '../together/bloc/together_bloc.dart';
import '../../core/theme/app_theme.dart';

// ╔══════════════════════════════════════════════════════════════╗
// ║  VIDEO CALL SCREEN — BeatFlow Together                      ║
// ║  Uses Agora RTC. channelId & token come from Firestore.     ║
// ╚══════════════════════════════════════════════════════════════╝

// ⚠️  IMPORTANT: Replace with your real Agora App ID from https://console.agora.io
// Error errInvalidToken / -101 = App ID is wrong OR token mismatch.
// Steps:
//   1. Go to https://console.agora.io → create project → copy App ID
//   2. Replace the value below with YOUR real App ID
//   3. For testing: disable token auth in Agora console (Auth Mechanism → No Token)
//   4. For production: generate tokens server-side and pass via Firestore session
//
// Current value is a PLACEHOLDER — it will always fail with errInvalidToken.
const _agoraAppId = 'ca17bb55b1c34aeb8cf392a03cbf116b'; // <-- REPLACE with real ID from console.agora.io

class VideoCallScreen extends StatefulWidget {
  final String channelId;
  final String displayName;
  final bool isOwner;

  const VideoCallScreen({
    super.key,
    required this.channelId,
    required this.displayName,
    required this.isOwner,
  });

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  RtcEngine? _engine;
  bool _localVideoOn  = true;
  bool _localAudioOn  = true;
  bool _joined        = false;
  bool _remoteJoined  = false;
  int? _remoteUid;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initAgora();
  }

  Future<void> _initAgora() async {
    // Guard: catch placeholder App ID before Agora throws errInvalidToken/-101
    if (_agoraAppId == 'YOUR_AGORA_APP_ID' || _agoraAppId.isEmpty) {
      setState(() => _error =
          'Agora App ID not configured.\n\n'
          'Steps:\n'
          '1. Go to console.agora.io → create project\n'
          '2. Copy your App ID (32-char hex string)\n'
          '3. Replace YOUR_AGORA_APP_ID in video_call_screen.dart line 23\n'
          '4. In Agora console: set Auth Mechanism to No Token (for dev)');
      return;
    }

    // Request permissions
    final camPerm  = await Permission.camera.request();
    final micPerm  = await Permission.microphone.request();
    if (!camPerm.isGranted || !micPerm.isGranted) {
      setState(() => _error = 'Camera & microphone permissions required.');
      return;
    }

    try {
      _engine = createAgoraRtcEngine();
      await _engine!.initialize(const RtcEngineContext(
        appId: _agoraAppId,
        channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
      ));

      // Set as broadcaster (can send+receive) if owner, else audience (receive-only but with mic/cam)
      await _engine!.setClientRole(
        role: ClientRoleType.clientRoleBroadcaster,
      );
      await _engine!.enableVideo();
      await _engine!.enableAudio();
      await _engine!.startPreview();

      _engine!.registerEventHandler(RtcEngineEventHandler(
        onJoinChannelSuccess: (conn, elapsed) {
          if (mounted) setState(() => _joined = true);
        },
        onUserJoined: (conn, uid, elapsed) {
          if (mounted) setState(() { _remoteJoined = true; _remoteUid = uid; });
        },
        onUserOffline: (conn, uid, reason) {
          if (mounted) setState(() { _remoteJoined = false; _remoteUid = null; });
        },
        onError: (code, msg) {
          if (mounted) setState(() => _error = 'Agora error $code: $msg');
        },
      ));

      // Join channel — token is null for testing (use null for temp token or set proper token)
      await _engine!.joinChannel(
        token:     '',          // '' = no-token mode (set Auth Mechanism → No Token in Agora console). For production: pass real token here
        channelId: widget.channelId,
        uid:       0,
        options:   const ChannelMediaOptions(
          autoSubscribeAudio: true,
          autoSubscribeVideo: true,
          publishMicrophoneTrack: true,
          publishCameraTrack: true,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to init Agora: $e');
    }
  }

  Future<void> _leaveCall() async {
    await _engine?.leaveChannel();
    await _engine?.release();
    _engine = null;
    if (mounted) {
      context.read<TogetherBloc>().add(
        widget.isOwner ? TogetherEndVideoCall() : TogetherLeaveSession(),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _engine?.leaveChannel();
    _engine?.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: AppTheme.bgDeep,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 56),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(_error!, textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70)),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Remote video (full screen) ──────────────────────
          if (_remoteJoined && _remoteUid != null && _engine != null)
            Positioned.fill(
              child: AgoraVideoView(
                controller: VideoViewController.remote(
                  rtcEngine: _engine!,
                  canvas: VideoCanvas(uid: _remoteUid),
                  connection: RtcConnection(channelId: widget.channelId),
                ),
              ),
            )
          else
            Positioned.fill(
              child: Container(
                color: AppTheme.bgDeep,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                      child: const Icon(Icons.person_rounded,
                          color: Colors.white54, size: 40),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _joined ? 'Waiting for others to join...' : 'Connecting...',
                      style: const TextStyle(color: Colors.white60, fontSize: 15),
                    ),
                    if (!_joined) ...[
                      const SizedBox(height: 16),
                      const CircularProgressIndicator(
                          color: Colors.white38, strokeWidth: 2),
                    ],
                  ],
                ),
              ),
            ),

          // ── Local video (PiP, top-right) ────────────────────
          if (_localVideoOn && _joined && _engine != null)
            Positioned(
              top: 60, right: 16,
              child: Container(
                width: 100, height: 140,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white24, width: 1.5),
                ),
                clipBehavior: Clip.hardEdge,
                child: AgoraVideoView(
                  controller: VideoViewController(
                    rtcEngine: _engine!,
                    canvas: const VideoCanvas(uid: 0),
                  ),
                ),
              ),
            ),

          // ── Top bar ─────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8, height: 8,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF22C55E),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text('LIVE CALL',
                            style: TextStyle(
                                color: Colors.white, fontSize: 11,
                                fontWeight: FontWeight.w700, letterSpacing: 1)),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (_remoteJoined)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black38,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.person_rounded, color: Colors.white, size: 14),
                          const SizedBox(width: 4),
                          Text('${_remoteJoined ? 2 : 1} in call',
                              style: const TextStyle(color: Colors.white, fontSize: 11)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ── Bottom controls ──────────────────────────────────
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(32, 24, 32, 48),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black.withValues(alpha: 0.9), Colors.transparent],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Mute mic
                  _CallBtn(
                    icon: _localAudioOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                    label: _localAudioOn ? 'Mute' : 'Unmute',
                    active: _localAudioOn,
                    onTap: () async {
                      await _engine?.muteLocalAudioStream(_localAudioOn);
                      setState(() => _localAudioOn = !_localAudioOn);
                    },
                  ),
                  // End call
                  GestureDetector(
                    onTap: _leaveCall,
                    child: Container(
                      width: 68, height: 68,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFEF4444),
                      ),
                      child: const Icon(Icons.call_end_rounded,
                          color: Colors.white, size: 30),
                    ),
                  ),
                  // Toggle camera
                  _CallBtn(
                    icon: _localVideoOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                    label: _localVideoOn ? 'Camera' : 'No Cam',
                    active: _localVideoOn,
                    onTap: () async {
                      await _engine?.muteLocalVideoStream(_localVideoOn);
                      setState(() => _localVideoOn = !_localVideoOn);
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CallBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _CallBtn({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active
                  ? Colors.white.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.05),
              border: Border.all(
                color: active ? Colors.white38 : Colors.white12,
                width: 1.5,
              ),
            ),
            child: Icon(icon,
                color: active ? Colors.white : Colors.white38, size: 24),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: TextStyle(
                  color: active ? Colors.white : Colors.white38,
                  fontSize: 11)),
        ],
      ),
    );
  }
}
