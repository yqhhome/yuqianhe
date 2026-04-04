import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/brand_logo.dart';
import '../../../data/models/register_request.dart';
import '../application/auth_notifier.dart';

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _emailCtrl = TextEditingController();
  final _passwdCtrl = TextEditingController();
  final _repassCtrl = TextEditingController();
  final _inviteCtrl = TextEditingController();
  final _emailCodeCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwdCtrl.dispose();
    _repassCtrl.dispose();
    _inviteCtrl.dispose();
    _emailCodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendEmail() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先输入邮箱')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await ref.read(authNotifierProvider.notifier).sendRegisterEmailCode(email);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.message)));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _submit() async {
    final base = ref.read(panelBaseUrlProvider);
    if (base == null || base.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请返回登录页，在右上角设置中填写服务器地址')),
      );
      return;
    }
    final email = _emailCtrl.text.trim();
    final password = _passwdCtrl.text;
    final repeat = _repassCtrl.text;
    if (email.isEmpty || password.isEmpty || repeat.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('邮箱、密码、重复密码不能为空')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final req = RegisterRequest(
        email: email,
        password: password,
        repeatPassword: repeat,
        inviteCode: _inviteCtrl.text.trim(),
        emailVerificationCode: _emailCodeCtrl.text.trim().isEmpty ? null : _emailCodeCtrl.text.trim(),
      );
      final res = await ref.read(authNotifierProvider.notifier).register(req);
      if (!mounted) {
        return;
      }
      if (res.success) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.message)));
        Navigator.of(context).pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.message)));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('宇千鹤 · 注册')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 860;
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: wide ? 820 : 500),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const BrandLogo(imageSize: 84),
                        const SizedBox(height: 14),
                        const Text(
                          '字段与网页注册一致：若站点开启验证码或仅邀请注册，请按提示填写。',
                          style: TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _emailCtrl,
                          decoration: const InputDecoration(
                            labelText: '邮箱',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _passwdCtrl,
                          decoration: const InputDecoration(
                            labelText: '密码（≥8 位）',
                            border: OutlineInputBorder(),
                          ),
                          obscureText: true,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _repassCtrl,
                          decoration: const InputDecoration(
                            labelText: '重复密码',
                            border: OutlineInputBorder(),
                          ),
                          obscureText: true,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _inviteCtrl,
                          decoration: const InputDecoration(
                            labelText: '邀请码（若站点要求）',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _emailCodeCtrl,
                                decoration: const InputDecoration(
                                  labelText: '邮箱验证码（若开启）',
                                  border: OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: _busy ? null : _sendEmail,
                              child: const Text('发送'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: _busy
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('注册'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
