import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';

class WindowSection extends StatefulWidget {
  const WindowSection({super.key});

  @override
  State<WindowSection> createState() => _WindowSectionState();
}

class _WindowSectionState extends State<WindowSection> {
  final _idController = TextEditingController(text: 'test');
  double _width = 240;
  double _height = 140;
  String _position = 'screenCenter';
  String _anchor = 'rightCenter';
  double _offsetX = 15;
  double _offsetY = 0;

  static const _positions = [
    'screenCenter',
    'bottomLeft',
    'bottomRight',
    'topRight',
    'flutterWindow',
  ];

  static const _anchors = [
    'topLeft',
    'topRight',
    'bottomLeft',
    'bottomRight',
    'leftCenter',
    'rightCenter',
  ];

  @override
  void dispose() {
    _idController.dispose();
    super.dispose();
  }

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
          'Window Management',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),

        // Listening Window Section
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Listening Window',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => context.read<AppState>().showListeningWindow(),
                      child: const Text('Show'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => context.read<AppState>().closeListeningWindow(),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Create Window Section
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Create Window',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              // Window ID
              TextField(
                controller: _idController,
                decoration: const InputDecoration(
                  labelText: 'Window ID',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),

              // Size
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Width: ${_width.toInt()}'),
                        Slider(
                          value: _width,
                          min: 100,
                          max: 600,
                          onChanged: (v) => setState(() => _width = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Height: ${_height.toInt()}'),
                        Slider(
                          value: _height,
                          min: 80,
                          max: 400,
                          onChanged: (v) => setState(() => _height = v),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Position
              Row(
                children: [
                  const Text('Position: '),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButton<String>(
                      value: _position,
                      isExpanded: true,
                      items: _positions
                          .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                          .toList(),
                      onChanged: (v) => setState(() => _position = v!),
                    ),
                  ),
                ],
              ),

              // Anchor (only for flutterWindow)
              if (_position == 'flutterWindow') ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Anchor: '),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButton<String>(
                        value: _anchor,
                        isExpanded: true,
                        items: _anchors
                            .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                            .toList(),
                        onChanged: (v) => setState(() => _anchor = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(
                          labelText: 'Offset X',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: TextInputType.number,
                        controller: TextEditingController(text: _offsetX.toString()),
                        onChanged: (v) => _offsetX = double.tryParse(v) ?? 15,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(
                          labelText: 'Offset Y',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: TextInputType.number,
                        controller: TextEditingController(text: _offsetY.toString()),
                        onChanged: (v) => _offsetY = double.tryParse(v) ?? 0,
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  context.read<AppState>().showTestWindow(
                        identifier: _idController.text,
                        width: _width,
                        height: _height,
                        position: _position,
                        anchor: _position == 'flutterWindow' ? _anchor : null,
                        offsetX: _offsetX,
                        offsetY: _offsetY,
                      );
                },
                child: const Text('Show Window'),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Active Windows Section
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    'Active Windows (${state.activeWindows.length})',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => context.read<AppState>().refreshActiveWindows(),
                    child: const Text('Refresh'),
                  ),
                ],
              ),
              if (state.activeWindows.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No active windows', style: TextStyle(color: Colors.grey)),
                )
              else
                ...state.activeWindows.map((id) => _ActiveWindowRow(windowId: id)),
              const SizedBox(height: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: state.activeWindows.isEmpty
                    ? null
                    : () => context.read<AppState>().closeAllTestWindows(),
                child: const Text('Close All'),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Event Log Section
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Text(
                    'Event Log',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => context.read<AppState>().clearWindowEvents(),
                    child: const Text('Clear'),
                  ),
                ],
              ),
              Container(
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: state.windowEvents.isEmpty
                    ? const Center(
                        child: Text('No events', style: TextStyle(color: Colors.grey)),
                      )
                    : ListView.builder(
                        itemCount: state.windowEvents.length,
                        padding: const EdgeInsets.all(8),
                        itemBuilder: (context, index) {
                          final event = state.windowEvents[index];
                          final timestamp = event['timestamp'] as String;
                          final time = timestamp.split('T').last.split('.').first;
                          final eventType = event['event'] ?? 'unknown';
                          final windowId = event['windowId'] ?? '';
                          return Text(
                            '$time $eventType: $windowId',
                            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActiveWindowRow extends StatelessWidget {
  final String windowId;

  const _ActiveWindowRow({required this.windowId});

  static const _movePositions = [
    'screenCenter',
    'bottomLeft',
    'bottomRight',
    'topRight',
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.window, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(windowId)),
          PopupMenuButton<String>(
            tooltip: 'Move window',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Move', style: TextStyle(fontSize: 12)),
                  Icon(Icons.arrow_drop_down, size: 16),
                ],
              ),
            ),
            onSelected: (position) {
              context.read<AppState>().updateTestWindowPosition(windowId, position);
            },
            itemBuilder: (context) => _movePositions
                .map((p) => PopupMenuItem(value: p, child: Text(p)))
                .toList(),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => context.read<AppState>().closeTestWindow(windowId),
            tooltip: 'Close window',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}
