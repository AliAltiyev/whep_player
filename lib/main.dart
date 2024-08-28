import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:async';

import 'package:flutter_webrtc_sdk/flutter_webrtc_sdk.dart';

void main() {
  runApp(const WHEPTestApp());
}

class Player extends StatelessWidget {
  final WebRTCPlayerBloc controller;

  const Player(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    return CustomWebRTCPlayer(
        controller: controller,
        playerBuilder: (_, __, player) => SizedBox.expand(child: player),
        placeholder: Container());
  }
}

class PlayerIdState {
  final Uri? url;

  const PlayerIdState(this.url);
}

class PlayerInitState extends PlayerIdState {
  const PlayerInitState() : super(null);
}

class PlayerLoadingState extends PlayerIdState {
  const PlayerLoadingState(Uri super.url);
}

class PlaylistCubit extends Cubit<PlayerIdState> {
  final controller = WhepPlayerController();

  PlaylistCubit() : super(const PlayerInitState());

  void setUrl(Uri? url) async {
    if (url == null) {
      emit(const PlayerInitState());
      controller.bye();
      return;
    }

    emit(PlayerLoadingState(url));

    final id = url.pathSegments.where((e) => e.isNotEmpty).join('/');
    controller.connect(url.toString(), id);

    await controller.stream.firstWhere((e) => e == WebRTCPlayerState.playing);
    emit(PlayerIdState(url));
  }

  @override
  Future<void> close() async {
    controller.dispose();
    super.close();
  }
}

class WHEPTestApp extends StatelessWidget {
  const WHEPTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
        create: (_) => PlaylistCubit(),
        child: MaterialApp(
          title: 'WHEP Protocol Test',
          theme: ThemeData(
            primarySwatch: Colors.blue,
          ),
          home: const WHEPTestPage(),
        ));
  }
}

class WHEPTestPage extends StatefulWidget {
  const WHEPTestPage({super.key});

  @override
  _WHEPTestPageState createState() => _WHEPTestPageState();
}

class _WHEPTestPageState extends State<WHEPTestPage> {
  final TextEditingController _urlController = TextEditingController.fromValue(
      const TextEditingValue(text: 'https://whep5.fastocloud.com/api/v2/whep/channel/test332'));
  String _logs = '';

  @override
  void initState() {
    super.initState();
  }

  void _log(String message) {
    setState(() {
      _logs += '$message\n';
    });
  }

  Future<void> _connect() async {
    context
        .read<PlaylistCubit>()
        .setUrl(Uri.parse('https://whep5.fastocloud.com/api/v2/whep/channel/test332'));
  }

  Future<void> _disconnect() async {}

  @override
  void dispose() {
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
                height: 320, width: 640, child: Player(context.read<PlaylistCubit>().controller)),
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
