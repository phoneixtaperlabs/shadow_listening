import 'package:flutter_test/flutter_test.dart';
import 'package:shadow_listening/shadow_listening.dart';
import 'package:shadow_listening/shadow_listening_platform_interface.dart';
import 'package:shadow_listening/shadow_listening_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockShadowListeningPlatform
    with MockPlatformInterfaceMixin
    implements ShadowListeningPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final ShadowListeningPlatform initialPlatform = ShadowListeningPlatform.instance;

  test('$MethodChannelShadowListening is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelShadowListening>());
  });

  test('getPlatformVersion', () async {
    ShadowListening shadowListeningPlugin = ShadowListening();
    MockShadowListeningPlatform fakePlatform = MockShadowListeningPlatform();
    ShadowListeningPlatform.instance = fakePlatform;

    expect(await shadowListeningPlugin.getPlatformVersion(), '42');
  });
}
