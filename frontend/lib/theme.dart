import 'package:flutter/material.dart';

/// 粉笔与红笔：绿板是讲台，纸面是作业本，朱砂红只属于「呼叫」。
abstract final class AppColors {
  static const paper = Color(0xFFF2F3EF);
  static const card = Color(0xFFFFFFFF);
  static const ink = Color(0xFF16211C);
  static const inkSoft = Color(0xFF3E4E47);
  static const muted = Color(0xFF74847C);
  static const rule = Color(0xFFDFE3DA);
  static const ruleFaint = Color(0xFFE9ECE5);

  static const board = Color(0xFF122E28);
  static const boardDeep = Color(0xFF0B201C);
  static const boardRim = Color(0xFF2A4F45);
  static const chalk = Color(0xFFE4EAE2);
  static const chalkSoft = Color(0xFF9FB3AA);

  static const redPen = Color(0xFFB33A2B);
  static const redPenDeep = Color(0xFF8C2A1F);
  static const redPenSoft = Color(0xFFF9E9E4);
  static const redPenOnBoard = Color(0xFFFF8A6E);

  static const jade = Color(0xFF0E7356);
  static const jadeSoft = Color(0xFFE6F0EA);
  static const jadeOnBoard = Color(0xFF77D9B4);

  static const amber = Color(0xFF8A5D11);
  static const amberSoft = Color(0xFFF8EFDC);
  static const amberOnBoard = Color(0xFFFFC46B);

  /// 兼容既有调用点的别名。
  static const Color background = paper;
  static const Color surface = card;
  static const Color line = rule;
  static const Color primary = redPen;
  static const Color primaryDark = board;
  static const Color primaryDeep = boardDeep;
  static const Color primarySoft = redPenSoft;
  static const Color teal = jade;
  static const Color tealSoft = jadeSoft;
  static const Color success = jade;
  static const Color warning = amber;
  static const Color warningSoft = amberSoft;
  static const Color danger = redPen;
  static const Color dangerSoft = redPenSoft;

  static const List<BoxShadow> cardShadow = [
    BoxShadow(color: Color(0x0F16211C), blurRadius: 18, offset: Offset(0, 6)),
  ];
}

abstract final class AppType {
  /// 时间、计数、状态码——数字是这套字体唯一能放开字重的地方。
  static TextStyle numeral(
    BuildContext context, {
    required double size,
    FontWeight weight = FontWeight.w700,
    Color? color,
  }) {
    return TextStyle(
      fontSize: size,
      fontWeight: weight,
      height: 1.1,
      color: color ?? AppColors.ink,
      fontFeatures: const [FontFeature.tabularFigures()],
      letterSpacing: 0.2,
    );
  }
}

ThemeData buildCallYouTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.redPen,
    onPrimary: Colors.white,
    primaryContainer: AppColors.redPenSoft,
    onPrimaryContainer: AppColors.redPenDeep,
    secondary: AppColors.jade,
    onSecondary: Colors.white,
    secondaryContainer: AppColors.jadeSoft,
    onSecondaryContainer: AppColors.jade,
    error: AppColors.redPen,
    onError: Colors.white,
    surface: AppColors.card,
    onSurface: AppColors.ink,
    surfaceContainerLowest: AppColors.card,
    surfaceContainerLow: AppColors.paper,
    surfaceContainer: AppColors.paper,
    surfaceContainerHigh: AppColors.ruleFaint,
    outline: AppColors.rule,
    outlineVariant: AppColors.rule,
  );

  final baseTheme = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamilyFallback: const ['CallYou CJK'],
  );

  // 中文只有一种字重，层级靠字号与留白，不靠假粗。
  final textTheme = baseTheme.textTheme
      .apply(bodyColor: AppColors.ink, displayColor: AppColors.ink)
      .copyWith(
        displayLarge: baseTheme.textTheme.displayLarge?.copyWith(
          fontSize: 46,
          fontWeight: FontWeight.w600,
          height: 1.08,
          letterSpacing: 0,
        ),
        displayMedium: baseTheme.textTheme.displayMedium?.copyWith(
          fontSize: 34,
          fontWeight: FontWeight.w600,
          height: 1.12,
          letterSpacing: 0,
        ),
        displaySmall: baseTheme.textTheme.displaySmall?.copyWith(
          fontSize: 27,
          fontWeight: FontWeight.w600,
          height: 1.18,
          letterSpacing: 0,
        ),
        headlineLarge: baseTheme.textTheme.headlineLarge?.copyWith(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          height: 1.24,
          letterSpacing: 0,
        ),
        headlineMedium: baseTheme.textTheme.headlineMedium?.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          height: 1.28,
          letterSpacing: 0,
        ),
        headlineSmall: baseTheme.textTheme.headlineSmall?.copyWith(
          fontSize: 17.5,
          fontWeight: FontWeight.w600,
          height: 1.32,
          letterSpacing: 0,
        ),
        titleLarge: baseTheme.textTheme.titleLarge?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          height: 1.38,
          letterSpacing: 0,
        ),
        titleMedium: baseTheme.textTheme.titleMedium?.copyWith(
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
          height: 1.4,
          letterSpacing: 0,
        ),
        titleSmall: baseTheme.textTheme.titleSmall?.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          height: 1.42,
          letterSpacing: 0,
        ),
        bodyLarge: baseTheme.textTheme.bodyLarge?.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          height: 1.7,
        ),
        bodyMedium: baseTheme.textTheme.bodyMedium?.copyWith(
          fontSize: 13.5,
          fontWeight: FontWeight.w400,
          height: 1.7,
        ),
        bodySmall: baseTheme.textTheme.bodySmall?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          height: 1.62,
        ),
        labelLarge: baseTheme.textTheme.labelLarge?.copyWith(
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
          height: 1.3,
        ),
        labelMedium: baseTheme.textTheme.labelMedium?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
        ),
        labelSmall: baseTheme.textTheme.labelSmall?.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
        ),
      );

  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: const BorderSide(color: AppColors.rule),
  );

  return baseTheme.copyWith(
    textTheme: textTheme,
    scaffoldBackgroundColor: AppColors.paper,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.rule,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(
        borderSide: const BorderSide(color: AppColors.ink, width: 1.4),
      ),
      errorBorder: inputBorder.copyWith(
        borderSide: const BorderSide(color: AppColors.redPen),
      ),
      focusedErrorBorder: inputBorder.copyWith(
        borderSide: const BorderSide(color: AppColors.redPen, width: 1.4),
      ),
      hintStyle: const TextStyle(
        color: AppColors.muted,
        fontSize: 14,
        height: 1.5,
      ),
      labelStyle: const TextStyle(color: AppColors.inkSoft, fontSize: 13.5),
      floatingLabelStyle: const TextStyle(
        color: AppColors.ink,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
      ),
      prefixIconColor: AppColors.muted,
      suffixIconColor: AppColors.muted,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, 50)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 22),
        ),
        elevation: const WidgetStatePropertyAll(0),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
        ),
        textStyle: WidgetStatePropertyAll(
          textTheme.labelLarge?.copyWith(fontSize: 14.5),
        ),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return AppColors.rule;
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.pressed)) {
            return AppColors.inkSoft;
          }
          return AppColors.board;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return AppColors.muted;
          }
          return AppColors.chalk;
        }),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 20),
        ),
        side: const WidgetStatePropertyAll(BorderSide(color: AppColors.rule)),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
        ),
        foregroundColor: const WidgetStatePropertyAll(AppColors.ink),
        textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.ink,
        textStyle: textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.board,
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: AppColors.chalk),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
      insetPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.jade,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: const BoxDecoration(
        color: AppColors.board,
        borderRadius: BorderRadius.all(Radius.circular(6)),
      ),
      textStyle: textTheme.bodySmall?.copyWith(color: AppColors.chalk),
      waitDuration: const Duration(milliseconds: 450),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(99),
      thumbColor: WidgetStatePropertyAll(AppColors.muted.withValues(alpha: 0.3)),
    ),
  );
}
