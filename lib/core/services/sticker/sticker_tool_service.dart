import 'dart:convert';

class StickerToolService {
  static const String toolName = 'get_sticker';
  static const String toolDescription = '获取表情包图片，让回复更生动有趣';

  // nachoneko 表情包映射表 (根据 AIaW 的配置)
  static const Map<int, String> _stickerMap = {
    0: '好的（いいよ！）',
    1: '开心（nya~）',
    2: '疑惑（？？？）',
    3: '招手',
    4: '睡觉（zzz）',
    5: '吃冰棒',
    6: '逃避',
    7: '担心',
    8: '困倦（ねむい）',
    9: '倒下',
    10: '偷看',
    11: '生气',
    12: '嫌弃',
    13: '哭泣',
    14: '蛋糕',
    15: '打瞌睡（おはよう）',
    16: '想吃',
    17: '道歉（ごめんなさい）',
    18: '不满（やだ）',
    19: '思考（...?）',
    20: '凝视',
    21: '撒娇',
    22: '大声叫',
    23: '心动',
    24: '发呆',
    25: '害羞',
    26: '你好（Hi）',
    27: '愤怒',
    28: '无语（...）',
    29: '喜爱',
    30: '期待',
    31: '害羞',
    32: '吓哭',
    33: '装傻',
    34: '惊叹（！）',
    35: '冷汗（汗）',
    36: '夸张惊讶（哦！）',
    37: '卖萌呆呆（？）',
  };

  static Map<String, dynamic> getToolDefinition() {
    return {
      'type': 'function',
      'function': {
        'name': toolName,
        'description': toolDescription,
        'parameters': {
          'type': 'object',
          'properties': {
            'sticker_id': {
              'type': 'integer',
              'description': '表情包编号 (0-37)，根据想表达的情绪选择对应编号',
              'minimum': 0,
              'maximum': 37,
            },
          },
          'required': ['sticker_id'],
        },
      },
    };
  }

  static Future<String> getSticker(int stickerId) async {
    try {
      // 验证 ID 范围
      if (stickerId < 0 || stickerId > 37) {
        return jsonEncode({
          'error': '表情包编号必须在 0-37 之间',
        });
      }

      // 返回自定义标记
      final description = _stickerMap[stickerId] ?? '表情包';
      final stickerTag = '[STICKER:nachoneko:$stickerId]';

      return jsonEncode({
        'sticker_tag': stickerTag,
        'description': description,
        'sticker_id': stickerId,
      });
    } catch (e) {
      return jsonEncode({
        'error': '获取表情包失败: $e',
      });
    }
  }

  /// Get system prompt for sticker tool
  /// [frequency] 0=low, 1=medium, 2=high
  static String getSystemPrompt({int frequency = 1}) {
    // 生成表情包列表
    final stickerList = _stickerMap.entries
        .map((e) => '- ${e.key}: ${e.value}')
        .join('\n');

    // 根据频率生成使用规范
    final String frequencyGuideline = switch (frequency) {
      0 => '''### 使用规范（低频率模式）
- **极少使用**：只在非常适合的场景才使用，一般情况下不要使用表情包
- **严肃话题不用**：技术讨论、正式回复时不使用表情包
- **仅限情感表达**：只在需要强烈情感表达时偶尔使用
- **每次对话最多1个**：即使使用，也控制在一个以内''',
      2 => '''### 使用规范（高频率模式）
- **积极使用**：可以更频繁地使用表情包，让对话更活泼
- **每次回复可用1-2个**：适当增加表情包的使用
- **增强亲和力**：用表情包让回复更亲切、有趣
- **情境匹配**：选择与对话内容和氛围相符的表情''',
      _ => '''### 使用规范（中等频率模式）
- **适度使用**：不要过度使用表情包，以免影响阅读体验
- **情境匹配**：选择与对话内容和氛围相符的表情
- **严肃话题慎用**：在处理严肃、技术性强的话题时，少用或不用表情包
- **增强表达**：用表情包来增强情绪表达，而不是替代文字内容''',
    };

    return '''
## get_sticker 工具使用说明

你可以使用 get_sticker 工具获取可爱的表情包，让回复更生动、富有情感。

### 可用的表情包（nachoneko）

$stickerList

### 使用方法
1. 根据对话氛围和想表达的情绪，选择合适的表情包编号
2. 调用 get_sticker(sticker_id=编号)
3. 工具会返回包含 sticker_tag 字段的 JSON
4. **直接将 sticker_tag 的值插入到你的回复中**

### 使用示例
```
工具返回：{"sticker_tag": "[STICKER:nachoneko:26]", "description": "你好（Hi）"}
你的回复：你好！[STICKER:nachoneko:26] 请问有什么可以帮您？
```

**重要提示：**
- 直接复制粘贴 sticker_tag 的值到回复中
- 不要修改标记格式，保持 [STICKER:nachoneko:数字] 的格式
- 表情包会在用户界面自动渲染成可爱的图片

$frequencyGuideline

### 示例
- 用户问好 → 可用 26 (你好) 或 3 (招手)
- 解答成功 → 可用 1 (开心) 或 0 (好的)
- 用户遇到困难 → 可用 7 (担心)
- 复杂问题需思考 → 可用 19 (思考)
- 出现错误需道歉 → 可用 17 (道歉)
''';
  }
}
