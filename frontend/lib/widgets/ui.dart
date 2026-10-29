import 'package:flutter/material.dart';

import '../theme.dart';

/// 呼叫的标志：一个座位，一圈正在扩散的声音。
class _RingerMark extends StatelessWidget {
  const _RingerMark({required this.size, required this.body, required this.ring});

  final double size;
  final Color body;
  final Color ring;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _RingerPainter(body: body, ring: ring),
    );
  }
}

class _RingerPainter extends CustomPainter {
  const _RingerPainter({required this.body, required this.ring});

  final Color body;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final seat = Offset(s * 0.40, s * 0.62);
    final stroke = s * 0.085;

    canvas.drawCircle(
      seat,
      s * 0.165,
      Paint()..color = body,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * 0.20, s * 0.66, s * 0.40, s * 0.17),
        Radius.circular(s * 0.08),
      ),
      Paint()..color = body,
    );

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;

    for (final entry in [(0.34, body), (0.54, ring)]) {
      arc.color = entry.$2;
      canvas.drawArc(
        Rect.fromCircle(center: seat, radius: s * entry.$1),
        -1.22,
        1.02,
        false,
        arc,
      );
    }
  }

  @override
  bool shouldRepaint(_RingerPainter old) =>
      old.body != body || old.ring != ring;
}

class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.size = 38,
    this.onDark = false,
    this.showWordmark = true,
    this.showSubtitle = true,
  });

  final double size;
  final bool onDark;
  final bool showWordmark;
  final bool showSubtitle;

  @override
  Widget build(BuildContext context) {
    final tile = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: onDark ? AppColors.chalk : AppColors.board,
        borderRadius: BorderRadius.circular(size * 0.22),
      ),
      alignment: Alignment.center,
      child: _RingerMark(
        size: size * 0.66,
        body: onDark ? AppColors.board : AppColors.chalk,
        ring: onDark ? AppColors.redPen : AppColors.redPenOnBoard,
      ),
    );

    if (!showWordmark) {
      return tile;
    }

    final titleColor = onDark ? AppColors.chalk : AppColors.ink;
    final subtitleColor = onDark ? AppColors.chalkSoft : AppColors.muted;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        tile,
        SizedBox(width: size * 0.28),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CallYou',
              style: TextStyle(
                color: titleColor,
                fontSize: size * 0.46,
                fontWeight: FontWeight.w700,
                height: 1.05,
                letterSpacing: -0.2,
              ),
            ),
            if (showSubtitle) ...[
              const SizedBox(height: 2),
              Text(
                '课堂即时呼叫',
                style: TextStyle(
                  color: subtitleColor,
                  fontSize: size * 0.26,
                  fontWeight: FontWeight.w400,
                  height: 1.2,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// 纸面 + 座次格线：格线是课桌与座位表的隐喻，不是光斑装饰。
class PageBackdrop extends StatelessWidget {
  const PageBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.paper),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const IgnorePointer(
            child: CustomPaint(painter: _SeatGridPainter()),
          ),
          child,
        ],
      ),
    );
  }
}

class _SeatGridPainter extends CustomPainter {
  const _SeatGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const pitch = 64.0;
    final line = Paint()
      ..color = AppColors.ruleFaint
      ..strokeWidth = 1;

    for (var x = pitch; x < size.width; x += pitch) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (var y = pitch; y < size.height; y += pitch) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ClassroomHeader extends StatelessWidget {
  const ClassroomHeader({
    super.key,
    required this.account,
    required this.roleLabel,
    required this.roleColor,
    required this.roleIcon,
    required this.onExit,
    this.identity,
  });

  final String account;
  final String roleLabel;
  final Color roleColor;
  final IconData roleIcon;
  final String? identity;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.rule)),
      ),
      child: Row(
        children: [
          const AppLogo(size: 32, showSubtitle: false),
          const SizedBox(width: 12),
          if (wide)
            Flexible(
              child: Text(
                account,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.muted,
                ),
              ),
            ),
          const Spacer(),
          if (wide && identity != null) ...[
            Text(
              identity!,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.inkSoft,
              ),
            ),
            const SizedBox(width: 14),
          ],
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(roleIcon, size: 15, color: roleColor),
              const SizedBox(width: 6),
              Text(
                roleLabel,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: roleColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Tooltip(
            message: '退出登录',
            child: IconButton(
              onPressed: onExit,
              icon: const Icon(Icons.close_rounded, size: 18),
              style: IconButton.styleFrom(
                foregroundColor: AppColors.muted,
                hoverColor: AppColors.ruleFaint,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 状态标签。颜色永远和文字、图标同时出现，不单靠色相传达状态。
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.background,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: background ?? Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class StudentAvatar extends StatelessWidget {
  const StudentAvatar({
    super.key,
    required this.name,
    this.size = 46,
    this.online,
    this.onDark = false,
  });

  static const _palettes = [
    (AppColors.jadeSoft, AppColors.jade),
    (Color(0xFFE9EDF1), Color(0xFF3D5468)),
    (AppColors.redPenSoft, AppColors.redPenDeep),
    (Color(0xFFEDEBE2), Color(0xFF6B5E33)),
    (Color(0xFFE7F0EE), Color(0xFF2A6A5E)),
    (Color(0xFFEDE7EA), Color(0xFF6E4358)),
  ];

  final String name;
  final double size;
  final bool? online;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim().substring(0, 1);
    final palette =
        _palettes[name.codeUnits.fold<int>(0, (a, b) => a + b) % _palettes.length];
    final background = onDark ? Colors.transparent : palette.$1;
    final foreground = onDark ? AppColors.chalk : palette.$2;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: background,
              shape: BoxShape.circle,
              border: Border.all(
                color: onDark
                    ? AppColors.chalk.withValues(alpha: 0.28)
                    : palette.$1,
                width: 1.5,
              ),
            ),
            child: Text(
              initial,
              style: TextStyle(
                color: foreground,
                fontSize: size * 0.4,
                fontWeight: FontWeight.w500,
                height: 1,
              ),
            ),
          ),
          if (online != null)
            Positioned(
              right: size * 0.02,
              bottom: size * 0.02,
              child: Container(
                width: size * 0.24,
                height: size * 0.24,
                decoration: BoxDecoration(
                  color: online! ? AppColors.jade : AppColors.muted,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: onDark ? AppColors.board : AppColors.card,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class PanelHeader extends StatelessWidget {
  const PanelHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: textTheme.titleLarge),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: textTheme.bodySmall?.copyWith(color: AppColors.muted),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 12),
          trailing!,
        ],
      ],
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
    this.color = AppColors.card,
    this.gradient,
    this.borderColor = AppColors.rule,
    this.radius = 12,
    this.showShadow = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Gradient? gradient;
  final Color borderColor;
  final double radius;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? color : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor),
        boxShadow: showShadow ? AppColors.cardShadow : null,
      ),
      child: child,
    );
  }
}

/// 绿板面板：教师端与来电共用的讲台表面。
class BoardPanel extends StatelessWidget {
  const BoardPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.depth = 0,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double depth;

  @override
  Widget build(BuildContext context) {
    final base = depth == 0 ? AppColors.board : AppColors.boardDeep;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: base == AppColors.boardDeep ? AppColors.board : AppColors.boardRim),
      ),
      child: child,
    );
  }
}

void showAppSnackBar(
  BuildContext context,
  String message, {
  bool error = false,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      backgroundColor: error ? AppColors.redPen : AppColors.board,
      content: Row(
        children: [
          Icon(
            error ? Icons.error_outline_rounded : Icons.check_circle_outline,
            color: AppColors.chalk,
            size: 19,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}

Route<T> appPageRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.018),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// 系统要求减少动画时停掉循环动效——课堂大屏会整天开着这一页。
bool prefersReducedMotion(BuildContext context) {
  return MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}
