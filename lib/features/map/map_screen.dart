import 'package:flutter/material.dart';
import '../../core/transport/nearby_service.dart';

class MapScreen extends StatelessWidget {
  final String deviceId;
  final String deviceName;
  final String groupId;
  final NearbyService nearby;

  const MapScreen({
    super.key,
    required this.deviceId,
    required this.deviceName,
    required this.groupId,
    required this.nearby,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 33, 182, 135),
        automaticallyImplyLeading: false,
        title: const Text('Group Map', style: TextStyle(color: Colors.white)),
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map, size: 80, color: Colors.grey),
            SizedBox(height: 16),
            Text('Map coming soon',
                style: TextStyle(color: Colors.grey, fontSize: 16)),
          ],
        ),
      ),
    );
  }
}
