import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:tray_manager/tray_manager.dart'
    show Menu, MenuItem, TrayListener, trayManager;
import 'package:window_manager/window_manager.dart'
    show WindowListener, windowManager;

const _showItemKey = 'show';
const _quitItemKey = 'quit';

/// Windows/Linux/macOS：点标题栏的关闭只是把窗口收进系统托盘，
/// 真正退出只在托盘菜单的「退出」里。
///
/// 收起后窗口不可见也不聚焦，但轮询呼叫的定时器和音频播放都不依赖窗口
/// 可见，所以接到呼叫照常循环播放，不需要为了听到提醒而把窗口留在前台。
class _DesktopTray with TrayListener, WindowListener {
  /// 托盘图标必须是打进产物的资源，插件按 flutter_assets 下的相对路径找它。
  static String get _iconPath =>
      defaultTargetPlatform == TargetPlatform.windows
      ? 'assets/tray/tray_icon.ico'
      : 'assets/tray/tray_icon.png';

  Future<void> install(String title) async {
    try {
      // 先把托盘准备好：这一步失败就整个退回默认的「关窗即退出」，不至于
      // 出现窗口收进了托盘却找不到图标唤回来的死路。
      await trayManager.setIcon(_iconPath);
      await trayManager.setToolTip(title);
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: _showItemKey, label: '显示 $title'),
            MenuItem.separator(),
            MenuItem(key: _quitItemKey, label: '退出'),
          ],
        ),
      );
      trayManager.addListener(this);

      await windowManager.ensureInitialized();
      // 监听先挂上，再打开关闭拦截：拦截生效时一定有人接管关窗事件。
      windowManager.addListener(this);
      await windowManager.setTitle(title);
      await windowManager.setPreventClose(true);
    } catch (_) {
      // 没有托盘宿主的桌面环境（裸 X session 等）不能让应用起不来。
    }
  }

  @override
  void onWindowClose() {
    unawaited(windowManager.hide());
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(_showWindow());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case _showItemKey:
        unawaited(_showWindow());
      case _quitItemKey:
        unawaited(_quit());
    }
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _quit() async {
    await windowManager.setPreventClose(false);
    await trayManager.destroy();
    await windowManager.destroy();
  }
}

Future<void> installDesktopTray({required String title}) =>
    _DesktopTray().install(title);
