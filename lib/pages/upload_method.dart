import 'package:flutter/material.dart';
import '../services/admin_service.dart';
import '../ui/manage_ui.dart';
import '../ui/media.dart';
import '../ui/neo.dart';
import 'upload_video.dart';
import 'upload_vidurl.dart';

class UploadMethodPage extends StatelessWidget {
  const UploadMethodPage({super.key});

  bool get isAdmin => AdminService.isAdmin;

  void openDirectUpload(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const UploadTestPage(),
      ),
    );
  }

  void openUrlUpload(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const UploadVideoUrlPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: AdminService.notifier,
        builder: (c, _, __) => _page(c),
      );

  Widget _page(BuildContext context) {
    if (!isAdmin) {
      return const NeoScaffold(
        overline: 'Access // Restricted',
        title: 'Upload Video',
        body: EmptyState(
          icon: Icons.lock_outline_rounded,
          text: 'Admin access only',
          sub: 'Sign in with the admin account to upload videos.',
        ),
      );
    }

    return NeoScaffold(
      overline: 'Admin // Upload',
      title: 'Upload Video',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
        children: [
          const SectionHeader(title: 'Choose method', tag: '2 modes'),
          const SizedBox(height: 14),
          NeoActionTile(
            icon: Icons.cloud_upload_rounded,
            title: 'Direct Video Upload',
            subtitle: 'Pick a video file from your device and upload it.',
            tag: 'DEVICE',
            color: Neo.cyan,
            onTap: () => openDirectUpload(context),
          ),
          const SizedBox(height: 14),
          NeoActionTile(
            icon: Icons.link_rounded,
            title: 'Upload Using URL',
            subtitle: 'Paste an existing video URL and save it to the database.',
            tag: 'LINK',
            color: Neo.violet,
            onTap: () => openUrlUpload(context),
          ),
        ],
      ),
    );
  }
}
