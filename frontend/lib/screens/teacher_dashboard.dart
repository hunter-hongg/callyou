import 'dart:async';

import 'package:flutter/material.dart';

import '../api_client.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/ui.dart';

class TeacherDashboard extends StatefulWidget {
  const TeacherDashboard({super.key, required this.api, required this.session});

  final ApiClient api;
  final AuthSession session;

  @override
  State<TeacherDashboard> createState() => _TeacherDashboardState();
}

class _TeacherDashboardState extends State<TeacherDashboard> {
  static const _pollInterval = Duration(seconds: 2);
  static const _quickMessages = ['请到办公室来一下', '请回答这个问题', '请到讲台前来', '请安静一下'];

  final _messageController = TextEditingController();
  Timer? _timer;

  List<Student> _students = const [];
  List<CallRecord> _calls = const [];
  bool _studentOnline = false;
  String? _selectedStudentId;
  String? _loadError;
  bool _connected = true;
  bool _initialLoading = true;
  bool _refreshing = false;
  bool _sending = false;
  DateTime? _lastSync;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh(showLoading: true));
    _timer = Timer.periodic(_pollInterval, (_) {
      unawaited(_refresh());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _refresh({bool showLoading = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    if (showLoading && mounted) {
      setState(() {
        _initialLoading = true;
        _loadError = null;
      });
    }

    try {
      final results = await Future.wait<Object>([
        widget.api.fetchStudents(),
        widget.api.fetchCalls(limit: 20),
      ]);
      if (!mounted) return;

      final roster = results[0] as StudentRoster;
      final calls = results[1] as List<CallRecord>;
      setState(() {
        _students = roster.students;
        _studentOnline = roster.studentOnline;
        _calls = calls;
        _connected = true;
        _initialLoading = false;
        _loadError = null;
        _lastSync = DateTime.now();
        if (_selectedStudentId != null &&
            !_students.any((student) => student.id == _selectedStudentId)) {
          _selectedStudentId = null;
        }
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _connected = false;
        _initialLoading = false;
        if (_students.isEmpty) {
          _loadError = error.message;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _connected = false;
        _initialLoading = false;
        if (_students.isEmpty) {
          _loadError = '无法连接课堂服务器，请检查后端是否已启动。';
        }
      });
    } finally {
      _refreshing = false;
    }
  }

  Student? get _selectedStudent {
    for (final student in _students) {
      if (student.id == _selectedStudentId) return student;
    }
    return null;
  }

  CallRecord? get _selectedPendingCall {
    final studentId = _selectedStudentId;
    if (studentId == null) return null;
    for (final call in _calls) {
      if (call.studentId == studentId && !call.isAcknowledged) {
        return call;
      }
    }
    return null;
  }

  CallRecord? _pendingCallFor(String studentId) {
    for (final call in _calls) {
      if (call.studentId == studentId && !call.isAcknowledged) {
        return call;
      }
    }
    return null;
  }

  int get _pendingCount => _calls.where((call) => !call.isAcknowledged).length;

  Future<void> _sendCall() async {
    final student = _selectedStudent;
    if (student == null || _sending || _selectedPendingCall != null) return;

    setState(() => _sending = true);
    try {
      final call = await widget.api.createCall(
        studentId: student.id,
        message: _messageController.text.trim(),
      );
      if (!mounted) return;
      _messageController.clear();
      setState(() {
        _calls = [call, ..._calls.where((existing) => existing.id != call.id)];
      });
      showAppSnackBar(context, '已向 ${student.name} 发起呼叫');
      unawaited(_refresh());
    } on ApiException catch (error) {
      if (!mounted) return;
      showAppSnackBar(context, error.message, error: true);
      unawaited(_refresh());
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(context, '发起呼叫失败，请稍后再试。', error: true);
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  void _exit() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageBackdrop(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1240),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClassroomHeader(
                      account: widget.session.account,
                      roleLabel: '教师端',
                      roleColor: AppColors.redPen,
                      roleIcon: Icons.co_present_rounded,
                      identity: '老师',
                      onExit: _exit,
                    ),
                    const SizedBox(height: 26),
                    _buildHero(context),
                    if (!_connected && !_initialLoading) ...[
                      const SizedBox(height: 14),
                      _buildConnectionBanner(context),
                    ],
                    const SizedBox(height: 22),
                    _buildWorkspace(context),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHero(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('课堂指挥台', style: textTheme.displaySmall),
        const SizedBox(height: 7),
        Text(
          '选一位学生，发出呼叫。回应状态每 2 秒自动同步。',
          style: textTheme.bodyMedium?.copyWith(color: AppColors.muted),
        ),
      ],
    );

    final metrics = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Metric(
          label: '学生端',
          value: _studentOnline ? '在线' : '离线',
          tone: _studentOnline ? AppColors.jade : AppColors.muted,
        ),
        _Metric(
          label: '待回应',
          value: '$_pendingCount',
          tone: _pendingCount > 0 ? AppColors.redPen : AppColors.muted,
        ),
        _Metric(
          label: '同步于',
          value: _lastSync == null
              ? '--:--:--'
              : formatClockWithSeconds(_lastSync!),
          tone: AppColors.ink,
          numeral: true,
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 920) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading,
              const SizedBox(height: 18),
              Wrap(
                spacing: 22,
                runSpacing: 14,
                children: [
                  _Metric(
                    label: '学生端',
                    value: _studentOnline ? '在线' : '离线',
                    tone: _studentOnline ? AppColors.jade : AppColors.muted,
                  ),
                  _Metric(
                    label: '待回应',
                    value: '$_pendingCount',
                    tone: _pendingCount > 0 ? AppColors.redPen : AppColors.muted,
                  ),
                  _Metric(
                    label: '同步于',
                    value: _lastSync == null
                        ? '--:--:--'
                        : formatClockWithSeconds(_lastSync!),
                    tone: AppColors.ink,
                    numeral: true,
                  ),
                ],
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: heading),
            const SizedBox(width: 24),
            metrics,
          ],
        );
      },
    );
  }

  Widget _buildConnectionBanner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.amberSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 18,
            color: AppColors.amber,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '与课堂服务器的连接暂时中断，正在自动重试。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.amber,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: () => unawaited(_refresh()),
            child: const Text('立即重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkspace(BuildContext context) {
    if (_initialLoading) {
      return const SectionCard(
        child: SizedBox(
          height: 220,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.jade,
                ),
              ),
              SizedBox(height: 14),
              Text('正在连接课堂…'),
            ],
          ),
        ),
      );
    }

    if (_loadError != null && _students.isEmpty) {
      return SectionCard(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              children: [
                const Icon(
                  Icons.cloud_off_rounded,
                  color: AppColors.redPen,
                  size: 30,
                ),
                const SizedBox(height: 14),
                Text('暂时无法载入课堂', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  _loadError!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: () => unawaited(_refresh(showLoading: true)),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('重新连接'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1000;
        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildStudentRoster(context),
              const SizedBox(height: 16),
              _buildCallConsole(context),
              const SizedBox(height: 16),
              _buildRecentCalls(context),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 6, child: _buildStudentRoster(context)),
            const SizedBox(width: 18),
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildCallConsole(context),
                  const SizedBox(height: 16),
                  _buildRecentCalls(context),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStudentRoster(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return SectionCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelHeader(
            title: '座次表',
            subtitle: '点一块姓名牌，把他设为本次呼叫对象。',
            trailing: Text(
              '${_students.length} 人',
              style: AppType.numeral(
                context,
                size: 13,
                color: AppColors.muted,
                weight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_students.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 30),
              alignment: Alignment.center,
              child: Text(
                '课堂中还没有学生，请确认后端已启动。',
                style: textTheme.bodyMedium?.copyWith(color: AppColors.muted),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 560
                    ? 3
                    : (constraints.maxWidth >= 380 ? 2 : 1);
                const gap = 10.0;
                final plateWidth =
                    (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final student in _students)
                      SizedBox(
                        width: plateWidth,
                        child: _SeatPlate(
                          student: student,
                          selected: student.id == _selectedStudentId,
                          pending: _pendingCallFor(student.id) != null,
                          onTap: () {
                            setState(() => _selectedStudentId = student.id);
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.rule)),
            ),
            child: Row(
              children: [
                const _CornerWedge(size: 13, color: AppColors.redPen),
                const SizedBox(width: 8),
                Text(
                  '红角＝呼叫已发出，等待回应',
                  style: textTheme.bodySmall?.copyWith(color: AppColors.muted),
                ),
                const Spacer(),
                Text(
                  _studentOnline ? '学生端在线' : '学生端离线',
                  style: textTheme.bodySmall?.copyWith(
                    color: _studentOnline ? AppColors.jade : AppColors.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallConsole(BuildContext context) {
    final selected = _selectedStudent;
    final pendingCall = _selectedPendingCall;
    final canCall = selected != null && pendingCall == null && !_sending;

    return BoardPanel(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '红笔 · 发起呼叫',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.chalk,
                  ),
                ),
              ),
              StatusPill(
                label: _connected ? '通道在线' : '正在重连',
                color: _connected ? AppColors.jadeOnBoard : AppColors.amberOnBoard,
                background: Colors.transparent,
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (selected == null)
            _buildEmptyConsole(context)
          else ...[
            Row(
              children: [
                StudentAvatar(name: selected.name, size: 48, onDark: true),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selected.name,
                        style: const TextStyle(
                          color: AppColors.chalk,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        pendingCall != null
                            ? '呼叫已发出，正在等待学生端回应'
                            : _studentOnline
                            ? '学生端在线 · 可立即接收呼叫'
                            : '学生端离线 · 上线后会收到呼叫',
                        style: TextStyle(
                          color: pendingCall != null
                              ? AppColors.redPenOnBoard
                              : AppColors.chalkSoft,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              '呼叫说明（可选）',
              style: TextStyle(
                color: AppColors.chalkSoft,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('callMessageField'),
              controller: _messageController,
              style: const TextStyle(color: AppColors.chalk, fontSize: 14),
              cursorColor: AppColors.redPenOnBoard,
              maxLines: 2,
              minLines: 1,
              maxLength: 120,
              decoration: InputDecoration(
                hintText: '例如：请带上课本到办公室。',
                hintStyle: TextStyle(
                  color: AppColors.chalk.withValues(alpha: 0.32),
                  fontSize: 13,
                ),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                counterStyle: TextStyle(
                  color: AppColors.chalk.withValues(alpha: 0.3),
                  fontSize: 10,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: AppColors.chalk.withValues(alpha: 0.16),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: AppColors.chalk.withValues(alpha: 0.16),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: AppColors.redPenOnBoard,
                    width: 1.4,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final message in _quickMessages)
                  _QuickMessageChip(
                    label: message,
                    onTap: () {
                      _messageController.value = TextEditingValue(
                        text: message,
                        selection: TextSelection.collapsed(
                          offset: message.length,
                        ),
                      );
                    },
                  ),
              ],
            ),
            const SizedBox(height: 18),
            FilledButton(
              key: const Key('sendCallButton'),
              onPressed: canCall ? _sendCall : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.redPen,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.1),
                disabledForegroundColor: AppColors.chalk.withValues(alpha: 0.4),
                minimumSize: const Size.fromHeight(52),
              ),
              child: Text(
                pendingCall != null
                    ? '等待学生确认'
                    : _sending
                    ? '正在呼叫…'
                    : '呼叫 ${selected.name}',
              ),
            ),
            const SizedBox(height: 10),
            Text(
              pendingCall != null
                  ? '学生回应后按钮会自动恢复可用。'
                  : _studentOnline
                  ? '学生端每 2 秒自动检查一次新呼叫。'
                  : '呼叫会保留，学生端上线并开始检查后立即送达。',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.chalk.withValues(alpha: 0.45),
                fontSize: 11.5,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyConsole(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 8),
      child: Column(
        children: [
          const Icon(
            Icons.touch_app_outlined,
            color: AppColors.chalkSoft,
            size: 28,
          ),
          const SizedBox(height: 14),
          const Text(
            '先从座次表选一位学生',
            style: TextStyle(
              color: AppColors.chalk,
              fontSize: 16.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            '选中后可以写上呼叫说明，并向这位学生发出即时呼叫。',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.chalk.withValues(alpha: 0.5),
              fontSize: 12.5,
              height: 1.65,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentCalls(BuildContext context) {
    final recentCalls = _calls.take(6).toList(growable: false);

    return SectionCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelHeader(
            title: '最近的呼叫',
            subtitle: '学生回应后，状态会在这里更新。',
          ),
          const SizedBox(height: 6),
          if (recentCalls.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Row(
                children: [
                  Icon(
                    Icons.forum_outlined,
                    size: 20,
                    color: AppColors.muted.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '还没有发出过呼叫。选一位学生，写下说明，按下呼叫。',
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: AppColors.muted),
                  ),
                ],
              ),
            )
          else
            for (final call in recentCalls)
              _CallRow(call: call),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.tone,
    this.numeral = false,
  });

  final String label;
  final String value;
  final Color tone;
  final bool numeral;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: numeral
                ? AppType.numeral(context, size: 19, color: tone)
                : Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: tone,
                    fontWeight: FontWeight.w600,
                  ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

/// 右上角的斜角，就是老师红笔的一记勾画：只在「呼叫待回应」时出现。
class _CornerWedge extends StatelessWidget {
  const _CornerWedge({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _WedgePainter(color: color)),
    );
  }
}

class _WedgePainter extends CustomPainter {
  const _WedgePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width - size.width * 0.62, size.height)
      ..lineTo(0, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_WedgePainter old) => old.color != color;
}

class _SeatPlate extends StatelessWidget {
  const _SeatPlate({
    required this.student,
    required this.selected,
    required this.pending,
    required this.onTap,
  });

  final Student student;
  final bool selected;
  final bool pending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      selected: selected,
      label: student.name,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: selected ? AppColors.board : AppColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.board : AppColors.rule,
            width: 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              PositionedDirectional(
                top: 0,
                end: 0,
                child: pending
                    ? const _CornerWedge(size: 15, color: AppColors.redPen)
                    : const SizedBox.shrink(),
              ),
              InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(13, 12, 13, 11),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        student.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleMedium?.copyWith(
                          color: selected ? AppColors.chalk : AppColors.ink,
                          fontSize: 15.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            pending
                                ? Icons.notifications_active_rounded
                                : selected
                                ? Icons.check_circle_rounded
                                : Icons.circle_outlined,
                            size: 13,
                            color: selected
                                ? AppColors.chalkSoft
                                : pending
                                ? AppColors.redPen
                                : AppColors.muted,
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              pending ? '待回应' : selected ? '已选中' : '可呼叫',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall?.copyWith(
                                fontSize: 11.5,
                                color: selected
                                    ? AppColors.chalkSoft
                                    : pending
                                    ? AppColors.redPen
                                    : AppColors.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickMessageChip extends StatelessWidget {
  const _QuickMessageChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.chalk.withValues(alpha: 0.2)),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.chalkSoft,
              fontSize: 11.5,
              height: 1.3,
            ),
          ),
        ),
      ),
    );
  }
}

class _CallRow extends StatelessWidget {
  const _CallRow({required this.call});

  final CallRecord call;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final accent = call.isAcknowledged ? AppColors.jade : AppColors.redPen;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.rule)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 34,
            margin: const EdgeInsets.only(right: 12, top: 2),
            color: accent,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  call.message.isEmpty ? '老师正在呼叫你，请尽快回应。' : call.message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(color: AppColors.ink),
                ),
                const SizedBox(height: 3),
                Text(
                  call.studentName,
                  style: textTheme.bodySmall?.copyWith(color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            formatClock(call.createdAt),
            style: AppType.numeral(
              context,
              size: 12,
              color: AppColors.muted,
              weight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 12),
          if (call.isAcknowledged)
            const StatusPill(
              label: '已确认',
              color: AppColors.jade,
              icon: Icons.check_circle_outline_rounded,
            )
          else
            const StatusPill(
              label: '待回应',
              color: AppColors.redPen,
              icon: Icons.notifications_active_outlined,
            ),
        ],
      ),
    );
  }
}
