import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

/// 프로필 화면
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('프로필'),
        centerTitle: true,
      ),
      body: Consumer<AuthProvider>(
        builder: (context, authProvider, child) {
          final user = authProvider.currentUser;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 프로필 헤더
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: Colors.blue,
                        child: Text(
                          user?.email[0].toUpperCase() ?? 'G',
                          style: const TextStyle(
                            fontSize: 32,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        user?.email ?? '게스트',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      if (user == null)
                        const Text(
                          '로그인하여 데이터를 동기화하세요',
                          style: TextStyle(color: Colors.grey),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 설정 항목들
              if (user == null) ...[
                ListTile(
                  leading: const Icon(Icons.login),
                  title: const Text('로그인'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pushNamed(context, '/login');
                  },
                ),
              ] else ...[
                ListTile(
                  leading: const Icon(Icons.sync),
                  title: const Text('서버 동기화'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    // TODO: 서버 동기화 구현
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('동기화 기능 준비 중입니다')),
                    );
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text(
                    '로그아웃',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('로그아웃'),
                        content: const Text('정말 로그아웃하시겠습니까?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('취소'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('로그아웃'),
                          ),
                        ],
                      ),
                    );

                    if (confirmed == true && context.mounted) {
                      await authProvider.signOut();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('로그아웃되었습니다')),
                        );
                      }
                    }
                  },
                ),
              ],

              const Divider(),

              // 앱 정보
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('앱 정보'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  showAboutDialog(
                    context: context,
                    applicationName: '근피로도 측정',
                    applicationVersion: '1.0.0',
                    applicationLegalese: '© 2025 근피로도 측정 앱',
                    children: [
                      const SizedBox(height: 16),
                      const Text(
                        '스마트폰 센서를 활용한 근피로도 측정 앱입니다.',
                      ),
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

