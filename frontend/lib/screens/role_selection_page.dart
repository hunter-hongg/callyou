import 'package:flutter/material.dart';

import '../api_client.dart';
import '../device_wording.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'student_dashboard.dart';
import 'teacher_dashboard.dart';

enum EntryRole { teacher, student }

class RoleSelectionPage extends StatefulWidget {
  const RoleSelectionPage({
    super.key,
    required this.api,
    required this.session,
  });

  final ApiClient api;
  final AuthSession session;

  @override
  State<RoleSelectionPage> createState() => _RoleSelectionPageState();
}

class _RoleSelectionPageState extends State<RoleSelectionPage> {
  EntryRole? _selectedRole;

  void _exit() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _enterClassroom() {
    final role = _selectedRole;
    if (role == null) return;

    if (role == EntryRole.teacher) {
      Navigator.of(context).push(
        appPageRoute<void>(
          TeacherDashboard(api: widget.api, session: widget.session),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      appPageRoute<void>(
        StudentDashboard(api: widget.api, session: widget.session),
      ),
    );
  }

  @override
  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: PageBackdrop(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                child: ClassroomHeader(
                  account: widget.session.account,
                  roleLabel: '身份选择',
                  roleColor: AppColors.ink,
                  roleIcon: Icons.grid_view_rounded,
                  onExit: _exit,
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, viewport) => SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 36),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: viewport.maxHeight,
                      ),
                      child: Align(
                        alignment: const Alignment(0, -0.3),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1020),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(height: 30),
                              Text(roleSelectionTitle, style: textTheme.displaySmall),
                              const SizedBox(height: 8),
                              Text(
                                roleSelectionIntro,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: AppColors.muted,
                                ),
                              ),
                              const SizedBox(height: 24),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final cards = [
                                    _RoleCard(
                                      title: '教师端',
                                      description: teacherRoleDescription,
                                      icon: Icons.co_present_rounded,
                                      accent: AppColors.redPen,
                                      motif: const _RoleMotif(
                                        glow: AppColors.redPenOnBoard,
                                        icon: Icons.touch_app_rounded,
                                      ),
                                      features: const [
                                        '查看学生名单与在线状态',
                                        '选择学生并发起即时呼叫',
                                        '实时查看「待回应 / 已确认」',
                                      ],
                                      footerLabel: teacherFooterLabel,
                                      selected:
                                          _selectedRole == EntryRole.teacher,
                                      onTap: () {
                                        setState(
                                          () =>
                                              _selectedRole = EntryRole.teacher,
                                        );
                                      },
                                    ),
                                    _RoleCard(
                                      title: '学生端',
                                      description: studentRoleDescription,
                                      icon: Icons.school_rounded,
                                      accent: AppColors.jade,
                                      motif: const _RoleMotif(
                                        glow: AppColors.jadeOnBoard,
                                        icon:
                                            Icons.notifications_active_rounded,
                                        named: false,
                                      ),
                                      features: const [
                                        '接收账号下的所有呼叫',
                                        '每 2 秒自动检查新呼叫',
                                        '接收提醒并自动播放语音',
                                      ],
                                      footerLabel: studentFooterLabel,
                                      selected:
                                          _selectedRole == EntryRole.student,
                                      onTap: () {
                                        setState(
                                          () =>
                                              _selectedRole = EntryRole.student,
                                        );
                                      },
                                    ),
                                  ];

                                  if (constraints.maxWidth < 760) {
                                    return Column(
                                      children: [
                                        cards[0],
                                        const SizedBox(height: 14),
                                        cards[1],
                                      ],
                                    );
                                  }
                                  return Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(child: cards[0]),
                                      const SizedBox(width: 16),
                                      Expanded(child: cards[1]),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 22),
                              _buildBottomAction(context),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomAction(BuildContext context) {
    final label = switch (_selectedRole) {
      EntryRole.teacher => '进入教师端',
      EntryRole.student => '进入学生端',
      null => '请选择身份',
    };
    final accent = switch (_selectedRole) {
      EntryRole.teacher => AppColors.redPen,
      _ => AppColors.board,
    };
    final button = FilledButton(
      onPressed: _selectedRole != null ? _enterClassroom : null,
      style: FilledButton.styleFrom(
        minimumSize: const Size(220, 52),
        backgroundColor: accent,
      ),
      child: Text(label),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final hint = Text(
          _selectedRole != null ? '身份确认后将进入当前课堂。' : '先选一种身份，再进入课堂。',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: AppColors.muted),
        );
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [button, const SizedBox(height: 10), hint],
          );
        }
        return Row(
          children: [
            Expanded(child: hint),
            const SizedBox(width: 20),
            button,
          ],
        );
      },
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.accent,
    required this.motif,
    required this.features,
    required this.footerLabel,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color accent;
  final _RoleMotif motif;
  final List<String> features;
  final String footerLabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      selected: selected,
      label: title,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? accent : AppColors.rule,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: selected
                              ? accent
                              : accent.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(
                          icon,
                          color: selected ? Colors.white : accent,
                          size: 21,
                        ),
                      ),
                      const Spacer(),
                      if (selected)
                        Text(
                          '已选',
                          style: textTheme.labelMedium?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(title, style: textTheme.headlineSmall),
                  const SizedBox(height: 7),
                  Text(
                    description,
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 16),
                  motif,
                  const SizedBox(height: 18),
                  for (final feature in features)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              color: accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              feature,
                              style: textTheme.bodyMedium?.copyWith(
                                color: AppColors.inkSoft,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.only(top: 12),
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: AppColors.rule)),
                    ),
                    child: Text(
                      footerLabel,
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 小黑板条：老师那侧是「点中一块姓名牌」，学生那侧是「牌子响起来」。
class _RoleMotif extends StatelessWidget {
  const _RoleMotif({required this.glow, required this.icon, this.named = true});

  final Color glow;
  final IconData icon;
  final bool named;

  @override
  Widget build(BuildContext context) {
    return BoardPanel(
      depth: 1,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      child: Row(
        children: [
          for (var i = 0; i < 3; i++) ...[
            Expanded(
              child: Container(
                height: 30,
                decoration: BoxDecoration(
                  color: named && i == 1
                      ? AppColors.chalk.withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: i == (named ? 1 : 0)
                        ? AppColors.redPenOnBoard
                        : AppColors.boardRim,
                    width: i == (named ? 1 : 0) ? 1.4 : 1,
                  ),
                ),
                child: named && i == 1
                    ? const Center(
                        child: Text(
                          '张小明',
                          style: TextStyle(
                            color: AppColors.chalk,
                            fontSize: 11.5,
                            height: 1.2,
                          ),
                        ),
                      )
                    : null,
              ),
            ),
            if (i != 2) const SizedBox(width: 8),
          ],
          const SizedBox(width: 13),
          Icon(icon, size: 17, color: glow),
        ],
      ),
    );
  }
}
