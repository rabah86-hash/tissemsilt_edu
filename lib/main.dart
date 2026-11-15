import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TissemsiltNewsApp());
}

class TissemsiltNewsApp extends StatelessWidget {
  const TissemsiltNewsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ø±Ø§ØµØ¯ Ø§Ù„ØªØ±Ø¨ÙŠØ© - ØªÙŠØ³Ù…Ø³ÙŠÙ„Øª',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: false,
        primaryColor: const Color(0xFF1A237E),
        scaffoldBackgroundColor: const Color(0xFFF0F2F8),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1A237E),
          foregroundColor: Colors.white,
        ),
      ),
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox(),
        );
      },
      home: const NewsDashboard(),
    );
  }
}

class NewsDashboard extends StatefulWidget {
  const NewsDashboard({super.key});

  @override
  State<NewsDashboard> createState() => _NewsDashboardState();
}

class _NewsDashboardState extends State<NewsDashboard>
    with SingleTickerProviderStateMixin {
  static const String _firebaseDbUrl =
      'https://tissemsilt-edu-default-rtdb.firebaseio.com/shared_posts.json';
  static const String _firebaseBaseUrl =
      'https://tissemsilt-edu-default-rtdb.firebaseio.com/shared_posts';

  late TabController _tabController;
  late StreamSubscription _intentSub;
  bool isScanning = false;
  String searchQuery = "";
  String selectedTab = "Ø§Ù„ÙƒÙ„";
  int maxDaysOld = 7;

  List newsList = [];

  final List<String> tissemsiltKeywords = [
    "ØªÙŠØ³Ù…Ø³ÙŠÙ„Øª", "Ø«Ù†ÙŠØ© Ø§Ù„Ø­Ø¯", "Ø¨Ø±Ø¬ Ø¨ÙˆÙ†Ø¹Ø§Ù…Ø©", "Ø®Ù…ÙŠØ³ØªÙŠ", "Ù„Ø±Ø¬Ø§Ù…",
    "Ø¹Ù…Ø§Ø±ÙŠ", "Ø¨ÙˆÙ‚Ø§ÙŠØ¯", "Ø§Ù„Ø£Ø²Ù‡Ø±ÙŠØ©", "Ø¨Ø±Ø¬ Ø§Ù„Ø£Ù…ÙŠØ± Ø¹Ø¨Ø¯ Ø§Ù„Ù‚Ø§Ø¯Ø±", "Ø³ÙŠØ¯ÙŠ Ø³Ù„ÙŠÙ…Ø§Ù†",
    "Ø£ÙˆÙ„Ø§Ø¯ Ø¨Ø³Ø§Ù…", "Ù…Ù„Ø¹Ø¨", "Ø³ÙŠØ¯ÙŠ Ø¹Ø§Ø¨Ø¯", "ØªÙ…Ù„Ø§Ø­Øª", "Ø³ÙŠØ¯ÙŠ Ø¨ÙˆØªØ´Ù†Øª",
    "Ø§Ù„Ø¹ÙŠÙˆÙ†", "Ø§Ù„ÙŠÙˆØ³ÙÙŠØ©", "Ø³ÙŠØ¯ÙŠ Ø§Ù„Ø¹Ù†ØªØ±ÙŠ", "Ù…Ø¹Ø§ØµÙ…"
  ];

  final List<String> tabs = [
    "Ø§Ù„ÙƒÙ„",
    "ØªÙŠØ³Ù…Ø³ÙŠÙ„Øª",
    "ÙˆØ·Ù†ÙŠ",
    "ØªÙ‚Ø§Ø±ÙŠØ± Ù…ØªÙ„ÙØ²Ø©",
    "ÙÙŠØ³Ø¨ÙˆÙƒ"
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: tabs.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          selectedTab = tabs[_tabController.index];
        });
      }
    });
    _loadSavedNews();
    _initSharingIntent();
  }

  // Ø§Ø³ØªÙ‚Ø¨Ø§Ù„ Ø§Ù„Ø±ÙˆØ§Ø¨Ø· ÙˆØ§Ù„Ù…Ù†Ø´ÙˆØ±Ø§Øª Ø§Ù„Ù…Ø´ØªØ±ÙƒØ© Ù…Ù† ÙÙŠØ³Ø¨ÙˆÙƒ ÙˆÙŠÙˆØªÙŠÙˆØ¨
  void _initSharingIntent() {
    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      (List<SharedMediaFile> value) {
        if (value.isNotEmpty) {
          _openQuickShareFromExternalApp(value.first.path);
        }
      },
      onError: (err) => debugPrint("Share Error: $err"),
    );

    ReceiveSharingIntent.instance.getInitialMedia().then(
      (List<SharedMediaFile> value) {
        if (value.isNotEmpty) {
          _openQuickShareFromExternalApp(value.first.path);
          ReceiveSharingIntent.instance.reset();
        }
      },
    );
  }

  // ÙØªØ­ Ù†Ø§ÙØ°Ø© Ø§Ù„Ø¥Ø¶Ø§ÙØ© ÙˆØ§Ù„Ù†Ø´Ø± Ø§Ù„ÙÙˆØ±ÙŠ Ù„Ù„Ø¬Ù…ÙŠØ¹ Ø¹Ù†Ø¯ Ù…Ø´Ø§Ø±ÙƒØ© Ø±Ø§Ø¨Ø· Ù…Ù† ÙÙŠØ³Ø¨ÙˆÙƒ Ø£Ùˆ ÙŠÙˆØªÙŠÙˆØ¨
  void _openQuickShareFromExternalApp(String rawSharedText) {
    if (rawSharedText.trim().isEmpty) return;

    final RegExp urlRegExp = RegExp(r'(https?:\/\/[^\s]+)');
    final Match? match = urlRegExp.firstMatch(rawSharedText);
    final String extractedUrl =
        match != null ? match.group(0)! : rawSharedText.trim();
    final String extractedTitle =
        rawSharedText.replaceAll(extractedUrl, '').trim();

    final bool isYoutube = extractedUrl.contains("youtube.com") ||
        extractedUrl.contains("youtu.be");

    _showAddFacebookModal(
      prefillUrl: extractedUrl,
      prefillTitle: extractedTitle.isNotEmpty
          ? extractedTitle
          : (isYoutube
              ? "ÙÙŠØ¯ÙŠÙˆ ØªØ±Ø¨ÙˆÙŠ Ù…Ø±ØµÙˆØ¯ Ø¹Ø¨Ø± ÙŠÙˆØªÙŠÙˆØ¨"
              : "Ù…Ù†Ø´ÙˆØ± ØªØ±Ø¨ÙˆÙŠ Ù…Ø±ØµÙˆØ¯ Ø¹Ø¨Ø± ÙÙŠØ³Ø¨ÙˆÙƒ"),
      defaultCategory: isYoutube ? "ØªÙ‚Ø§Ø±ÙŠØ± Ù…ØªÙ„ÙØ²Ø©" : "ØªÙŠØ³Ù…Ø³ÙŠÙ„Øª",
    );
  }

  Future<void> _loadSavedNews() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? savedData = prefs.getString('tissemsilt_edu_news_v5');
      if (savedData != null && savedData.isNotEmpty) {
        final decoded = json.decode(savedData) as List;
        if (decoded.isNotEmpty) {
          setState(() {
            newsList =
                decoded.map((e) => Map<String, dynamic>.from(e)).toList();
          });
        }
      }
    } catch (_) {}

    // Ø¬Ù„Ø¨ Ø§Ù„Ù…Ù†Ø´ÙˆØ±Ø§Øª Ø§Ù„Ø³Ø­Ø§Ø¨ÙŠØ© Ø§Ù„Ù…Ø´ØªØ±ÙƒØ© + ØªØ­Ø¯ÙŠØ« Ø§Ù„Ø£Ø®Ø¨Ø§Ø± Ø§Ù„Ø­ÙŠØ© ØªÙ„Ù‚Ø§Ø¦ÙŠØ§Ù‹
    await _fetchCloudPosts();
    if (newsList.isEmpty) {
      runSmartRadarBot();
    }
  }

  Future<void> _saveNewsToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('tissemsilt_edu_news_v5', json.encode(newsList));
    } catch (_) {}
  }

  // Ø¬Ù„Ø¨ Ø§Ù„Ù…Ù†Ø´ÙˆØ±Ø§Øª Ø§Ù„Ù…Ø´ØªØ±ÙƒØ© Ù…Ù† Firebase Ù„ØªØ¸Ù‡Ø± Ø¹Ù†Ø¯ Ø¬Ù…ÙŠØ¹ Ø§Ù„Ù…Ø³ØªØ®Ø¯Ù…ÙŠÙ†
  Future<void> _fetchCloudPosts() async {
    try {
      final response = await http
          .get(Uri.parse(_firebaseDbUrl))
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final decoded = json.decode(utf8.decode(response.bodyBytes));
        if (decoded != null && decoded is Map) {
          decoded.forEach((key, value) {
            if (value is Map) {
              final String title = (value["title"] ?? "").toString();
              final String url = (value["url"] ?? "").toString();
              if (title.isEmpty) return;

              final int ts = (value["timestamp"] is int)
                  ? value["timestamp"] as int
                  : DateTime.now().millisecondsSinceEpoch;
              final parsedDate =
                  DateTime.fromMillisecondsSinceEpoch(ts).toIso8601String();
              final timeInfo = _parseRealTime(parsedDate);

              final existingIndex =
                  newsList.indexWhere((n) => n['cloudId'] == key);
              final postMap = <String, dynamic>{
                "cloudId": key,
                "title": title,
                "summary": (value["summary"] ?? title).toString(),
                "source": (value["source"] ?? "Ø±ØµØ¯ Ø§Ù„Ø¥Ø¯Ø§Ø±Ø© Ø§Ù„Ù…Ø¨Ø§Ø´Ø±").toString(),
                "category": (value["category"] ?? "ØªÙŠØ³Ù…Ø³ÙŠÙ„Øª").toString(),
                "type": (value["type"] ?? "facebook").toString(),
                "time": timeInfo["display"],
                "timestamp": ts,
                "url": url,
                "important": (value["category"] ?? "ØªÙŠØ³Ù…Ø³ÙŠÙ„Øª") == "ØªÙŠØ³Ù…Ø³ÙŠÙ„Øª",
              };

              if (existingIndex == -1) {
                newsList.insert(0, postMap);
              } else {
                newsList[existingIndex] = postMap;
              }
            }
          });
          newsList.sort((a, b) =>
              ((b['timestamp'] ?? 0) as int).compareTo((a['timestamp'] ?? 0) as int));
          if (mounted) setState(() {});
          await _saveNewsToStorage();
        }
      }
    } catch (_) {}
  }

  // Ø±ÙØ¹ Ø§Ù„Ù…Ù†Ø´ÙˆØ± Ø£Ùˆ Ø§Ù„ÙÙŠØ¯ÙŠÙˆ Ø¥Ù„Ù‰ Firebase Ù„ÙŠØ¸Ù‡Ø± Ù„Ø¯Ù‰ Ø¬Ù…ÙŠØ¹ Ø§Ù„Ù…Ø³ØªØ®Ø¯Ù…ÙŠÙ† ÙÙˆØ±Ø§Ù‹
  Future<void> _publishPostToCloud(Map<String, dynamic> postData) async {
    try {
      final response = await http.post(
        Uri.parse(_firebaseDbUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(postData),
      );
      if (response.statusCode == 200) {
        final resData = json.decode(response.body);
        if (resData is Map && resData['name'] != null) {
          postData['cloudId'] = resData['name'];
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text("ØªÙ… Ø§Ù„Ù†Ø´Ø± Ø§Ù„Ø³Ø­Ø§Ø¨ÙŠ Ø¨Ù†Ø¬Ø§Ø­! ÙŠØ¸Ù‡Ø± Ø§Ù„Ø¢Ù† Ù„Ø¯Ù‰ Ø¬Ù…ÙŠØ¹ Ù…Ø³ØªØ®Ø¯Ù…ÙŠ Ø§Ù„ØªØ·Ø¨ÙŠÙ‚."),
              backgroundColor: Colors.green.shade800,
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("ØªÙ… Ø§Ù„Ø­ÙØ¸ Ù…Ø­Ù„ÙŠØ§Ù‹ (ØªØ¹Ø°Ø± Ø§Ù„ÙˆØµÙˆÙ„ Ù„Ù„Ø³Ø­Ø§Ø¨Ø©ØŒ ØªØ­Ù‚Ù‚ Ù…Ù† Ø§Ù„Ø¥Ù†ØªØ±Ù†Øª)."),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Map<String, dynamic> _parseRealTime(String rawDate) {
    DateTime? parsed;
    try {
      parsed = DateTime.tryParse(rawDate);
      if (parsed == null) {
        final months = {
          'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
          'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12
        };
        final parts = rawDate.replaceAll(',', '').split(RegExp(r'\s+'));
        if (parts.length >= 5) {
          int day = int.tryParse(parts[1]) ?? 1;
          int month = months[parts[2]] ?? 1;
          int year = int.tryParse(parts[3]) ?? DateTime.now().year;
          final timeParts = parts[4].split(':');
          int hour = int.tryParse(timeParts[0]) ?? 0;
          int minute =
              timeParts.length > 1 ? (int.tryParse(timeParts[1]) ?? 0) : 0;
          parsed = DateTime.utc(year, month, day, hour, minute).toLocal();
        }
      } else {
        parsed = parsed.toLocal();
      }
    } catch (_) {}

    final now = DateTime.now();
    parsed ??= now;

    final diff = now.difference(parsed);
    String relative = "";
    if (diff.inMinutes < 2) {
      relative = "Ø§Ù„Ø¢Ù†";
    } else if (diff.inMinutes < 60) {
      relative = "Ù…Ù†Ø° ${diff.inMinutes} Ø¯Ù‚ÙŠÙ‚Ø©";
    } else if (diff.inHours < 24) {
      relative = "Ù…Ù†Ø° ${diff.inHours} Ø³Ø§Ø¹Ø©";
    } else {
      relative = "Ù…Ù†Ø° ${diff.inDays} ÙŠÙˆÙ…";
    }

    String clock =
        "${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}";
    String fullDate =
        "${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')} ($clock)";

    return {
      "timestamp": parsed.millisecondsSinceEpoch,
      "display": "$relative | $fullDate",
      "daysOld": diff.inDays < 0 ? 0 : diff.inDays,
    };
  }

  String _cleanSummaryText(String rawHtml, String fallbackTitle) {
    String text = rawHtml
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (text.length < 25 || text == fallbackTitle) {
      return "Ù…Ù„Ø®Øµ Ø§Ù„Ø®Ø¨Ø±: $fallbackTitle. (Ø§Ø¶ØºØ· Ù„Ø¹Ø±Ø¶ Ø§Ù„ØªÙØ§ØµÙŠÙ„ Ø§Ù„ÙƒØ§Ù…Ù„Ø© Ø£Ùˆ ÙØªØ­ Ø§Ù„ØªÙ‚Ø±ÙŠØ± Ø§Ù„Ø£ØµÙ„ÙŠ).";
    }
    return text.length > 260 ? "${text.substring(0, 260)}..." : text;
  }

  // Ø§Ù„Ø±ÙˆØ¨ÙˆØª Ø§Ù„Ù…ÙˆØ³Ø¹: Ø§ØªØµØ§Ù„ Ù…Ø¨Ø§Ø´Ø± ÙˆÙ…Ø³ØªÙ‚Ø± Ø¨Ù€ Google News RSS Ù…Ø¹ ÙÙ„ØªØ±Ø© ØµØ§Ø±Ù…Ø© Ù„Ù„ØªØ§Ø±ÙŠØ® Ø§Ù„Ø­Ø¯ÙŠØ«
  Future<void> runSmartRadarBot() async {
    if (isScanning) return;
    setState(() => isScanning = true);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Ø¬Ø§Ø±ÙŠ Ù…Ø³Ø­ 8 Ù‚Ù†ÙˆØ§Øª Ø¥Ø®Ø¨Ø§Ø±ÙŠØ© ÙˆØªÙ„ÙØ²ÙŠÙˆÙ†ÙŠØ© (Ø£Ø®Ø¨Ø§Ø± Ø¢Ø®Ø± $maxDaysOld Ø£ÙŠØ§Ù… ÙÙ‚Ø·)...'),
          backgroundColor: const Color(0xFF1A237E),
          duration: const Duration(seconds: 3),
        ),
      );
    }

    await _fetchCloudPosts();

    // Ø­Ø³Ø§Ø¨ ØªØ§Ø±ÙŠØ® Ø§Ù„Ø¨Ø¯Ø§ÙŠØ© Ø§Ù„Ø¯Ù‚ÙŠÙ‚ Ø¨ØµÙŠØºØ© YYYY-MM-DD Ù„Ø¥Ø¬Ø¨Ø§Ø± Ù…Ø­Ø±Ùƒ Ø§Ù„Ø£Ø®Ø¨Ø§Ø± Ø¹Ù„Ù‰ Ø¬Ù„Ø¨ Ø§Ù„Ø­Ø¯ÙŠØ« ÙÙ‚Ø·
    final DateTime cutoffDate =
        DateTime.now().subtract(Duration(days: maxDaysOld));
    final String afterDateStr =
        "${cutoffDate.year}-${cutoffDate.month.toString().padLeft(2, '0')}-${cutoffDate.day.toString().padLeft(2, '0')}";

    final List queries = [
      {
        "q": "ØªÙŠØ³Ù…Ø³ÙŠÙ„Øª ØªØ±Ø¨ÙŠØ© OR Ù…Ø¯ÙŠØ±ÙŠØ© Ø§Ù„ØªØ±Ø¨ÙŠØ© ØªÙŠØ³Ù…Ø³ÙŠÙ„Øª after:$afterDateStr",
        "type": "press",
        "forceLocal": true
      },
      {
        "q": "ÙˆÙ„Ø§ÙŠØ© ØªÙŠØ³Ù…Ø³ÙŠÙ„Øª Ù…Ø¯Ø§Ø±Ø³ OR Ø«Ø§Ù†ÙˆÙŠØ© OR Ù…ØªÙˆØ³Ø·Ø© OR Ø§Ø¨ØªØ¯Ø§Ø¦ÙŠØ© after:$afterDateStr",
        "type": "press",
        "forceLocal": true
      },
      {
        "q": "ØªÙŠØ³Ù…Ø³ÙŠÙ„Øª (Ø«Ù†ÙŠØ© Ø§Ù„Ø­Ø¯ OR Ø¨Ø±Ø¬ Ø¨ÙˆÙ†Ø¹Ø§Ù…Ø© OR Ø®Ù…ÙŠØ³ØªÙŠ OR Ù„Ø±Ø¬Ø§Ù… OR Ø¹Ù…Ø§Ø±ÙŠ) after:$afterDateStr",
        "type": "press",
        "forceLocal": true
      },
      {
        "q": "ÙˆØ²Ø§Ø±Ø© Ø§Ù„ØªØ±Ø¨ÙŠØ© Ø§Ù„ÙˆØ·Ù†ÙŠØ© Ø§Ù„Ø¬Ø²Ø§Ø¦Ø± after:$afterDateStr",
        "type": "press",
        "forceLocal": false
      },
      {
        "q": "ÙˆØ²ÙŠØ± Ø§Ù„ØªØ±Ø¨ÙŠØ© Ø§Ù„Ø¬Ø²Ø§Ø¦Ø± OR Ø§Ù„Ø¯Ø®ÙˆÙ„ Ø§Ù„Ù…Ø¯Ø±Ø³ÙŠ OR Ø§Ù„Ø¨ÙƒØ§Ù„ÙˆØ±ÙŠØ§ OR Ø§Ù„Ø¨ÙŠØ§Ù… after:$afterDateStr",
        "type": "press",
        "forceLocal": false
      },
      {
        "q": "Ù…Ø³Ø§Ø¨Ù‚Ø© Ø§Ù„Ø£Ø³Ø§ØªØ°Ø© OR ØªÙˆØ¸ÙŠÙ Ø§Ù„ØªØ±Ø¨ÙŠØ© Ø§Ù„Ø¬Ø²Ø§Ø¦Ø± OR Ù…Ø¯ÙŠØ± Ù…ØªÙˆØ³Ø·Ø© after:$afterDateStr",
        "type": "press",
        "forceLocal": false
      },
      {
        "q": "(ÙÙŠØ¯ÙŠÙˆ OR ØªÙ‚Ø±ÙŠØ± OR ØªØºØ·ÙŠØ©) Ù‚Ø·Ø§Ø¹ Ø§Ù„ØªØ±Ø¨ÙŠØ© Ø§Ù„Ø¬Ø²Ø§Ø¦Ø± OR Ù…Ø¯Ø§Ø±Ø³ ØªÙŠØ³Ù…Ø³ÙŠÙ„Øª after:$afterDateStr",
        "type": "tv",
        "forceLocal": false
      },
      {
        "q": "(Ù‚Ù†Ø§Ø© Ø§Ù„Ù†Ù‡Ø§Ø± OR Ø§Ù„Ø´Ø±ÙˆÙ‚ Ù†ÙŠÙˆØ² OR Ù‚Ù†Ø§Ø© Ø§Ù„Ø¨Ù„Ø§Ø¯ OR Ø§Ù„ØªÙ„ÙØ²ÙŠÙˆÙ† Ø§Ù„Ø¬Ø²Ø§Ø¦Ø±ÙŠ) Ø§Ù„ØªØ±Ø¨ÙŠØ© after:$afterDateStr",
        "type": "tv",
        "forceLocal": false
      },
    ];

    int addedCount = 0;

    for (var queryObj in queries) {
      final String qText = queryObj["q"].toString();
      final String qType = queryObj["type"].toString();
      final bool forceLocal = queryObj["forceLocal"] == true;
      final encodedQuery = Uri.encodeComponent(qText);
      final directRssUrl = Uri.parse(
          'https://news.google.com/rss/search?q=$encodedQuery&hl=ar&gl=DZ&ceid=DZ:ar');

      try {
        final response = await http.get(
          directRssUrl,
          headers: {
            'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36',
            'Accept': 'application/rss+xml, application/xml, text/xml, */*',
          },
        ).timeout(const Duration(seconds: 12));

        if (response.statusCode == 200) {
          final document =
              XmlDocument.parse(utf8.decode(response.bodyBytes, allowMalformed: true));
          final items = document.findAllElements('item');

          for (var node in items) {
            String rawTitle =
                node.findElements('title').firstOrNull?.innerText.trim() ?? "";
            if (rawTitle.isEmpty) continue;

            final String link =
                node.findElements('link').firstOrNull?.innerText.trim() ?? "";
            final String rawDate =
                node.findElements('pubDate').firstOrNull?.innerText.trim() ?? "";
            final String rawDesc =
                node.findElements('description').firstOrNull?.innerText ?? "";
            String extractedSource =
                node.findElements('source').firstOrNull?.innerText.trim() ?? "";

            if (rawTitle.contains(" - ")) {
              final splitParts = rawTitle.split(" - ");
              if (extractedSource.isEmpty) {
                extractedSource = splitParts.last.trim();
              }
              rawTitle =
                  splitParts.sublist(0, splitParts.length - 1).join(" - ").trim();
            }
            if (extractedSource.isEmpty) {
              extractedSource =
                  qType == "tv" ? "ØªÙ‚Ø±ÙŠØ± ØªÙ„ÙØ²ÙŠÙˆÙ†ÙŠ" : "Ø§Ù„ØµØ­Ø§ÙØ© Ø§Ù„ÙˆØ·Ù†ÙŠØ©";
            }

            final Map<String, dynamic> timeInfo = _parseRealTime(rawDate);
            // Ø§Ø³ØªØ¨Ø¹Ø§Ø¯ ØµØ§Ø±Ù… Ù„Ø£ÙŠ Ø®Ø¨Ø± Ø£Ù‚Ø¯Ù… Ù…Ù† Ø§Ù„Ù†Ø·Ø§Ù‚ Ø§Ù„Ù…Ø­Ø¯Ø¯
            if ((timeInfo["daysOld"] as int) > maxDaysOld) continue;

            bool exists = newsList.any((n) => n['title'].toString() == rawTitle);
            if (!exists) {
              bool isTissemsilt = forceLocal ||
                  tissemsiltKeywords.any(
                      (k) => rawTitle.contains(k) || rawDesc.contains(k));
              String category = isTissemsilt
                  ? "ØªÙŠØ³Ù…Ø³ÙŠÙ„Øª"
                  : (qType == "tv" ? "ØªÙ‚Ø§Ø±ÙŠØ± Ù…ØªÙ„ÙØ²Ø©" : "ÙˆØ·Ù†ÙŠ");

              newsList.add({
                "title": rawTitle,
                "summary": _cleanSummaryText(rawDesc, rawTitle),
                "source": extractedSource,
                "category": category,
                "type": qType,
                "time": timeInfo["display"],
                "timestamp": timeInfo["timestamp"],
                "url": link,
                "important": isTissemsilt
              });
              addedCount++;
            }
          }
        }
      } catch (_) {}
    }

    // Ø¥Ø²Ø§Ù„Ø© Ø£ÙŠ Ø£Ø®Ø¨Ø§Ø± Ù‚Ø¯ÙŠÙ…Ø© Ù…Ø®Ø²Ù†Ø© Ø³Ø§Ø¨Ù‚Ø§Ù‹ ØªØªØ¬Ø§ÙˆØ² Ø§Ù„Ù†Ø·Ø§Ù‚ Ø§Ù„Ù…Ø­Ø¯Ø¯ (Ù…Ø§ Ø¹Ø¯Ø§ Ù…Ù†Ø´ÙˆØ±Ø§Øª Ø§Ù„Ø¥Ø¯Ø§Ø±Ø© Ø§Ù„Ø³Ø­Ø§Ø¨ÙŠØ©)
    newsList.removeWhere((item) {
      if (item['cloudId'] != null) return false;
      final int ts = (item['timestamp'] ?? 0) as int;
      final ageDays = DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(ts))
          .inDays;
      return ageDays > maxDaysOld;
    });

    // ØªØ±ØªÙŠØ¨ ØµØ§Ø±Ù… Ù…Ù† Ø§Ù„Ø£Ø­Ø¯Ø« Ø¥Ù„Ù‰ Ø§Ù„Ø£Ù‚Ø¯Ù…
    newsList.sort((a, b) {
      int timeA = (a['timestamp'] ?? 0) as int;
      int timeB = (b['timestamp'] ?? 0) as int;
      return timeB.compareTo(timeA);
    });

    await _saveNewsToStorage();

    if (mounted) {
      setState(() => isScanning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Ø§ÙƒØªÙ…Ù„ Ø§Ù„Ø±ØµØ¯: ØªÙ… Ø³Ø­Ø¨ $addedCount Ø®Ø¨Ø± ÙˆØªÙ‚Ø±ÙŠØ± Ø­Ø¯ÙŠØ« Ø¨Ø§Ù„ØªÙˆÙ‚ÙŠØª Ø§Ù„Ø­Ù‚ÙŠÙ‚ÙŠ.'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    }
  }

  void _showArticleSummarySheet(Map<String, dynamic> item) {
    final String type = (item["type"] ?? "press").toString();
    final bool isTv = type == "tv";
    final bool isFb = type == "facebook";

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isTv ? Icons.live_tv : (isFb ? Icons.facebook : Icons.summarize),
                    color: isTv ? Colors.red.shade700 : const Color(0xFF1A237E),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Ø¨Ø·Ø§Ù‚Ø© Ø§Ù„Ù…Ù„Ø®Øµ Ø§Ù„Ø¥Ø¹Ù„Ø§Ù…ÙŠ - ${(item["source"] ?? "").toString()}",
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Color(0xFF1A237E)),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  )
                ],
              ),
              const Divider(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.access_time,
                        size: 15, color: Colors.deepOrange),
                    const SizedBox(width: 6),
                    Text(
                      "Ø§Ù„ØªÙˆÙ‚ÙŠØª Ø§Ù„Ø­Ù‚ÙŠÙ‚ÙŠ Ù„Ù„Ù†Ø´Ø±: ${(item["time"] ?? "").toString()}",
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepOrange),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                (item["title"] ?? "").toString(),
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold, height: 1.4),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F7FB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.indigo.shade100),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isTv
                          ? "Ù…Ù„Ø®Øµ Ø§Ù„ØªÙ‚Ø±ÙŠØ± Ø§Ù„Ù…ØªÙ„ÙØ² / Ø§Ù„ÙÙŠØ¯ÙŠÙˆ:"
                          : "Ø§Ù„Ø®Ù„Ø§ØµØ© Ø§Ù„Ù…Ø±ÙƒØ²Ø© Ù„Ù„Ø®Ø¨Ø±:",
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Color(0xFF1A237E)),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      (item["summary"] ?? item["title"] ?? "").toString(),
                      style: const TextStyle(
                          fontSize: 14, height: 1.6, color: Colors.black87),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            isTv ? Colors.red.shade700 : const Color(0xFF1A237E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _openNewsLink((item["url"] ?? "").toString());
                      },
                      icon: Icon(
                          isTv ? Icons.play_circle_fill : Icons.open_in_new),
                      label: Text(isTv
                          ? "Ù…Ø´Ø§Ù‡Ø¯Ø© Ø§Ù„ÙÙŠØ¯ÙŠÙˆ Ø§Ù„ÙƒØ§Ù…Ù„ Ù…Ù† Ø§Ù„Ù…ØµØ¯Ø±"
                          : "Ù‚Ø±Ø§Ø¡Ø© Ø§Ù„Ù…Ù‚Ø§Ù„ Ø§Ù„ÙƒØ§Ù…Ù„ Ù…Ù† Ø§Ù„Ù…ØµØ¯Ø±"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAddFacebookModal({
    String prefillUrl = "",
    String prefillTitle = "",
    String defaultCategory = "ØªÙŠØ³Ù…Ø³ÙŠÙ„Øª",
  }) {
    final linkController = TextEditingController(text: prefillUrl);
    final titleController = TextEditingController(text: prefillTitle);
    final summaryController = TextEditingController();
    String selectedCategory = defaultCategory;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                left: 20,
                right: 20,
                top: 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.campaign,
                          color: Color(0xFF1877F2), size: 28),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          "Ù†Ø´Ø± Ø®Ø¨Ø± Ø£Ùˆ ÙÙŠØ¯ÙŠÙˆ Ù„Ù„Ø¬Ù…ÙŠØ¹ (ÙÙŠØ³Ø¨ÙˆÙƒ / ÙŠÙˆØªÙŠÙˆØ¨)",
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      )
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: linkController,
                    decoration: InputDecoration(
                      labelText: "Ø±Ø§Ø¨Ø· Ø§Ù„Ù…Ù†Ø´ÙˆØ± Ø£Ùˆ Ø§Ù„ÙÙŠØ¯ÙŠÙˆ",
                      prefixIcon: const Icon(Icons.link),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: titleController,
                    decoration: InputDecoration(
                      labelText: "Ø¹Ù†ÙˆØ§Ù† Ø§Ù„Ø®Ø¨Ø± Ø§Ù„Ø¨Ø§Ø±Ø²",
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: summaryController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: "Ù…Ù„Ø®Øµ Ø§Ù„Ø®Ø¨Ø± (Ø§Ø®ØªÙŠØ§Ø±ÙŠ - ÙŠØ¸Ù‡Ø± Ù„Ù„Ù…Ø·Ø§Ù„Ø¹ÙŠÙ†)",
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: selectedCategory,
                    decoration: InputDecoration(
                      labelText: "ØªØµÙ†ÙŠÙ Ø§Ù„Ø®Ø¨Ø±",
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: "ØªÙŠØ³Ù…Ø³ÙŠÙ„Øª",
                          child: Text("Ø£Ø®Ø¨Ø§Ø± ØªÙŠØ³Ù…Ø³ÙŠÙ„Øª (Ø£ÙˆÙ„ÙˆÙŠØ© Ù‚ØµÙˆÙ‰)")),
                      DropdownMenuItem(
                          value: "ÙˆØ·Ù†ÙŠ",
                          child: Text("Ø£Ø®Ø¨Ø§Ø± ÙˆØ·Ù†ÙŠØ© - ÙˆØ²Ø§Ø±Ø© Ø§Ù„ØªØ±Ø¨ÙŠØ©")),
                      DropdownMenuItem(
                          value: "ØªÙ‚Ø§Ø±ÙŠØ± Ù…ØªÙ„ÙØ²Ø©",
                          child: Text("ÙÙŠØ¯ÙŠÙˆ / ØªÙ‚Ø±ÙŠØ± ÙŠÙˆØªÙŠÙˆØ¨ Ø£Ùˆ ØªÙ„ÙØ²ÙŠÙˆÙ†")),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setModalState(() => selectedCategory = val);
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A237E),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.send),
                      label: const Text("Ù†Ø´Ø± Ù„Ù„Ø¬Ù…ÙŠØ¹ Ø§Ù„Ø¢Ù†",
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)),
                      onPressed: () async {
                        if (titleController.text.trim().isEmpty &&
                            linkController.text.trim().isEmpty) return;

                        String finalUrl = linkController.text.trim().isEmpty
                            ? "https://www.facebook.com"
                            : linkController.text.trim();
                        final bool isYt = finalUrl.contains("youtube.com") ||
                            finalUrl.contains("youtu.be");
                        final int nowTs = DateTime.now().millisecondsSinceEpoch;
                        final nowInfo =
                            _parseRealTime(DateTime.now().toIso8601String());

                        final String finalTitle =
                            titleController.text.trim().isEmpty
                                ? (isYt
                                    ? "ÙÙŠØ¯ÙŠÙˆ ØªØ±Ø¨ÙˆÙŠ Ù…Ø±ØµÙˆØ¯ Ø¹Ø¨Ø± ÙŠÙˆØªÙŠÙˆØ¨"
                                    : "Ù…Ù†Ø´ÙˆØ± ØªØ±Ø¨ÙˆÙŠ Ù…Ø±ØµÙˆØ¯ Ø¹Ø¨Ø± ÙÙŠØ³Ø¨ÙˆÙƒ")
                                : titleController.text.trim();

                        final String finalSummary =
                            summaryController.text.trim().isEmpty
                                ? finalTitle
                                : summaryController.text.trim();

                        final String sourceName =
                            isYt ? "Ø±ØµØ¯ ÙŠÙˆØªÙŠÙˆØ¨ Ù…Ø¨Ø§Ø´Ø±" : "Ø±ØµØ¯ ÙÙŠØ³Ø¨ÙˆÙƒ Ù…Ø¨Ø§Ø´Ø±";
                        final String itemType =
                            (selectedCategory == "ØªÙ‚Ø§Ø±ÙŠØ± Ù…ØªÙ„ÙØ²Ø©" || isYt)
                                ? "tv"
                                : "facebook";

                        final newPost = <String, dynamic>{
                          "title": finalTitle,
                          "summary": finalSummary,
                          "source": sourceName,
                          "category": selectedCategory,
                          "type": itemType,
                          "time": nowInfo["display"],
                          "timestamp": nowTs,
                          "url": finalUrl,
                          "important": selectedCategory == "ØªÙŠØ³Ù…Ø³ÙŠÙ„Øª",
                        };

                        setState(() {
                          newsList.insert(0, newPost);
                        });
                        Navigator.pop(context);
                        await _publishPostToCloud(newPost);
                        await _saveNewsToStorage();
                      },
                    ),
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openNewsLink(String urlString) async {
    if (urlString.isEmpty) return;
    final Uri url = Uri.parse(urlString);
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  @override
  void dispose() {
    _intentSub.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List filteredNews = newsList.where((item) {
      bool matchesTab = true;
      if (selectedTab == "ÙÙŠØ³Ø¨ÙˆÙƒ") {
        matchesTab = item["type"] == "facebook" || item["cloudId"] != null;
      } else if (selectedTab != "Ø§Ù„ÙƒÙ„") {
        matchesTab = item["category"] == selectedTab;
      }

      bool matchesSearch = searchQuery.isEmpty ||
          item["title"].toString().contains(searchQuery) ||
          (item["summary"] ?? "").toString().contains(searchQuery) ||
          item["source"].toString().contains(searchQuery);

      return matchesTab && matchesSearch;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Ø±Ø§ØµØ¯ Ø§Ù„ØªØ±Ø¨ÙŠØ© - ÙˆÙ„Ø§ÙŠØ© ØªÙŠØ³Ù…Ø³ÙŠÙ„Øª",
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text(
              "Ø¥Ø¬Ù…Ø§Ù„ÙŠ Ø§Ù„Ø£Ø®Ø¨Ø§Ø± Ø§Ù„Ù…Ø±ØµÙˆØ¯Ø©: ${newsList.length} Ø®Ø¨Ø± Ø­Ø¯ÙŠØ«",
              style: const TextStyle(fontSize: 11, color: Colors.amberAccent),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<int>(
            tooltip: "ØªØ­Ø¯ÙŠØ¯ Ø­Ø¯Ø§Ø«Ø© Ø§Ù„Ø£Ø®Ø¨Ø§Ø±",
            icon: const Icon(Icons.history_toggle_off, color: Colors.white),
            onSelected: (days) {
              setState(() {
                maxDaysOld = days;
                newsList.removeWhere((item) => item['cloudId'] == null);
              });
              runSmartRadarBot();
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                  value: 1, child: Text("Ø£Ø®Ø¨Ø§Ø± Ø¢Ø®Ø± 24 Ø³Ø§Ø¹Ø© ÙÙ‚Ø· (Ø¹Ø§Ø¬Ù„)")),
              const PopupMenuItem(value: 3, child: Text("Ø£Ø®Ø¨Ø§Ø± Ø¢Ø®Ø± 3 Ø£ÙŠØ§Ù…")),
              const PopupMenuItem(
                  value: 7, child: Text("Ø£Ø®Ø¨Ø§Ø± Ù‡Ø°Ø§ Ø§Ù„Ø£Ø³Ø¨ÙˆØ¹ (7 Ø£ÙŠØ§Ù…)")),
            ],
          ),
          IconButton(
            onPressed: isScanning ? null : runSmartRadarBot,
            tooltip: "ØªØ­Ø¯ÙŠØ« ÙˆØ³Ø­Ø¨ Ø§Ù„Ø£Ø®Ø¨Ø§Ø± Ø§Ù„Ø¬Ø¯ÙŠØ¯Ø© Ø§Ù„Ø¢Ù†",
            icon: isScanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.amber, strokeWidth: 2))
                : const Icon(Icons.radar, color: Colors.amberAccent, size: 28),
          ),
          const SizedBox(width: 6),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(105),
          child: Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: TextField(
                  onChanged: (val) => setState(() => searchQuery = val),
                  decoration: InputDecoration(
                    hintText:
                        "Ø§Ø¨Ø­Ø« ÙÙŠ Ø§Ù„Ø¹Ù†Ø§ÙˆÙŠÙ† ÙˆØ§Ù„Ù…Ù„Ø®ØµØ§Øª (ØªÙŠØ³Ù…Ø³ÙŠÙ„ØªØŒ Ø§Ù…ØªØ­Ø§Ù†ØŒ Ø¨Ù„Ø¯ÙŠØ©...)",
                    prefixIcon:
                        const Icon(Icons.search, color: Color(0xFF1A237E)),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Container(
                color: Colors.white,
                width: double.infinity,
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  labelColor: const Color(0xFF1A237E),
                  unselectedLabelColor: Colors.grey.shade600,
                  indicatorColor: const Color(0xFFD97706),
                  indicatorWeight: 3,
                  tabs: const [
                    Tab(text: "Ø§Ù„ÙƒÙ„"),
                    Tab(text: "ØªÙŠØ³Ù…Ø³ÙŠÙ„Øª"),
                    Tab(text: "ÙˆØ·Ù†ÙŠ"),
                    Tab(text: "ØªÙ‚Ø§Ø±ÙŠØ± Ù…ØªÙ„ÙØ²Ø©"),
                    Tab(text: "ÙÙŠØ³Ø¨ÙˆÙƒ"),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: isScanning && newsList.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 14),
                  Text(
                      "Ø¬Ø§Ø±ÙŠ Ø³Ø­Ø¨ ÙˆØªÙ„Ø®ÙŠØµ Ø£Ø­Ø¯Ø« Ø§Ù„Ø£Ø®Ø¨Ø§Ø± ÙˆØ§Ù„ØªÙ‚Ø§Ø±ÙŠØ± Ø¨Ø§Ù„ØªÙˆÙ‚ÙŠØª Ø§Ù„Ø­Ù‚ÙŠÙ‚ÙŠ..."),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: runSmartRadarBot,
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: filteredNews.length,
                itemBuilder: (context, index) {
                  final item = filteredNews[index];
                  final bool isImportant = item["important"] == true;
                  final String type = (item["type"] ?? "press").toString();

                  IconData badgeIcon = Icons.article;
                  Color badgeColor = Colors.teal.shade700;
                  if (type == "facebook") {
                    badgeIcon = Icons.facebook;
                    badgeColor = const Color(0xFF1877F2);
                  } else if (type == "tv") {
                    badgeIcon = Icons.live_tv;
                    badgeColor = Colors.red.shade700;
                  }

                  return Card(
                    elevation: 2,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isImportant
                            ? Colors.amber.shade700
                            : Colors.transparent,
                        width: isImportant ? 1.5 : 0,
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _showArticleSummarySheet(item),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(badgeIcon, size: 17, color: badgeColor),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Text(
                                    (item["source"] ?? "").toString(),
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: badgeColor),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isImportant)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade50,
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      "ØªÙŠØ³Ù…Ø³ÙŠÙ„Øª",
                                      style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.red.shade800),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(Icons.schedule,
                                    size: 13, color: Colors.grey.shade600),
                                const SizedBox(width: 4),
                                Text(
                                  (item["time"] ?? "").toString(),
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade700,
                                      fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              (item["title"] ?? "").toString(),
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  height: 1.35),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                (item["summary"] ?? item["title"] ?? "")
                                    .toString(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12.5,
                                    color: Colors.grey.shade800,
                                    height: 1.4),
                              ),
                            ),
                            const Divider(height: 16),
                            Row(
                              children: [
                                TextButton.icon(
                                  onPressed: () =>
                                      _showArticleSummarySheet(item),
                                  icon: Icon(
                                      type == "tv"
                                          ? Icons.ondemand_video
                                          : Icons.menu_book,
                                      size: 16),
                                  label: Text(type == "tv"
                                      ? "Ù…Ù„Ø®Øµ Ø§Ù„ØªÙ‚Ø±ÙŠØ± ÙˆØ§Ù„ÙÙŠØ¯ÙŠÙˆ"
                                      : "Ù‚Ø±Ø§Ø¡Ø© Ø§Ù„Ù…Ù„Ø®Øµ"),
                                ),
                                TextButton.icon(
                                  onPressed: () => _openNewsLink(
                                      (item["url"] ?? "").toString()),
                                  icon: const Icon(Icons.open_in_new, size: 15),
                                  label: const Text("Ø§Ù„Ù…ØµØ¯Ø±"),
                                ),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.redAccent, size: 19),
                                  onPressed: () async {
                                    final cloudId = item['cloudId'];
                                    setState(() {
                                      newsList.remove(item);
                                    });
                                    await _saveNewsToStorage();
                                    if (cloudId != null) {
                                      try {
                                        await http.delete(Uri.parse(
                                            '$_firebaseBaseUrl/$cloudId.json'));
                                      } catch (_) {}
                                    }
                                  },
                                ),
                              ],
                            )
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF1877F2),
        foregroundColor: Colors.white,
        onPressed: () => _showAddFacebookModal(),
        icon: const Icon(Icons.add_link),
        label: const Text("Ø¥Ø¶Ø§ÙØ© Ù…Ù† ÙÙŠØ³Ø¨ÙˆÙƒ",
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}
