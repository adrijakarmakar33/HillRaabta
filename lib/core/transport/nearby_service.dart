import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_nearby_connections_plus/flutter_nearby_connections_plus.dart'
    as mpc;
import 'package:nearby_connections/nearby_connections.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../mesh/message_model.dart';

class NearbyService {
  static const Strategy strategy = Strategy.P2P_CLUSTER;
  static const String _iosServiceType = 'hill-mesh';
  static const int _iosMaxFileBytes = 2 * 1024 * 1024;

  final Set<String> _seenIds = {};
  final Set<String> _connectedPeers = {};
  final Map<String, String> _peerNames = {};
  final Set<String> _invitedPeers = {};

  // Callbacks
  Function(MeshMessage)? onMessage;
  Function(String peerId, String peerName)? onPeerConnected;
  Function(String peerId)? onPeerDisconnected;
  Function(String event)? onSystemEvent;
  Function(String endpointId, String filePath)? onFileReceived;

  String _deviceName = '';
  bool _isRunning = false;

  mpc.NearbyService? _iosNearby;
  StreamSubscription? _iosStateSub;
  StreamSubscription? _iosDataSub;

  bool get isRunning => _isRunning;
  Set<String> get connectedPeers => _connectedPeers;
  bool get isIos => !kIsWeb && Platform.isIOS;

  Future<bool> requestPermissions() async {
    if (isIos) {
      final statuses = await [
        Permission.bluetooth,
        Permission.locationWhenInUse,
      ].request();
      return statuses.values.every((s) => s.isGranted || s.isLimited);
    }
    final statuses = await [
      Permission.bluetooth,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
      Permission.nearbyWifiDevices,
    ].request();
    return statuses.values.every((s) => s.isGranted);
  }

  Future<void> start(String deviceId, String deviceName) async {
    _deviceName = deviceName;

    final ok = await requestPermissions();
    if (!ok) {
      onSystemEvent?.call('Permissions needed for offline mesh chat');
      return;
    }

    try {
      if (isIos) {
        await _startIos();
      } else {
        await _startAndroid();
      }
      _isRunning = true;
      debugPrint('HillRaabta: Mesh started as $_deviceName');
    } catch (e) {
      debugPrint('HillRaabta: Error starting mesh: $e');
      onSystemEvent?.call('Could not start mesh: $e');
    }
  }

  Future<void> _startAndroid() async {
    await _startAdvertising();
    await _startDiscovery();
  }

  Future<void> _startIos() async {
    _iosNearby = mpc.NearbyService();
    final nearby = _iosNearby!;

    final initReady = Completer<void>();
    await nearby.init(
      serviceType: _iosServiceType,
      deviceName: _deviceName,
      strategy: mpc.Strategy.P2P_CLUSTER,
      callback: (running) {
        if (running && !initReady.isCompleted) initReady.complete();
      },
    );
    await initReady.future.timeout(const Duration(seconds: 5));

    _iosStateSub?.cancel();
    _iosStateSub = nearby.stateChangedSubscription(callback: (devices) {
      final connected = devices
          .where((d) => d.state == mpc.SessionState.connected)
          .map((d) => d.deviceId)
          .toSet();
      final previous = Set<String>.from(_connectedPeers);

      for (final d in devices) {
        _peerNames[d.deviceId] = d.deviceName;
        if (d.state == mpc.SessionState.notConnected &&
            !_invitedPeers.contains(d.deviceId)) {
          _invitedPeers.add(d.deviceId);
          nearby.invitePeer(deviceID: d.deviceId, deviceName: d.deviceName);
        }
      }

      for (final id in connected) {
        if (!previous.contains(id)) {
          _connectedPeers.add(id);
          onPeerConnected?.call(id, _peerNames[id] ?? id);
        }
      }

      for (final id in previous) {
        if (!connected.contains(id)) {
          _connectedPeers.remove(id);
          onPeerDisconnected?.call(id);
        }
      }
    });

    _iosDataSub?.cancel();
    _iosDataSub = nearby.dataReceivedSubscription(callback: (data) {
      if (data is! Map) return;
      final senderId = (data['deviceId'] as String?) ?? 'peer';
      final raw = (data['message'] as String?) ?? '';
      if (raw.isEmpty) return;
      if (raw.startsWith('HILL_FILE:')) {
        unawaited(_handleIosFileIncoming(senderId, raw.substring(10)));
        return;
      }
      _handleIncoming(raw);
    });

    await nearby.startAdvertisingPeer(deviceName: _deviceName);
    await nearby.startBrowsingForPeers();
    onSystemEvent?.call('iOS mesh active — nearby iPhones can join');
  }

  Future<void> _startAdvertising() async {
    await Nearby().startAdvertising(
      _deviceName,
      strategy,
      onConnectionInitiated: _onConnectionInitiated,
      onConnectionResult: (id, status) {
        if (status == Status.CONNECTED) {
          _connectedPeers.add(id);
          onPeerConnected?.call(id, id);
        }
      },
      onDisconnected: (id) {
        _connectedPeers.remove(id);
        onPeerDisconnected?.call(id);
      },
    );
  }

  Future<void> _startDiscovery() async {
    await Nearby().startDiscovery(
      _deviceName,
      strategy,
      onEndpointFound: (id, name, serviceId) {
        Nearby().requestConnection(
          _deviceName,
          id,
          onConnectionInitiated: _onConnectionInitiated,
          onConnectionResult: (id, status) {
            if (status == Status.CONNECTED) {
              _connectedPeers.add(id);
              onPeerConnected?.call(id, name);
            }
          },
          onDisconnected: (id) {
            _connectedPeers.remove(id);
            onPeerDisconnected?.call(id);
          },
        );
      },
      onEndpointLost: (id) {},
    );
  }

  void _onConnectionInitiated(String id, ConnectionInfo info) {
    Nearby().acceptConnection(
      id,
      onPayLoadRecieved: (endpointId, payload) {
        if (payload.type == PayloadType.BYTES && payload.bytes != null) {
          _handleIncoming(utf8.decode(payload.bytes!));
        } else if (payload.type == PayloadType.FILE) {
          // ignore: deprecated_member_use
          final location = payload.uri ?? payload.filePath ?? 'device storage';
          onFileReceived?.call(endpointId, location);
          onSystemEvent?.call('File received from $endpointId');
        }
      },
      onPayloadTransferUpdate: (endpointId, update) {
        if (update.status == PayloadStatus.SUCCESS) {
          onSystemEvent?.call('File transfer complete from $endpointId');
        }
      },
    );
  }

  void _handleIncoming(String raw) {
    try {
      final msg = MeshMessage.decode(raw);
      if (_seenIds.contains(msg.id)) return;
      _seenIds.add(msg.id);
      onMessage?.call(msg);
      if (msg.shouldRelay) {
        msg.ttl--;
        unawaited(_broadcast(msg));
      }
    } catch (e) {
      debugPrint('HillRaabta: Error handling message: $e');
    }
  }

  Future<void> _handleIosFileIncoming(String senderId, String jsonRaw) async {
    try {
      final map = jsonDecode(jsonRaw) as Map<String, dynamic>;
      final name = (map['name'] as String?) ?? 'received_file';
      final data = base64Decode(map['data'] as String);
      final dir = await getApplicationDocumentsDirectory();
      final inbox = Directory(p.join(dir.path, 'received_files'));
      if (!inbox.existsSync()) inbox.createSync(recursive: true);
      final safeName = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final out = File(p.join(inbox.path, '${DateTime.now().millisecondsSinceEpoch}_$safeName'));
      await out.writeAsBytes(data, flush: true);
      onFileReceived?.call(senderId, out.path);
      onSystemEvent?.call('File received: $safeName');
    } catch (e) {
      debugPrint('HillRaabta: iOS file receive error: $e');
    }
  }

  Future<bool> send(MeshMessage msg) async {
    _seenIds.add(msg.id);
    return _broadcast(msg);
  }

  Future<bool> _broadcast(MeshMessage msg) async {
    if (_connectedPeers.isEmpty) return false;
    final raw = msg.encode();

    if (isIos) {
      final nearby = _iosNearby;
      if (nearby == null) return false;
      var sent = false;
      for (final peer in _connectedPeers) {
        try {
          await nearby.sendMessage(peer, raw);
          sent = true;
        } catch (e) {
          debugPrint('HillRaabta: iOS send error to $peer: $e');
        }
      }
      return sent;
    }

    final bytes = utf8.encode(raw);
    var sentAtLeastOne = false;
    for (final peer in _connectedPeers) {
      try {
        await Nearby().sendBytesPayload(peer, bytes);
        sentAtLeastOne = true;
      } catch (e) {
        debugPrint('HillRaabta: send error to $peer: $e');
      }
    }
    return sentAtLeastOne;
  }

  Future<void> sendFileToPeers(String filePath) async {
    if (_connectedPeers.isEmpty) return;

    if (isIos) {
      final file = File(filePath);
      if (!file.existsSync()) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > _iosMaxFileBytes) {
        onSystemEvent?.call('File too large for iOS mesh (max 2 MB)');
        return;
      }
      final payload = 'HILL_FILE:${jsonEncode({
        'name': p.basename(filePath),
        'data': base64Encode(bytes),
      })}';
      final nearby = _iosNearby;
      if (nearby == null) return;
      for (final peer in _connectedPeers) {
        try {
          await nearby.sendMessage(peer, payload);
        } catch (e) {
          debugPrint('HillRaabta: iOS file send error to $peer: $e');
        }
      }
      onSystemEvent?.call('File sent to nearby iPhones');
      return;
    }

    for (final peer in _connectedPeers) {
      try {
        await Nearby().sendFilePayload(peer, filePath);
      } catch (e) {
        debugPrint('HillRaabta: File send error to $peer: $e');
      }
    }
  }

  Future<void> stop() async {
    if (isIos) {
      await _iosStateSub?.cancel();
      await _iosDataSub?.cancel();
      final nearby = _iosNearby;
      if (nearby != null) {
        await nearby.stopBrowsingForPeers();
        await nearby.stopAdvertisingPeer();
      }
      _iosNearby = null;
    } else {
      await Nearby().stopAllEndpoints();
      await Nearby().stopAdvertising();
      await Nearby().stopDiscovery();
    }
    _connectedPeers.clear();
    _peerNames.clear();
    _invitedPeers.clear();
    _isRunning = false;
  }
}
