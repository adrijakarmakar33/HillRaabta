import 'package:flutter/material.dart';

class MvpScreen extends StatelessWidget {
  const MvpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const androidItems = <_MvpItem>[
      _MvpItem(
        icon: Icons.share,
        title: 'Music sharing',
        subtitle: 'Send music title/link through mesh chat',
        done: true,
      ),
      _MvpItem(
        icon: Icons.library_music,
        title: 'Offline music player',
        subtitle: 'Play local songs from phone storage without internet',
        done: true,
      ),
      _MvpItem(
        icon: Icons.sos,
        title: 'SOS system',
        subtitle: 'One-tap emergency broadcast in trip group',
        done: true,
      ),
      _MvpItem(
        icon: Icons.photo_library,
        title: 'File/photo sharing',
        subtitle: 'Share file or photo names/links in chat',
        done: true,
      ),
      _MvpItem(
        icon: Icons.group,
        title: 'Group chat with mesh relay',
        subtitle: 'Message hopping already active via TTL relay',
        done: true,
      ),
      _MvpItem(
        icon: Icons.sms,
        title: 'Texting via Nearby Connections API',
        subtitle: 'Android: 2 phones can message in same group code',
        done: true,
      ),
      _MvpItem(
        icon: Icons.map,
        title: 'Map/location features',
        subtitle: 'Offline GPS route from you to destination + heading',
        done: true,
      ),
    ];

    const iosItems = <_MvpItem>[
      _MvpItem(
        icon: Icons.phone_iphone,
        title: 'iOS app project',
        subtitle: 'Xcode Runner + Flutter iOS shell configured',
        done: true,
      ),
      _MvpItem(
        icon: Icons.location_on,
        title: 'GPS & offline map on iOS',
        subtitle: 'Location, saved places, route line, distance, direction',
        done: true,
      ),
      _MvpItem(
        icon: Icons.library_music,
        title: 'Offline music on iOS',
        subtitle: 'Play local audio files without internet',
        done: true,
      ),
      _MvpItem(
        icon: Icons.privacy_tip_outlined,
        title: 'iOS permissions',
        subtitle: 'Location + Bluetooth usage strings in Info.plist',
        done: true,
      ),
      _MvpItem(
        icon: Icons.wifi_tethering,
        title: 'Mesh chat (Multipeer Connectivity)',
        subtitle: 'iPhone-to-iPhone messaging without internet',
        done: true,
      ),
      _MvpItem(
        icon: Icons.ios_share,
        title: 'iOS file & photo sharing',
        subtitle: 'Send files up to 2 MB over iPhone mesh',
        done: true,
      ),
      _MvpItem(
        icon: Icons.flight_takeoff,
        title: 'TestFlight beta',
        subtitle: 'Run scripts/build_ios_testflight.sh on Mac to upload IPA',
        done: true,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title:
            const Text('MVP Progress', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1D9E75),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionHeader(
            icon: Icons.android,
            title: 'Android MVP',
            doneCount: androidItems.where((i) => i.done).length,
            total: androidItems.length,
          ),
          const SizedBox(height: 10),
          ...androidItems.map(_itemCard),
          const SizedBox(height: 20),
          _sectionHeader(
            icon: Icons.phone_iphone,
            title: 'iOS',
            doneCount: iosItems.where((i) => i.done).length,
            total: iosItems.length,
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade100),
            ),
            child: const Text(
              'iOS is ready: mesh chat, file share, map, and music. '
              'TestFlight upload needs a Mac + Apple Developer account.',
              style: TextStyle(fontSize: 12, height: 1.35),
            ),
          ),
          ...iosItems.map(_itemCard),
        ],
      ),
    );
  }

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required int doneCount,
    required int total,
  }) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF1D9E75)),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        const Spacer(),
        Text(
          '$doneCount/$total',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: doneCount == total ? Colors.green.shade700 : Colors.orange.shade800,
          ),
        ),
      ],
    );
  }

  Widget _itemCard(_MvpItem item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: item.done ? Colors.green.shade50 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: item.done ? Colors.green.shade200 : Colors.grey.shade300,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor:
                  item.done ? Colors.green.shade200 : Colors.grey.shade300,
              child: Icon(item.icon, color: Colors.black87, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.subtitle,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
            Icon(
              item.done ? Icons.check_circle : Icons.pending,
              color: item.done ? Colors.green : Colors.orange,
            ),
          ],
        ),
      ),
    );
  }
}

class _MvpItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool done;

  const _MvpItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.done,
  });
}
