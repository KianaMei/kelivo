import 'package:flutter/material.dart';
import 'package:lobe_ui/lobe_ui.dart';

/// LobeUI 品牌组件演示
class BrandDemo extends StatefulWidget {
  const BrandDemo({super.key});

  @override
  State<BrandDemo> createState() => _BrandDemoState();
}

class _BrandDemoState extends State<BrandDemo> {
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // Logo 组件
        Text(
          'Logo 组件',
          style: context.titleLarge,
        ),
        const SizedBox(height: 16),

        // Logo 类型演示
        _buildSection(
          'Logo 类型',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLogoRow('图标模式', const LobeLogo(type: LogoType.icon)),
              const SizedBox(height: 16),
              _buildLogoRow('组合模式', const LobeLogo(type: LogoType.combined)),
              const SizedBox(height: 16),
              _buildLogoRow('文字模式', const LobeLogo(type: LogoType.text)),
            ],
          ),
        ),

        // Logo 尺寸
        _buildSection(
          'Logo 尺寸',
          Row(
            children: [
              LobeLogo(size: 24, type: LogoType.combined),
              const SizedBox(width: 16),
              LobeLogo(size: 32, type: LogoType.combined),
              const SizedBox(width: 16),
              LobeLogo(size: 48, type: LogoType.combined),
              const SizedBox(width: 16),
              LobeLogo(size: 64, type: LogoType.combined),
            ],
          ),
        ),

        // 自定义颜色
        _buildSection(
          '自定义渐变色',
          Row(
            children: [
              LobeLogo(
                type: LogoType.icon,
                size: 48,
                gradientColors: [Colors.purple, Colors.blue],
              ),
              const SizedBox(width: 16),
              LobeLogo(
                type: LogoType.icon,
                size: 48,
                gradientColors: [Colors.orange, Colors.pink],
              ),
              const SizedBox(width: 16),
              LobeLogo(
                type: LogoType.icon,
                size: 48,
                gradientColors: [Colors.green, Colors.teal],
              ),
            ],
          ),
        ),

        // 3D Logo
        _buildSection(
          '3D Logo (悬停效果)',
          const Row(
            children: [
              Logo3D(size: 64),
              SizedBox(width: 24),
              Logo3D(
                size: 80,
                gradientColors: [Colors.purple, Colors.blue],
              ),
            ],
          ),
        ),

        const SizedBox(height: 48),

        // Footer 组件
        Text(
          'Footer 组件',
          style: context.titleLarge,
        ),
        const SizedBox(height: 16),

        // 基础 Footer
        _buildSection(
          '基础 Footer',
          LobeFooter(
            logo: LobeLogo(type: LogoType.combined, size: 32),
            description: 'LobeUI - Modern UI Components for AI Applications',
            columns: const [
              FooterColumn(
                title: '产品',
                links: [
                  FooterLink(label: 'LobeChat', url: 'https://chat.lobehub.com'),
                  FooterLink(label: 'LobeHub', url: 'https://lobehub.com'),
                ],
              ),
              FooterColumn(
                title: '资源',
                links: [
                  FooterLink(label: '文档', url: 'https://ui.lobehub.com'),
                  FooterLink(label: 'GitHub', url: 'https://github.com/lobehub'),
                ],
              ),
              FooterColumn(
                title: '社区',
                links: [
                  FooterLink(label: 'Discord', url: '#'),
                  FooterLink(label: 'Twitter', url: '#'),
                ],
              ),
            ],
          ),
        ),

        // 简单 Footer
        _buildSection(
          '简单 Footer',
          LobeFooter(
            logo: LobeLogo(type: LogoType.icon, size: 24),
            description: '由 LobeHub 团队精心打造',
            copyright: '© 2024 LobeHub. All rights reserved.',
          ),
        ),

        // 带底部内容的 Footer
        _buildSection(
          '带底部链接',
          LobeFooter(
            logo: LobeLogo(type: LogoType.combined, size: 28),
            description: 'Next-generation UI component library',
            copyright: '© 2024 LobeHub',
            bottom: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () {},
                  child: const Text('隐私政策'),
                ),
                const SizedBox(width: 8),
                Text('|', style: TextStyle(color: context.colorTextSecondary)),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {},
                  child: const Text('服务条款'),
                ),
                const SizedBox(width: 8),
                Text('|', style: TextStyle(color: context.colorTextSecondary)),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {},
                  child: const Text('联系我们'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSection(String title, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: context.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: context.colorText,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.colorBgContainer,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.colorBorder),
          ),
          child: child,
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildLogoRow(String label, Widget logo) {
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(color: context.colorTextSecondary),
          ),
        ),
        logo,
      ],
    );
  }
}
