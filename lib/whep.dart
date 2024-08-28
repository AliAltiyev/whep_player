import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:developer';

class WHEPAdapter {
  RTCPeerConnection? _localPeer;
  late Uri _channelUrl;
  bool _debug = false;
  bool _waitingForCandidates = false;
  Timer? _iceGatheringTimeout;
  String? _resource;
  final Function(MediaStream) _onStreamReceivedCallback;

  static const int defaultConnectTimeout = 2000;

  WHEPAdapter(RTCPeerConnection peer, Uri channelUrl, Function(String) onError,
      this._onStreamReceivedCallback) {
    _channelUrl = channelUrl;
    resetPeer(peer);
  }

  void enableDebug() {
    _debug = true;
  }

  void resetPeer(RTCPeerConnection newPeer) {
    _localPeer = newPeer;
    _localPeer?.onIceGatheringState = _onIceGatheringStateChange;
    _localPeer?.onIceCandidate = onicecandidate;
    _localPeer?.onTrack = (RTCTrackEvent event) {
      if (event.track.kind == 'video' && event.streams.isNotEmpty) {
        _onStreamReceivedCallback(event.streams.first);
      }
    };
  }

  RTCPeerConnection? getPeer() {
    return _localPeer;
  }

  Future<void> connect() async {
    try {
      await _initSdpExchange();
    } catch (error) {
      log(error.toString());
    }
  }

  Future<void> disconnect() async {
    if (_resource != null) {
      _log('Disconnecting by removing resource $_resource');
      final response = await http.delete(Uri.parse(_resource!));
      if (response.statusCode == 200) {
        _log('Successfully removed resource');
      }
    }
  }

  Future<void> _initSdpExchange() async {
    _iceGatheringTimeout?.cancel();

    if (_localPeer != null) {
      String offer = await _requestOffer();
      await _localPeer!.setRemoteDescription(RTCSessionDescription(offer, 'offer'));
      RTCSessionDescription answer = await _localPeer!.createAnswer();

      try {
        await _localPeer!.setLocalDescription(answer);
        _waitingForCandidates = true;
        _iceGatheringTimeout =
            Timer(const Duration(milliseconds: defaultConnectTimeout), _onIceGatheringTimeout);
      } catch (error) {
        _log(answer.sdp);
        rethrow;
      }
    }
  }

  void onicecandidate(RTCIceCandidate? candidate) async {
    if (candidate == null || _resource == null) {
      return;
    }
  }

  void _onIceGatheringStateChange(RTCIceGatheringState state) {
    _log('IceGatheringState', state.toString());
    if (state != RTCIceGatheringState.RTCIceGatheringStateComplete || !_waitingForCandidates) {
      return;
    }

    _onDoneWaitingForCandidates();
  }

  void _onIceGatheringTimeout() {
    _log('IceGatheringTimeout');

    if (!_waitingForCandidates) {
      return;
    }

    _onDoneWaitingForCandidates();
  }

  Future<void> _onDoneWaitingForCandidates() async {
    _waitingForCandidates = false;
    _iceGatheringTimeout?.cancel();

    await _sendAnswer();
  }

  String? _getResourceUrlFromHeaders(Map<String, String> headers) {
    final String? location = headers['location'];
    if (location != null && location.startsWith('/')) {
      final Uri resourceUrl = Uri.parse(_channelUrl.origin + location);
      return resourceUrl.toString();
    } else {
      return location;
    }
  }

  Future<String> _requestOffer() async {
    _log('Requesting offer from: $_channelUrl');
    final response = await http.post(
      _channelUrl,
      headers: {'Content-Type': 'application/sdp'},
    );

    if (response.statusCode == 201) {
      _resource = _getResourceUrlFromHeaders(response.headers);
      _log('WHEP Resource', _resource);
      return response.body;
    } else {
      throw Exception(response.body);
    }
  }

  Future<void> _sendAnswer() async {
    if (_localPeer == null) {
      _log('Local RTC peer not initialized');
      return;
    }

    if (_resource != null) {
      RTCSessionDescription? answer = await _localPeer!.getLocalDescription();
      final body = answer!.sdp;
      final response = await http.patch(Uri.parse(_resource!),
          headers: {'Content-Type': 'application/sdp'}, body: body);

      if (response.statusCode != 201) {
        _error('sendAnswer response: ${response.statusCode}');
      }
    }
  }

  void _log(dynamic message, [dynamic data]) {
    if (_debug) {
      log('WebRTC-player $message ${data ?? ''}');
    }
  }

  void _error(dynamic message) {
    log('WebRTC-player $message');
  }
}
