import 'package:flutter/material.dart';

import '../api_client.dart';
import '../device_wording.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'role_selection_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.api});

  final ApiClient api;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _registerFormKey = GlobalKey<FormState>();
  final _accountController = TextEditingController(text: 'callyou');
  final _passwordController = TextEditingController(text: '123456');
  final _regUsernameController = TextEditingController();
  final _regPasswordController = TextEditingController();
  final _regStudentsController = TextEditingController();

  bool _registerMode = false;
  bool _obscurePassword = true;
  bool _obscureRegisterPassword = true;
  bool _submitting = false;
  bool _registering = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _accountController.dispose();
    _passwordController.dispose();
    _regUsernameController.dispose();
    _regPasswordController.dispose();
    _regStudentsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final session = await widget.api.login(
        account: _accountController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      Navigator.of(context).push(
        appPageRoute<void>(
          RoleSelectionPage(api: widget.api, session: session),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '登录失败，请稍后再试。');
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _submitRegister() async {
    if (_registering) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (!(_registerFormKey.currentState?.validate() ?? false)) return;

    final username = _regUsernameController.text.trim();
    final password = _regPasswordController.text;

    setState(() {
      _registering = true;
      _error = null;
    });

    try {
      await widget.api.register(
        username: username,
        password: password,
        students: _regStudentsController.text,
      );
      if (!mounted) return;
      _accountController.text = username;
      _passwordController.text = password;
      setState(() {
        _registerMode = false;
        _success = '注册成功，已为你填好账号，点「进入课堂」登录即可。';
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '注册失败，请稍后再试。');
    } finally {
      if (mounted) {
        setState(() => _registering = false);
      }
    }
  }

  void _switchToRegister() {
    if (_registerMode || _submitting || _registering) return;
    setState(() {
      _registerMode = true;
      _error = null;
      _success = null;
    });
  }

  void _switchToLogin() {
    if (!_registerMode || _submitting || _registering) return;
    setState(() {
      _registerMode = false;
      _error = null;
      _success = null;
    });
  }

  void _clearError() {
    if (_error != null) {
      setState(() => _error = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageBackdrop(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide =
                  constraints.maxWidth >= 1040 && constraints.maxHeight >= 640;
              if (isWide) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 1160,
                        maxHeight: 660,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Expanded(flex: 11, child: _BrandPanel()),
                            Expanded(
                              flex: 9,
                              child: Container(
                                color: AppColors.card,
                                alignment: Alignment.center,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 40,
                                  vertical: 32,
                                ),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 360,
                                  ),
                                  child: _buildCard(context),
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

              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 26, 20, 32),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Center(
                          child: AppLogo(size: 42, showSubtitle: false),
                        ),
                        const SizedBox(height: 24),
                        _buildCard(context),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context) =>
      _registerMode ? _buildRegisterCard(context) : _buildLoginCard(context);

  Widget _buildLoginCard(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AutofillGroup(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('登录课堂', style: textTheme.displaySmall),
            const SizedBox(height: 8),
            Text(
              '教师端与学生端共用一个课堂账号，登录后再选择身份。',
              style: textTheme.bodyMedium?.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: 26),
            if (_success != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: AppColors.jadeSoft,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.jade.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.check_circle_outline_rounded,
                      size: 17,
                      color: AppColors.jade,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _success!,
                        style: textTheme.bodySmall?.copyWith(
                          color: AppColors.jade,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
            ],
            TextFormField(
              controller: _accountController,
              autofillHints: const [AutofillHints.username],
              textInputAction: TextInputAction.next,
              onChanged: (_) => _clearError(),
              decoration: const InputDecoration(
                labelText: '课堂账号',
                hintText: '请输入课堂账号',
                prefixIcon: Icon(Icons.badge_outlined, size: 20),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '请输入课堂账号';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passwordController,
              autofillHints: const [AutofillHints.password],
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              onChanged: (_) => _clearError(),
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: '课堂密码',
                hintText: '请输入课堂密码',
                prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                suffixIcon: IconButton(
                  tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                  onPressed: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 19,
                  ),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return '请输入课堂密码';
                }
                return null;
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: AppColors.redPenSoft,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.redPen.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 17,
                      color: AppColors.redPen,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: textTheme.bodySmall?.copyWith(
                          color: AppColors.redPenDeep,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: _submitting
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox.square(
                          dimension: 17,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.chalk,
                          ),
                        ),
                        SizedBox(width: 10),
                        Text('正在进入课堂…'),
                      ],
                    )
                  : const Text('进入课堂'),
            ),
            const SizedBox(height: 16),
            Text(
              classroomDeviceLoginHint,
              style: textTheme.bodySmall?.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.center,
              child: TextButton(
                onPressed: _submitting ? null : _switchToRegister,
                child: const Text('还没有课堂账号？先注册'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRegisterCard(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AutofillGroup(
      child: Form(
        key: _registerFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('注册课堂账号', style: textTheme.displaySmall),
            const SizedBox(height: 8),
            Text(
              '填写用户名、密码和学生名单，注册后用该账号登录课堂。',
              style: textTheme.bodyMedium?.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: 26),
            TextFormField(
              controller: _regUsernameController,
              autofillHints: const [AutofillHints.username],
              textInputAction: TextInputAction.next,
              onChanged: (_) => _clearError(),
              decoration: const InputDecoration(
                labelText: '用户名',
                hintText: '请输入用户名',
                prefixIcon: Icon(Icons.badge_outlined, size: 20),
              ),
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) {
                  return '请输入用户名';
                }
                if (text.runes.length > 32) {
                  return '用户名过长（最多 32 个字符）';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _regPasswordController,
              autofillHints: const [AutofillHints.password],
              obscureText: _obscureRegisterPassword,
              textInputAction: TextInputAction.next,
              onChanged: (_) => _clearError(),
              decoration: InputDecoration(
                labelText: '密码',
                hintText: '请输入密码',
                prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                suffixIcon: IconButton(
                  tooltip: _obscureRegisterPassword ? '显示密码' : '隐藏密码',
                  onPressed: () {
                    setState(
                      () => _obscureRegisterPassword = !_obscureRegisterPassword,
                    );
                  },
                  icon: Icon(
                    _obscureRegisterPassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 19,
                  ),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return '请输入密码';
                }
                if (value.runes.length > 64) {
                  return '密码过长（最多 64 个字符）';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _regStudentsController,
              minLines: 4,
              maxLines: 6,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submitRegister(),
              onChanged: (_) => _clearError(),
              style: textTheme.bodyMedium,
              decoration: const InputDecoration(
                labelText: '学生名单',
                hintText: '一行一个姓名，例如：\n张小明\n李思思',
                helperText: '一行一个姓名，换行分隔（最多 60 人）',
                prefixIcon: Icon(Icons.school_outlined, size: 20),
              ),
              validator: (value) {
                final names = _parseRosterNames(value ?? '');
                if (names.isEmpty) {
                  return '请至少填写一个学生姓名，一行一个';
                }
                if (names.length > 60) {
                  return '学生名单最多 60 人';
                }
                return null;
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: AppColors.redPenSoft,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.redPen.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 17,
                      color: AppColors.redPen,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: textTheme.bodySmall?.copyWith(
                          color: AppColors.redPenDeep,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _registering ? null : _submitRegister,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: _registering
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox.square(
                          dimension: 17,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.chalk,
                          ),
                        ),
                        SizedBox(width: 10),
                        Text('正在注册…'),
                      ],
                    )
                  : const Text('注册账号'),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.center,
              child: TextButton(
                onPressed: _registering ? null : _switchToLogin,
                child: const Text('已注册？返回登录'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static List<String> _parseRosterNames(String raw) {
    final names = <String>[];
    for (final line in raw.split('\n')) {
      final name = line.trim();
      if (name.isNotEmpty) {
        names.add(name);
      }
    }
    return names;
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    return BoardPanel(
      depth: 1,
      padding: const EdgeInsets.fromLTRB(40, 34, 40, 30),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showPreview = constraints.maxHeight >= 520;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppLogo(size: 40, onDark: true),
              const Spacer(),
              Text(
                '让每一次课堂呼叫，\n都被及时听见。',
                style: Theme.of(context).textTheme.displayMedium
                    ?.copyWith(color: AppColors.chalk, height: 1.24),
              ),
              const SizedBox(height: 16),
              Text(
                '老师在讲台按下呼叫，学生端每 2 秒检查一次，文字与语音提醒同时到达。',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: AppColors.chalkSoft, height: 1.8),
              ),
              if (showPreview) ...[
                const SizedBox(height: 30),
                const _SeatChartPreview(),
              ],
              const Spacer(),
              const Row(
                children: [
                  _SpecCell(label: '检查频率', value: '每 2 秒'),
                  _SpecCell(label: '送达范围', value: '账号下全部呼叫'),
                  _SpecCell(label: '提醒方式', value: '文字 + 语音接口'),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 一张座次表：右上角有红角的那位，正是被点到的学生。
class _SeatChartPreview extends StatelessWidget {
  const _SeatChartPreview();

  static const _names = ['张小明', '李思思', '王一诺', '陈子涵', '刘星辰', '赵雨桐'];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var row = 0; row < 2; row++) ...[
          Row(
            children: [
              for (var column = 0; column < 3; column++) ...[
                Expanded(
                  child: _SeatPlatePreview(
                    name: _names[row * 3 + column],
                    ringing: row == 0 && column == 1,
                  ),
                ),
                if (column != 2) const SizedBox(width: 10),
              ],
            ],
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _SeatPlatePreview extends StatelessWidget {
  const _SeatPlatePreview({required this.name, required this.ringing});

  final String name;
  final bool ringing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
      decoration: BoxDecoration(
        color: ringing
            ? AppColors.board
            : AppColors.chalk.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: ringing ? AppColors.redPen : AppColors.boardRim,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(color: AppColors.chalk),
            ),
          ),
          Icon(
            ringing
                ? Icons.notifications_active_rounded
                : Icons.circle_outlined,
            size: 14,
            color: ringing ? AppColors.redPenOnBoard : AppColors.chalkSoft,
          ),
        ],
      ),
    );
  }
}

class _SpecCell extends StatelessWidget {
  const _SpecCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: AppColors.chalkSoft.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: AppColors.chalk),
          ),
        ],
      ),
    );
  }
}
