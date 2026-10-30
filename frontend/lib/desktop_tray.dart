/// 桌面版「关窗收进托盘」的安装入口。
///
/// 只有 Windows/Linux/macOS 有系统托盘，Web 与移动端走条件导出的空实现，
/// 免得把只支持桌面的插件带进 Web 构建。
library;

export 'desktop_tray_stub.dart'
    if (dart.library.io) 'desktop_tray_native.dart';
