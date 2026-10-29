import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api_client.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';
import '../tts_player.dart';
import '../widgets/ui.dart';
import 'incoming_call_overlay.dart';

class StudentDashboard extends StatefulWidget {
  const StudentDashboard({
    super.key,
    required this.api,
    required this.session,
    this.ttsPlayer,
  });

  final ApiClient api;
  final AuthSession session;

  /// 可注入的语音播放器；未注入时使用跨平台默认实现。
  final TtsPlayer? ttsPlayer;

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> {
  static const _pollInterval = Duration(seconds: 2);

  Timer? _pollTimer;
  bool _pollInFlight = false;
  bool _connected = false;
  String? _connectionError;
  DateTime? _lastChecked;

  List<CallRecord> _pendingCalls = const [];
  final Set<String> _alertedCallIds = {};
  final Set<String> _acknowledgingIds = {};
  final Map<String, String> _ackErrors = {};
  VoiceReminderStatus _voiceStatus = VoiceReminderStatus.idle;
  String _voiceNote = '';
  int _voiceRequestToken = 0;
  final List<CallRecord> _history = [];
  TtsPlayer? _ttsPlayer;

  /// 懒创建播放器：没有呼叫进来、没有可播的音频时，不占用音频资源。
  TtsPlayer get _player =>
      _ttsPlayer ??= widget.ttsPlayer ?? AudioTtsPlayer();

  @override
  void initState() {
    super.initState();
    unawaited(_poll());
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      unawaited(_poll());
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    // 注入的播放器归调用方管理，这里只释放自己创建的那一个。
    if (widget.ttsPlayer == null) unawaited(_ttsPlayer?.dispose());
    super.dispose();
  }

  Future<void> _poll() async {
    if (_pollInFlight) return;
    _pollInFlight = true;

    try {
      final calls = await widget.api.fetchPendingCalls();
      if (!mounted) return;

      final pendingIds = calls.map((call) => call.id).toSet();
      _alertedCallIds.removeWhere((id) => !pendingIds.contains(id));
      final newCalls = calls
          .where((call) => !_alertedCallIds.contains(call.id))
          .toList();

      setState(() {
        _connected = true;
        _connectionError = null;
        _lastChecked = DateTime.now();
        _pendingCalls = calls;
        _ackErrors.removeWhere((id, _) => !pendingIds.contains(id));

        if (calls.isEmpty) {
          _voiceStatus = VoiceReminderStatus.idle;
          _voiceNote = '';
        } else if (newCalls.isNotEmpty) {
          _voiceStatus = VoiceReminderStatus.requesting;
          _voiceNote = '正在调用后端语音接口…';
        }
      });

      if (newCalls.isNotEmpty) {
        unawaited(_playAlertSound());
        for (final call in newCalls) {
          _alertedCallIds.add(call.id);
          unawaited(_requestVoice(call));
        }
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _connected = false;
        _connectionError = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _connected = false;
        _connectionError = '无法连接课堂服务器，正在自动重试。';
      });
    } finally {
      _pollInFlight = false;
    }
  }

  Future<void> _playAlertSound() async {
    try {
      await SystemSound.play(SystemSoundType.alert);
    } catch (_) {
      // Some desktop and web targets do not expose a system alert sound.
    }
  }

  Future<void> _requestVoice(CallRecord call) async {
    final token = ++_voiceRequestToken;
    if (mounted && _pendingCalls.any((item) => item.id == call.id)) {
      setState(() {
        _voiceStatus = VoiceReminderStatus.requesting;
        _voiceNote = '正在调用后端语音接口…';
      });
    }

    try {
      final result = await widget.api.synthesize(
        '${call.studentName}同学，${call.message}',
      );
      if (!mounted || !_pendingCalls.any((item) => item.id == call.id)) {
        return;
      }
      if (result.hasAudio) {
        final audio = result.audio;
        if (token == _voiceRequestToken) {
          setState(() {
            _voiceStatus = VoiceReminderStatus.playing;
            _voiceNote = '语音提醒正在播放（${audio.length} 字节）…';
          });
        }
        // play 返回的 Future 在这个片段播完时才完成；多个片段按先进先出
        // 依次念完，不会互相打断。结果只在这个请求仍是最新时更新界面。
        unawaited(
          _player.play(audio, contentType: result.contentType).then(
                (_) {
                  if (!mounted || token != _voiceRequestToken) return;
                  setState(() {
                    _voiceStatus = VoiceReminderStatus.ready;
                    _voiceNote =
                        '语音提醒已播放完毕（${audio.length} 字节）。';
                  });
                },
                onError: (Object error, StackTrace stackTrace) {
                  if (!mounted || token != _voiceRequestToken) return;
                  setState(() {
                    _voiceStatus = VoiceReminderStatus.failed;
                    _voiceNote = '音频播放失败，可点「重试」重新合成播放。';
                  });
                },
              ),
        );
      } else if (token == _voiceRequestToken) {
        setState(() {
          _voiceStatus = VoiceReminderStatus.empty;
          _voiceNote = '后端语音接口已调用，当前返回空音频；文字呼叫已正常显示。';
        });
      }
    } on ApiException catch (error) {
      if (!mounted ||
          !_pendingCalls.any((item) => item.id == call.id) ||
          token != _voiceRequestToken) {
        return;
      }
      setState(() {
        _voiceStatus = VoiceReminderStatus.failed;
        _voiceNote = '语音接口请求失败：${error.message}';
      });
    } catch (_) {
      if (!mounted ||
          !_pendingCalls.any((item) => item.id == call.id) ||
          token != _voiceRequestToken) {
        return;
      }
      setState(() {
        _voiceStatus = VoiceReminderStatus.failed;
        _voiceNote = '语音接口请求失败，可稍后重试。';
      });
    }
  }

  void _retryVoice() {
    if (_pendingCalls.isEmpty) return;
    unawaited(_requestVoice(_pendingCalls.first));
  }

  Future<void> _acknowledge(CallRecord call) async {
    if (_acknowledgingIds.contains(call.id)) return;

    setState(() {
      _acknowledgingIds.add(call.id);
      _ackErrors.remove(call.id);
    });

    try {
      final acknowledged = await widget.api.acknowledgeCall(
        callId: call.id,
      );
      if (!mounted) return;

      _voiceRequestToken++;
      setState(() {
        _history.removeWhere((item) => item.id == acknowledged.id);
        _history.insert(0, acknowledged);
        _pendingCalls = _pendingCalls
            .where((item) => item.id != acknowledged.id)
            .toList();
        _alertedCallIds.remove(acknowledged.id);
        _acknowledgingIds.remove(acknowledged.id);
        if (_pendingCalls.isEmpty) {
          _voiceStatus = VoiceReminderStatus.idle;
          _voiceNote = '';
        }
      });
      showAppSnackBar(context, '已回应 ${acknowledged.studentName} 的呼叫');
      unawaited(_poll());
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _acknowledgingIds.remove(call.id);
        _ackErrors[call.id] = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _acknowledgingIds.remove(call.id);
        _ackErrors[call.id] = '确认失败，请稍后再试。';
      });
    }
  }

  void _exit() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  String get _connectionLabel {
    if (_connected) return '学生端在线';
    if (_lastChecked == null) return '正在连接';
    return '连接中断';
  }

  Color get _connectionColor {
    if (_connected) return AppColors.jade;
    if (_lastChecked == null) return AppColors.muted;
    return AppColors.amber;
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pendingCalls;

    return Scaffold(
      body: Stack(
        children: [
          PageBackdrop(
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ClassroomHeader(
                          account: widget.session.account,
                          roleLabel: '学生端',
                          roleColor: AppColors.jade,
                          roleIcon: Icons.school_rounded,
                          onExit: _exit,
                        ),
                        const SizedBox(height: 24),
                        _buildHero(context),
                        const SizedBox(height: 20),
                        _buildContent(context),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: pending.isEmpty
                  ? const SizedBox.expand(key: ValueKey('no-incoming-call'))
                  : IncomingCallOverlay(
                      key: ValueKey(
                        pending.map((call) => call.id).join(','),
                      ),
                      calls: pending,
                      voiceStatus: _voiceStatus,
                      voiceNote: _voiceNote,
                      acknowledgingIds: _acknowledgingIds,
                      ackErrors: _ackErrors,
                      onAcknowledge: _acknowledge,
                      onRetryVoice: _retryVoice,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHero(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('统一学生端已就绪', style: textTheme.displaySmall),
        const SizedBox(height: 7),
        Text(
          '这台设备接收课堂账号下的全部呼叫，无需刷新。',
          style: textTheme.bodyMedium?.copyWith(color: AppColors.muted),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final status = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Dot(color: _connectionColor),
            const SizedBox(width: 8),
            Text(
              _connectionLabel,
              style: textTheme.titleSmall?.copyWith(color: _connectionColor),
            ),
            const SizedBox(width: 18),
            Text(
              _lastChecked == null
                  ? '--:--:--'
                  : formatClockWithSeconds(_lastChecked!),
              style: AppType.numeral(
                context,
                size: 15,
                color: AppColors.muted,
              ),
            ),
          ],
        );

        if (constraints.maxWidth < 700) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [heading, const SizedBox(height: 14), status],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: heading),
            const SizedBox(width: 20),
            status,
          ],
        );
      },
    );
  }

  Widget _buildContent(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final listening = _buildListeningPanel(context);
        final side = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHistoryCard(context),
            const SizedBox(height: 16),
            _buildVoiceCard(context),
          ],
        );

        if (constraints.maxWidth < 980) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [listening, const SizedBox(height: 16), side],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 6, child: listening),
            const SizedBox(width: 18),
            Expanded(flex: 5, child: side),
          ],
        );
      },
    );
  }

  Widget _buildListeningPanel(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final connected = _connectionError == null;

    return BoardPanel(
      depth: 1,
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
      child: Column(
        children: [
          const _PollHeart(active: true),
          const SizedBox(height: 22),
          Text(
            connected ? '正在聆听' : '连接中断',
            style: textTheme.headlineMedium?.copyWith(
              color: connected ? AppColors.chalk : AppColors.amberOnBoard,
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Text(
              connected
                  ? '后台每 2 秒检查一次本账号的新呼叫，来了就会全屏弹出。'
                  : _connectionError!,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.chalkSoft,
                height: 1.7,
              ),
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              _BoardStat(
                label: '检查间隔',
                value: '2 秒',
              ),
              const SizedBox(width: 20),
              _BoardStat(
                label: '上次检查',
                value: _lastChecked == null
                    ? '--:--:--'
                    : formatClockWithSeconds(_lastChecked!),
                numeral: true,
              ),
              const Spacer(),
              if (!connected)
                TextButton(
                  onPressed: () => unawaited(_poll()),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.amberOnBoard,
                  ),
                  child: const Text('立即检查'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return SectionCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelHeader(
            title: '已回应的呼叫',
            subtitle: '本次打开学生端以来的回应记录。',
            trailing: StatusPill(
              label: '${_history.length} 条',
              color: AppColors.jade,
              icon: Icons.checklist_rounded,
            ),
          ),
          const SizedBox(height: 8),
          if (_history.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 26),
              child: Row(
                children: [
                  Icon(
                    Icons.notifications_none_rounded,
                    size: 20,
                    color: AppColors.muted.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '还没有回应的呼叫。收到来电后，按下「收到了，马上回应」就会记录在这里。',
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            for (final call in _history) _HistoryRow(call: call),
        ],
      ),
    );
  }

  Widget _buildVoiceCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.jadeSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.jade.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.graphic_eq_rounded,
            color: AppColors.jade,
            size: 18,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '语音提醒已接入',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 3),
                Text(
                  '收到呼叫时自动调用并播放课堂后端的语音提醒；接口返回空音频时，文字提醒照常显示。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.inkSoft,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _BoardStat extends StatelessWidget {
  const _BoardStat({required this.label, required this.value, this.numeral = false});

  final String label;
  final String value;
  final bool numeral;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: numeral
              ? AppType.numeral(context, size: 16, color: AppColors.chalk)
              : Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.chalk,
                ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.chalkSoft.withValues(alpha: 0.75),
          ),
        ),
      ],
    );
  }
}

/// 每 2 秒一跳的铃声脉冲。系统「减少动态效果」打开时静止显示。
class _PollHeart extends StatefulWidget {
  const _PollHeart({required this.active});

  final bool active;

  @override
  State<_PollHeart> createState() => _PollHeartState();
}

class _PollHeartState extends State<_PollHeart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
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
    const size = 132.0;
    final tone = widget.active ? AppColors.jadeOnBoard : AppColors.amberOnBoard;

    return RepaintBoundary(
      child: SizedBox.square(
        dimension: size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) => Stack(
            alignment: Alignment.center,
            children: [
              for (var index = 0; index < 2; index++)
                _buildRing(size, index, tone),
              child!,
            ],
          ),
          child: Container(
            width: size * 0.44,
            height: size * 0.44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: tone, width: 1.6),
            ),
            child: Icon(Icons.notifications_rounded, color: tone, size: 30),
          ),
        ),
      ),
    );
  }

  Widget _buildRing(double size, int index, Color tone) {
    final progress = prefersReducedMotion(context)
        ? (0.35 + index * 0.3)
        : (_controller.value + index / 2) % 1;
    final eased = Curves.easeOut.transform(progress);
    final ringSize = size * (0.48 + eased * 0.52);
    final opacity = 0.12 + (1 - progress) * 0.42;

    return Container(
      width: ringSize,
      height: ringSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: tone.withValues(alpha: opacity), width: 1.4),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.call});

  final CallRecord call;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.rule)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_rounded, size: 16, color: AppColors.jade),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${call.studentName}：${call.message}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.inkSoft,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  formatClock(call.createdAt),
                  style: AppType.numeral(
                    context,
                    size: 11.5,
                    color: AppColors.muted,
                    weight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const StatusPill(
            label: '已确认',
            color: AppColors.jade,
            icon: Icons.check_circle_outline_rounded,
          ),
        ],
      ),
    );
  }
}
