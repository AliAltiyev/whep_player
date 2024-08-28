import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'dart:async';

import 'package:whep_player/whep.dart';

void main() {
  runApp(const WHEPTestApp());
}

class WHEPTestApp extends StatelessWidget {
  const WHEPTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WHEP Protocol Test',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const WHEPTestPage(),
    );
  }
}

class WHEPTestPage extends StatefulWidget {
  const WHEPTestPage({super.key});

  @override
  _WHEPTestPageState createState() => _WHEPTestPageState();
}

class _WHEPTestPageState extends State<WHEPTestPage> {
  RTCPeerConnection? _peerConnection;
  WHEPAdapter? _whepAdapter;
  final TextEditingController _urlController = TextEditingController.fromValue(
      const TextEditingValue(text: 'https://whep5.fastocloud.com/api/v2/whep/channel/test332'));
  String _logs = '';
  final RTCVideoRenderer _renderer = RTCVideoRenderer();

  @override
  void initState() {
    super.initState();
    _renderer.initialize().then((_) {
      // Renderer is initialized
    }).catchError((error) {
      _log('Error initializing renderer: $error');
    });
    _initializePeerConnection();
  }

  Future<void> _initializePeerConnection() async {
    Map<String, dynamic> configuration = {
      "iceServers": [
        {"urls": "stun:stun.l.google.com:19302"}
      ]
    };

    final Map<String, dynamic> offerSdpConstraints = {
      "mandatory": {},
      "optional": [
        {"DtlsSrtpKeyAgreement": true}
      ],
    };

    _peerConnection = await createPeerConnection(configuration, offerSdpConstraints);
    _whepAdapter = WHEPAdapter(
      _peerConnection!,
      Uri.parse(_urlController.text),
      (error) => _log('Error: $error'),
      MediaConstraints(
        audioOnly: true,
        videoOnly: true,
      ),
      (MediaStream stream) {
        setState(() {
          _renderer.srcObject = stream;
          log(stream.toString());
        });
        _log('Received video stream.');
      },
    );

    _whepAdapter!.enableDebug();
  }

  void _log(String message) {
    setState(() {
      _logs += '$message\n';
    });
  }

  Future<void> _connect() async {
    if (_whepAdapter != null) {
      await _whepAdapter!.connect();
      _log('Connected to WHEP server.');
    }
  }

  Future<void> _disconnect() async {
    if (_whepAdapter != null) {
      await _whepAdapter!.disconnect();
      _log('Disconnected from WHEP server.');
    }
  }

  @override
  void dispose() {
    _renderer.dispose();
    _peerConnection?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WHEP Protocol Test'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Enter WHEP Server URL',
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: MediaQuery.sizeOf(context).height / 2,
              width: MediaQuery.sizeOf(context).width,
              child: RTCVideoView(_renderer,
                  mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () {
                    _connect();
                  },
                  child: const Text('Connect'),
                ),
                ElevatedButton(
                  onPressed: _disconnect,
                  child: const Text('Disconnect'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  _logs,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
