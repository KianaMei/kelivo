import 'package:flutter/material.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/services/runtime_cache_service.dart';
import '../../../core/services/haptics.dart';

/// Runtime cache management page
/// Allows users to download/manage frontend runtime libraries for offline use
class RuntimeCachePage extends StatefulWidget {
  const RuntimeCachePage({super.key});

  @override
  State<RuntimeCachePage> createState() => _RuntimeCachePageState();
}

class _RuntimeCachePageState extends State<RuntimeCachePage> {
  Map<String, bool> _cacheStatus = {};
  bool _isLoading = true;
  bool _isDownloading = false;
  String _downloadingFile = '';
  int _downloadProgress = 0;
  int _cacheSize = 0;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() => _isLoading = true);
    try {
      final cache = RuntimeCacheService.instance;
      await cache.init();
      final status = await cache.getCacheStatus();
      final size = await cache.getCacheSize();
      if (mounted) {
        setState(() {
          _cacheStatus = status;
          _cacheSize = size;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _downloadAll() async {
    if (_isDownloading) return;
    
    setState(() => _isDownloading = true);
    Haptics.light();

    try {
      final cache = RuntimeCacheService.instance;
      await cache.downloadAll(
        onProgress: (fileName, progress) {
          if (mounted) {
            setState(() {
              _downloadingFile = RuntimeCacheService.getLibraryName(fileName);
              _downloadProgress = progress;
            });
          }
        },
      );
      await _loadStatus();
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadingFile = '';
          _downloadProgress = 0;
        });
      }
    }
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除缓存'),
        content: const Text('确定要删除所有已下载的运行时库吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      Haptics.light();
      final cache = RuntimeCacheService.instance;
      await cache.clearCache();
      await _loadStatus();
    }
  }

  String _formatBytes(int bytes) {
    const kb = 1024;
    const mb = kb * 1024;
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(2)} MB';
    if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(1)} KB';
    return '$bytes B';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final cachedCount = _cacheStatus.values.where((v) => v).length;
    final totalCount = _cacheStatus.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('代码预览缓存'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Status card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white10 : cs.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        cachedCount == totalCount ? Lucide.CheckCircle : Lucide.cloudDownload,
                        size: 48,
                        color: cachedCount == totalCount ? Colors.green : cs.primary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        cachedCount == totalCount ? '已准备好离线使用' : '需要下载运行时库',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '已缓存 $cachedCount/$totalCount 个库 · ${_formatBytes(_cacheSize)}',
                        style: TextStyle(
                          fontSize: 14,
                          color: cs.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Download button
                if (_isDownloading) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white10 : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '正在下载 $_downloadingFile...',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: cs.onSurface,
                                ),
                              ),
                            ),
                            Text(
                              '$_downloadProgress%',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: cs.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _downloadProgress / 100,
                            backgroundColor: cs.primary.withOpacity(0.15),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  ElevatedButton.icon(
                    onPressed: cachedCount == totalCount ? null : _downloadAll,
                    icon: Icon(cachedCount == totalCount ? Lucide.Check : Lucide.Download),
                    label: Text(cachedCount == totalCount ? '全部已下载' : '下载全部运行时库'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Library list
                Text(
                  '运行时库',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white10 : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
                  ),
                  child: Column(
                    children: RuntimeCacheService.libraryFileNames.map((fileName) {
                      final isCached = _cacheStatus[fileName] ?? false;
                      final name = RuntimeCacheService.getLibraryName(fileName);
                      final isLast = fileName == RuntimeCacheService.libraryFileNames.last;
                      
                      return Column(
                        children: [
                          ListTile(
                            leading: Icon(
                              isCached ? Lucide.CheckCircle : Lucide.Circle,
                              color: isCached ? Colors.green : cs.onSurface.withOpacity(0.3),
                              size: 20,
                            ),
                            title: Text(name),
                            subtitle: Text(
                              fileName,
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurface.withOpacity(0.5),
                              ),
                            ),
                            trailing: isCached
                                ? null
                                : IconButton(
                                    icon: const Icon(Lucide.Download, size: 18),
                                    onPressed: () async {
                                      Haptics.light();
                                      final cache = RuntimeCacheService.instance;
                                      await cache.download(fileName);
                                      await _loadStatus();
                                    },
                                  ),
                          ),
                          if (!isLast)
                            Divider(
                              height: 1,
                              indent: 56,
                              color: cs.outlineVariant.withOpacity(0.3),
                            ),
                        ],
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 24),

                // Clear cache button
                if (_cacheSize > 0)
                  TextButton.icon(
                    onPressed: _clearCache,
                    icon: const Icon(Lucide.Trash, size: 18, color: Colors.red),
                    label: const Text('清除所有缓存', style: TextStyle(color: Colors.red)),
                  ),

                const SizedBox(height: 16),

                // Info
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Lucide.info, size: 16, color: cs.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '下载运行时库后，代码预览功能可在离线状态下使用',
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurface.withOpacity(0.7),
                          ),
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
