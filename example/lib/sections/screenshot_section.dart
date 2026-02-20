import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';

class ScreenshotSection extends StatelessWidget {
  const ScreenshotSection({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 16),
        const Text(
          'Screenshot / Capture Target',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),

        // Enumerate Windows
        _EnumerateSection(state: state),

        const SizedBox(height: 16),

        // Update Capture Target
        _UpdateCaptureTargetSection(state: state),
      ],
    );
  }
}

class _EnumerateSection extends StatelessWidget {
  final AppState state;

  const _EnumerateSection({required this.state});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Enumerate Windows',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
            ),
            onPressed: () => context.read<AppState>().enumerateWindows(),
            child: const Text('Enumerate Windows & Displays'),
          ),
          if (state.enumeratedWindows.isNotEmpty ||
              state.enumeratedDisplays.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              '${state.enumeratedWindows.length} windows, ${state.enumeratedDisplays.length} displays',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            // Displays
            if (state.enumeratedDisplays.isNotEmpty) ...[
              const Text('Displays:',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              ...state.enumeratedDisplays.map((d) => Padding(
                    padding: const EdgeInsets.only(left: 8, top: 4),
                    child: Text(
                      'ID:${d['displayID']} - ${d['localizedName']} (${d['width']}x${d['height']})',
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                    ),
                  )),
              const SizedBox(height: 8),
            ],
            // Windows (scrollable)
            const Text('Windows:',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            Container(
              constraints: const BoxConstraints(maxHeight: 150),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: state.enumeratedWindows.length,
                itemBuilder: (context, index) {
                  final w = state.enumeratedWindows[index];
                  return Padding(
                    padding: const EdgeInsets.only(left: 8, top: 2),
                    child: Text(
                      'ID:${w['windowID']} ${w['appName']} - "${w['title']}"',
                      style:
                          const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _UpdateCaptureTargetSection extends StatefulWidget {
  final AppState state;

  const _UpdateCaptureTargetSection({required this.state});

  @override
  State<_UpdateCaptureTargetSection> createState() =>
      _UpdateCaptureTargetSectionState();
}

class _UpdateCaptureTargetSectionState
    extends State<_UpdateCaptureTargetSection> {
  String _selectedType = 'noCapture';

  static const _types = ['noCapture', 'autoCapture', 'window', 'display'];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Update Capture Target',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const Text(
            'Requires listening window to be open',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 12),

          // Type selector
          Row(
            children: [
              const Text('Type: '),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButton<String>(
                  value: _selectedType,
                  isExpanded: true,
                  items: _types
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedType = v!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Quick actions based on type (only for types that don't need search params)
          if (_selectedType == 'noCapture' || _selectedType == 'autoCapture')
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                context
                    .read<AppState>()
                    .updateCaptureTarget({'type': _selectedType});
              },
              child: Text('Set $_selectedType'),
            )
          else
            const Text(
              'Use quick-select below to pick a specific window or display',
              style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
            ),

          // If windows are enumerated, show quick-select buttons
          if (_selectedType == 'window' &&
              widget.state.enumeratedWindows.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Quick select from enumerated:',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 4),
            Container(
              constraints: const BoxConstraints(maxHeight: 120),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.state.enumeratedWindows.length,
                itemBuilder: (context, index) {
                  final w = widget.state.enumeratedWindows[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () {
                        context.read<AppState>().updateCaptureTarget({
                          'type': 'window',
                          'windowID': w['windowID'],
                        });
                      },
                      child: Text(
                        '${w['appName']} - "${w['title']}"',
                        style: const TextStyle(fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],

          if (_selectedType == 'display' &&
              widget.state.enumeratedDisplays.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Quick select from enumerated:',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 4),
            ...widget.state.enumeratedDisplays.map((d) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () {
                      context.read<AppState>().updateCaptureTarget({
                        'type': 'display',
                        'displayID': d['displayID'],
                      });
                    },
                    child: Text(
                      '${d['localizedName']} (${d['width']}x${d['height']})',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                )),
          ],

          // Result display
          if (widget.state.updateCaptureTargetResult != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Result: ${widget.state.updateCaptureTargetResult}',
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
