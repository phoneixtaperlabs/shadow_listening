import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../widgets/status_badge.dart';

class PermissionsSection extends StatelessWidget {
  const PermissionsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PermissionRow(
          title: 'Mic Permission',
          isAllowed: state.micAllowed,
          permissionType: 'mic',
        ),
        const SizedBox(height: 16),
        _PermissionRow(
          title: 'System Audio Permission',
          isAllowed: state.sysAudioAllowed,
          permissionType: 'sysAudio',
        ),
        const SizedBox(height: 16),
        _PermissionRow(
          title: 'Screen Recording Permission',
          isAllowed: state.screenRecordingAllowed,
          permissionType: 'screen',
        ),
      ],
    );
  }
}

class _PermissionRow extends StatelessWidget {
  final String title;
  final bool isAllowed;
  final String permissionType;

  const _PermissionRow({
    required this.title,
    required this.isAllowed,
    required this.permissionType,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            StatusBadge.permission(allowed: isAllowed),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: () => context.read<AppState>().checkPermission(permissionType),
                child: const Text('Check'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: isAllowed
                    ? null
                    : () async {
                        final state = context.read<AppState>();
                        await state.requestPermission(permissionType);
                        await state.checkAllPermissionStatus();
                      },
                child: Text(isAllowed ? 'Allowed' : 'Request'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
