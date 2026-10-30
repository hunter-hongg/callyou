import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/ui.dart';

enum VoiceReminderStatus { idle, requesting, playing, empty, failed }

class IncomingCallOverlay extends StatefulWidget {
  const IncomingCallOverlay({
    super.key,
    required this.calls,
    required this.voiceStatus,
    required this.voiceNote,
    required this.acknowledgingIds,
    required this.ackErrors,
    required this.onAcknowledge,
    required this.onRetryVoice,
  });

  final List<CallRecord> calls;
  final VoiceReminderStatus voiceStatus;
  final String voiceNote;
  final Set<String> acknowledgingIds;
  final Map<String, String> ackErrors;
  final ValueChanged<CallRecord> onAcknowledge;
  final VoidCallback onRetryVoice;

  @override
  State<IncomingCallOverlay> createState() => _IncomingCallOverlayState();
}

class _IncomingCallOverlayState extends State<IncomingCallOverlay> {
  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 620;
    final calls = widget.calls;
    final newest = calls.first;
    final multiple = calls.length > 1;

    return Material(
      color: AppColors.boardDeep,
      child: DecoratedBox(
        decoration: const BoxDecoration(color: AppColors.boardDeep),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 20 : 32,
              14,
              compact ? 20 : 32,
              18,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const AppLogo(
                      size: 30,
                      onDark: true,
                      showSubtitle: false,
                      showWordmark: false,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '课堂呼叫',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppColors.chalkSoft,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '最新 ${formatClock(newest.createdAt)}',
                      style: AppType.numeral(
                        context,
                        size: 13,
                        color: AppColors.chalkSoft,
                        weight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 620),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const _Ringer(size: 108),
                            const SizedBox(height: 22),
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                multiple
                                    ? '老师有 ${calls.length} 条呼叫待回应'
                                    : '老师正在呼叫你',
                                textAlign: TextAlign.center,
                                style: (compact
                                        ? Theme.of(context).textTheme.displayMedium
                                        : Theme.of(context).textTheme.displayLarge)
                                    ?.copyWith(color: AppColors.chalk),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              multiple
                                  ? '以下是本账号收到的呼叫，请逐一回应'
                                  : '${newest.studentName}同学，请及时回应',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: AppColors.chalkSoft),
                            ),
                            const SizedBox(height: 24),
                            for (var index = 0; index < calls.length; index++) ...[
                              _buildCallCard(context, calls[index], index == 0),
                              if (index != calls.length - 1)
                                const SizedBox(height: 12),
                            ],
                            const SizedBox(height: 14),
                            _buildVoiceStatus(context),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCallCard(BuildContext context, CallRecord call, bool loudest) {
    final acknowledging = widget.acknowledgingIds.contains(call.id);
    final error = widget.ackErrors[call.id];
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: AppColors.board,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: loudest
              ? AppColors.redPen.withValues(alpha: 0.8)
              : AppColors.boardRim,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StudentAvatar(name: call.studentName, size: 38, onDark: true),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      call.studentName,
                      style: textTheme.titleMedium?.copyWith(
                        color: AppColors.chalk,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      call.message,
                      style: const TextStyle(
                        color: AppColors.chalk,
                        fontSize: 15.5,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatClock(call.createdAt),
                style: AppType.numeral(
                  context,
                  size: 12,
                  color: AppColors.chalkSoft,
                  weight: FontWeight.w500,
                ),
              ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.redPen.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.redPenOnBoard.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 16,
                    color: AppColors.redPenOnBoard,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '确认失败：$error',
                      style: const TextStyle(
                        color: AppColors.redPenOnBoard,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: loudest
                ? FilledButton(
                    onPressed: acknowledging
                        ? null
                        : () => widget.onAcknowledge(call),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.redPen,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.redPenDeep,
                      disabledForegroundColor: Colors.white70,
                      minimumSize: const Size(0, 52),
                    ),
                    child: _answerLabel(acknowledging),
                  )
                : OutlinedButton(
                    onPressed: acknowledging
                        ? null
                        : () => widget.onAcknowledge(call),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.chalk,
                      minimumSize: const Size(0, 48),
                      side: const BorderSide(color: AppColors.boardRim),
                    ),
                    child: _answerLabel(acknowledging),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _answerLabel(bool acknowledging) {
    if (!acknowledging) {
      return const Text('收到了，马上回应');
    }
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: 10),
        Text('正在确认…'),
      ],
    );
  }

  Widget _buildVoiceStatus(BuildContext context) {
    final details = switch (widget.voiceStatus) {
      VoiceReminderStatus.requesting => (
        null,
        AppColors.chalkSoft,
        '正在调用后端语音接口…',
      ),
      VoiceReminderStatus.playing => (
        Icons.graphic_eq_rounded,
        AppColors.jadeOnBoard,
        widget.voiceNote,
      ),
      VoiceReminderStatus.empty => (
        Icons.volume_off_outlined,
        AppColors.chalkSoft,
        widget.voiceNote,
      ),
      VoiceReminderStatus.failed => (
        Icons.error_outline_rounded,
        AppColors.amberOnBoard,
        widget.voiceNote,
      ),
      VoiceReminderStatus.idle => (
        Icons.graphic_eq_rounded,
        AppColors.chalkSoft,
        '准备语音提醒…',
      ),
    };

    final icon = details.$1;
    final color = details.$2;
    final note = details.$3;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.boardRim),
      ),
      child: Row(
        children: [
          if (widget.voiceStatus == VoiceReminderStatus.requesting)
            SizedBox.square(
              dimension: 15,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            )
          else
            Icon(icon, size: 16, color: color),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              note,
              style: TextStyle(color: color, fontSize: 11.5, height: 1.5),
            ),
          ),
          if (widget.voiceStatus == VoiceReminderStatus.failed)
            TextButton(
              onPressed: widget.onRetryVoice,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.amberOnBoard,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('重试'),
            ),
        ],
      ),
    );
  }
}

/// 来电时的铃声脉冲：红色只在这里、以及「待回应」的姓名牌角上出现。
class _Ringer extends StatefulWidget {
  const _Ringer({required this.size});

  final double size;

  @override
  State<_Ringer> createState() => _RingerState();
}

class _RingerState extends State<_Ringer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (prefersReducedMotion(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) => Stack(
            alignment: Alignment.center,
            children: [
              for (var index = 0; index < 2; index++) _buildRing(index),
              child!,
            ],
          ),
          child: Container(
            width: widget.size * 0.5,
            height: widget.size * 0.5,
            decoration: const BoxDecoration(
              color: AppColors.redPen,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_rounded,
              size: 30,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRing(int index) {
    final reduced = prefersReducedMotion(context);
    final progress = reduced ? (0.45 + index * 0.28) : (_controller.value + index / 2) % 1;
    final eased = Curves.easeOut.transform(progress);
    final ringSize = widget.size * (0.52 + eased * 0.48);
    final opacity = reduced ? 0.26 : 0.14 + (1 - progress) * 0.46;

    return Container(
      width: ringSize,
      height: ringSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: AppColors.redPenOnBoard.withValues(alpha: opacity),
          width: 1.6,
        ),
      ),
    );
  }
}
