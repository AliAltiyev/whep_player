import 'dart:convert';
import 'dart:developer';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'dart:async';

class WHEPAdapter {
  RTCPeerConnection? _localPeer;
  late Uri _channelUrl;
  bool _debug = false;
  late WHEPType _whepType;
  bool _waitingForCandidates = false;
  Timer? _iceGatheringTimeout;
  String? _resource;
  late Function(String) _onErrorHandler;
  late bool _audio;
  late bool _video;
  late MediaConstraints _mediaConstraints;
  final Function(MediaStream) _onStreamReceivedCallback;

  static const int DEFAULT_CONNECT_TIMEOUT = 2000;

  WHEPAdapter(RTCPeerConnection peer, Uri channelUrl, Function(String) onError,
      MediaConstraints mediaConstraints, this._onStreamReceivedCallback) {
    _mediaConstraints = mediaConstraints;
    _channelUrl = channelUrl;

    _whepType = WHEPType.Client;
    _onErrorHandler = onError;
    _audio = !_mediaConstraints.videoOnly;
    _video = !_mediaConstraints.audioOnly;
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
      print(error.toString());
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

    if (_localPeer != null && _whepType == WHEPType.Client) {
      if (_video)
        _localPeer?.addTransceiver(
            kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
            init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly));
      if (_audio)
        _localPeer?.addTransceiver(
            kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
            init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly));

      RTCSessionDescription offer = await _localPeer!.createOffer();

      if (offer.sdp != null) {
        final RegExp opusCodecId = RegExp(r'a=rtpmap:(\d+) opus/48000/2');
        final Match? match = opusCodecId.firstMatch(offer.sdp!);

        if (match != null) {
          offer = RTCSessionDescription(
            offer.sdp!.replaceAll(
                'opus/48000/2\r\n', 'opus/48000/2\r\na=rtcp-fb:${match.group(1)} nack\r\n'),
            offer.type!,
          );
        }
      }

      await _localPeer!.setLocalDescription(offer);
      _waitingForCandidates = true;
      _iceGatheringTimeout =
          Timer(const Duration(milliseconds: DEFAULT_CONNECT_TIMEOUT), _onIceGatheringTimeout);
    } else {
      if (_localPeer != null) {
        String offer = await _requestOffer();
        await _localPeer!.setRemoteDescription(RTCSessionDescription(offer, 'offer'));
        RTCSessionDescription answer = await _localPeer!.createAnswer();

        try {
          await _localPeer!.setLocalDescription(answer);
          _waitingForCandidates = true;
          _iceGatheringTimeout =
              Timer(const Duration(milliseconds: DEFAULT_CONNECT_TIMEOUT), _onIceGatheringTimeout);
        } catch (error) {
          _log(answer.sdp);
          rethrow;
        }
      }
    }
  }

  void onicecandidate(RTCIceCandidate? candidate) async {
    if (candidate == null || _resource == null) {
      return;
    }
    log('Sending candidate: ${candidate.toMap().toString()}');
    try {
      var respose = await http.patch(Uri.parse(_resource!),
          headers: {
            'Content-Type': 'application/trickle-ice-sdpfrag',
          },
          body: candidate.candidate);
      log('Received Patch response: ${respose.body}');
    } catch (e) {}
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

    if (_whepType == WHEPType.Client) {
      await _sendOffer();
    } else {
      await _sendAnswer();
    }
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
    if (_whepType == WHEPType.Server) {
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
    return '';
  }

  Future<void> _sendAnswer() async {
    if (_localPeer == null) {
      _log('Local RTC peer not initialized');
      return;
    }

    if (_whepType == WHEPType.Server && _resource != null) {
      RTCSessionDescription? answer = await _localPeer!.getRemoteDescription();
      final response = await http.patch(
        Uri.parse(_resource!),
        headers: {'Content-Type': 'application/sdp'},
        body: answer!.sdp,
      );

      if (response.statusCode != 200) {
        _error('sendAnswer response: ${response.statusCode}');
      }
    }
  }

  Future<void> _sendOffer() async {
    if (_localPeer == null) {
      _log('Local RTC peer not initialized');
      return;
    }

    RTCSessionDescription? offer = await _localPeer!.getLocalDescription();

    if (_whepType == WHEPType.Client) {
      _log('Sending offer to $_channelUrl');
      final response = await http.post(
        _channelUrl,
        headers: {'Content-Type': 'application/sdp'},
        body: offer!.sdp,
      );

      if (response.statusCode == 200) {
        print('--------works');
        _resource = _getResourceUrlFromHeaders(response.headers);
        _log('WHEP Resource', _resource);
        String answer = response.body;
        await _localPeer!.setRemoteDescription(RTCSessionDescription(answer, 'answer'));
        _sendAnswer();
      } else if (response.statusCode == 400) {
        _log('Server does not support client-offer, need to reconnect');
        _whepType = WHEPType.Server;
        _onErrorHandler('reconnectneeded');
      } else if (response.statusCode == 406 &&
          _audio &&
          !_mediaConstraints.audioOnly &&
          !_mediaConstraints.videoOnly) {
        _log('Maybe server does not support audio. Let\'s retry without audio');
        _audio = false;
        _video = true;
        _onErrorHandler('reconnectneeded');
      } else if (response.statusCode == 406 &&
          _video &&
          !_mediaConstraints.audioOnly &&
          !_mediaConstraints.videoOnly) {
        _log('Maybe server does not support video. Let\'s retry without video');
        _audio = true;
        _video = false;
        _onErrorHandler('reconnectneeded');
      } else {
        _error('sendAnswer response: ${response.statusCode}');
        _onErrorHandler('connectionfailed');
      }
    }
  }

  void _log(dynamic message, [dynamic data]) {
    if (_debug) {
      print('WebRTC-player $message ${data ?? ''}');
    }
  }

  void _error(dynamic message) {
    print('WebRTC-player $message');
  }
}

enum WHEPType {
  Client,
  Server,
}

class MediaConstraints {
  final bool audioOnly;
  final bool videoOnly;

  MediaConstraints({this.audioOnly = false, this.videoOnly = false});
}
