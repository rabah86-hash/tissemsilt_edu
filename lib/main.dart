import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RabahEduNewsApp());
}

class RabahEduNewsApp extends StatelessWidget {
  const RabahEduNewsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'تطبيق Rabah لأخبار التربية والتعليم',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0A1931),
          primary: const Color(0xFF0A1931),
          secondary: const Color(0xFFD97706),
          surface: const Color(0xFFF3F6FB),
        ),
        scaffoldBackgroundColor: const Color(0xFFF3F6FB),
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
  State createState() => _NewsDashboardState();
}

class _NewsDashboardState extends State
    with SingleTickerProviderStateMixin {
  static const String _firebaseDbUrl =
      'https://tissemsilt-edu-default-rtdb.firebaseio.com/shared_posts.json';
  static const String _firebaseBaseUrl =
      'https://tissemsilt-edu-default-rtdb.firebaseio.com/shared_posts';

  late TabController _tabController;
  late StreamSubscription _intentSub;
  final TextEditingController _searchController = TextEditingController();

  bool isScanning = false;
  bool isCustomSearching = false;
  String searchQuery = "";
  String selectedTab = "الكل";
  int maxDaysOld = 7;

  List newsList = [];

  final List tissemsiltKeywords = [
    "تيسمسيلت", "ثنية الحد", "برج بونعامة", "خميستي", "لرجام",
    "عماري", "بوقايد", "الأزهرية", "برج الأمير عبد القادر", "سيدي سليمان",
    "أولاد بسام", "ملعب", "سيدي عابد", "تملاحت", "سيدي بوتشنت",
    "العيون", "اليوسفية", "سيدي العنتري", "معاصم"
  ];

  final List tabs = [
    "الكل",
    "تيسمسيلت",
    "المواقع والصحافة",
    "القنوات واليوتيوب",
    "فيسبوك والمشاركات"
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: tabs.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          selectedTab = tabs[_tabController.index].toString();
        });
      }
    });
    _loadSavedNews();
    _initSharingIntent();
  }

  void _initSharingIntent() {
    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      (value) {
        if (value.isNotEmpty) {
          _openQuickShareFromExternalApp(value.first.path);
        }
      },
      onError: (err) => debugPrint("Share Error: $err"),
    );

    ReceiveSharingIntent.instance.getInitialMedia().then(
      (value) {
        if (value.isNotEmpty) {
          _openQuickShareFromExternalApp(value.first.path);
          ReceiveSharingIntent.instance.reset();
        }
      },
    );
  }

  // استخراج الرابط والنص عند المشاركة من فيسبوك أو يوتيوب أو المواقع الإلكترونية
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
    final bool isFacebook = extractedUrl.contains("facebook.com") ||
        extractedUrl.contains("fb.watch") ||
        extractedUrl.contains("fb.com");

    String defaultCat = "المواقع والصحافة";
    if (isYoutube) {
      defaultCat = "القنوات واليوتيوب";
    } else if (isFacebook) {
      defaultCat = "تيسمسيلت";
    }

    _showAddShareModal(
      prefillUrl: extractedUrl,
      prefillTitle: extractedTitle,
      defaultCategory: defaultCat,
    );
  }

  // جلب عنوان الخبر الحقيقي تلقائياً من رابط يوتيوب أو فيسبوك أو موقع إلكتروني
  Future> _autoFetchLinkMetadata(String url) async {
    String detectedTitle = "";
    String detectedAuthor = "";

    try {
      // 1. محاولة الجلب السريع عبر NoEmbed (يدعم يوتيوب وفيسبوك والمواقع العالمية)
      final noembedUri = Uri.parse(
          'https://noembed.com/embed?url=${Uri.encodeComponent(url)}');
      final res =
          await http.get(noembedUri).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = json.decode(utf8.decode(res.bodyBytes));
        if (data is Map) {
          detectedTitle = (data['title'] ?? '').toString().trim();
          detectedAuthor = (data['author_name'] ?? '').toString().trim();
        }
      }
    } catch (_) {}

    // 2. إذا كان موقعاً إلكترونياً إخبارياً، نستخرج وسم <title> أو og:title من صفحة الويب
    if (detectedTitle.isEmpty) {
      try {
        final proxyUri = Uri.parse(
            'https://api.allorigins.win/raw?url=${Uri.encodeComponent(url)}');
        final res =
            await http.get(proxyUri).timeout(const Duration(seconds: 6));
        if (res.statusCode == 200) {
          final html = utf8.decode(res.bodyBytes, allowMalformed: true);
          final ogMatch = RegExp(
                  r'property=["\x27]og:title["\x27]\s+content=["\x27]([^"\x27]+)["\x27]',
                  caseSensitive: false)
              .firstMatch(html);
          if (ogMatch != null) {
            detectedTitle = ogMatch.group(1)!.trim();
          } else {
            final titleMatch = RegExp(r'<title[^>]*>([^<]+)<\/title>',
                    caseSensitive: false)
                .firstMatch(html);
            if (titleMatch != null) {
              detectedTitle = titleMatch.group(1)!.trim();
            }
          }
        }
      } catch (_) {}
    }

    return {
      "title": _stripHtmlCompletly(detectedTitle),
      "author": detectedAuthor,
    };
  }

  Future _loadSavedNews() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? savedData = prefs.getString('rabah_edu_news_v4');
      if (savedData != null && savedData.isNotEmpty) {
        final decoded = json.decode(savedData) as List;
        if (decoded.isNotEmpty) {
          setState(() {
            newsList = decoded;
          });
        }
      }
    } catch (_) {}

    await _fetchCloudPosts();
    if (newsList.isEmpty) {
      runFastParallelEngine();
    }
  }

  Future _saveNewsToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('rabah_edu_news_v4', json.encode(newsList));
    } catch (_) {}
  }

  Future _fetchCloudPosts() async {
    try {
      final response = await http
          .get(Uri.parse(_firebaseDbUrl))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final decoded = json.decode(utf8.decode(response.bodyBytes));
        if (decoded != null && decoded is Map) {
          decoded.forEach((key, value) {
            if (value is Map) {
              final String title = _stripHtmlCompletly((value["title"] ?? "").toString());
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
              final postMap = {
                "cloudId": key,
                "title": title,
                "summary": _cleanSummaryText(
                  (value["summary"] ?? "").toString(),
                  title,
                  (value["source"] ?? "متابعة خاصة").toString(),
                ),
                "source": (value["source"] ?? "متابعة خاصة").toString(),
                "category": (value["category"] ?? "تيسمسيلت").toString(),
                "type": (value["type"] ?? "facebook").toString(),
                "time": timeInfo["display"],
                "timestamp": ts,
                "url": url,
                "important": (value["category"] ?? "تيسمسيلت") == "تيسمسيلت",
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

  Future _publishPostToCloud(Map postData) async {
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
              content: const Text("تم النشر بنجاح! يظهر الخبر وعنوانه الآن لدى جميع المستخدمين."),
              backgroundColor: Colors.green.shade800,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("تم الحفظ في جهازك (تحقق من الاتصال لنشره سحابياً)."),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Map _parseRealTime(String rawDate) {
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
      relative = "الآن";
    } else if (diff.inMinutes < 60) {
      relative = "منذ ${diff.inMinutes} دقيقة";
    } else if (diff.inHours < 24) {
      relative = "منذ ${diff.inHours} ساعة";
    } else {
      relative = "منذ ${diff.inDays} يوم";
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

  // تنظيف جذري لأي أكواد HTML مشفرة مرتين مثل &lt;a href=...&gt; والروابط الطويلة
  String _stripHtmlCompletly(String input) {
    String s = input
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&laquo;', '«')
        .replaceAll('&raquo;', '»');

    // مسح جميع وسوم HTML بعد فك التشفير
    s = s.replaceAll(RegExp(r'<[^>]*>'), ' ');
    // مسح أي بقايا وسوم مشوهة مثل lt;a href=... أو target="_blank" أو font
    s = s.replaceAll(RegExp(r'(lt;|gt;|href=|target=|font|color=)[^\s]*', caseSensitive: false), ' ');
    // مسح الروابط الطويلة من داخل النص
    s = s.replaceAll(RegExp(r'https?:\/\/[^\s]+'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  // بناء ملخص عربي نظيف وأنيق 100% للخبر أو الفيديو
  String _cleanSummaryText(String rawHtml, String cleanTitle, String sourceName) {
    String text = _stripHtmlCompletly(rawHtml);

    if (text.startsWith(cleanTitle)) {
      text = text.substring(cleanTitle.length).trim();
    }
    if (text.endsWith(sourceName)) {
      text = text.substring(0, text.length - sourceName.length).trim();
    }
    text = text.replaceAll(RegExp(r'^[-–—:\s•|]+'), '').trim();

    // إذا كان المصدر (مثل Google News) لا يرسل سوى العنوان المكرر داخل كود HTML، نولد ملخصاً إخبارياً واضحاً ومنسقاً
    if (text.length < 30 || text == cleanTitle || text.contains("news.google")) {
      return "تفاصيل الخبر: «$cleanTitle» — صادر عبر ($sourceName) ضمن التغطية المستمرة لمستجدات قطاع التربية والتعليم في الجزائر. اضغط على زر المصدر بالأسفل لمطالعة النص الكامل أو مشاهدة التقرير.";
    }
    return text.length > 360 ? "${text.substring(0, 360)}..." : text;
  }

  String _extractTagContent(String xml, String tag) {
    final startTag = "<$tag>";
    final endTag = "</$tag>";
    int startIndex = xml.indexOf(startTag);
    if (startIndex == -1) {
      startIndex = xml.indexOf("<$tag ");
      if (startIndex != -1) {
        startIndex = xml.indexOf(">", startIndex);
        if (startIndex != -1) startIndex += 1;
      }
    } else {
      startIndex += startTag.length;
    }
    if (startIndex == -1) return "";
    int endIndex = xml.indexOf(endTag, startIndex);
    if (endIndex == -1) return "";
    return xml
        .substring(startIndex, endIndex)
        .replaceAll("<![CDATA[", "")
        .replaceAll("]]>", "")
        .trim();
  }

  Future<List> _fetchSingleChannel(Map queryObj) async {
    final String qText = queryObj["q"].toString();
    final String qType = queryObj["type"].toString();
    final bool forceLocal = queryObj["forceLocal"] == true;
    final encodedQuery = Uri.encodeComponent(qText);
    final targetRss =
        'https://news.google.com/rss/search?q=$encodedQuery&hl=ar&gl=DZ&ceid=DZ:ar';

    final rss2jsonUrl = Uri.parse(
        'https://api.rss2json.com/v1/api.json?rss_url=${Uri.encodeComponent(targetRss)}');
    final allOriginsUrl = Uri.parse(
        'https://api.allorigins.win/raw?url=${Uri.encodeComponent(targetRss)}');

    List results = [];
    bool fetched = false;

    try {
      final response =
          await http.get(rss2jsonUrl).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final Map data = json.decode(utf8.decode(response.bodyBytes)) as Map;
        if (data["status"] == "ok" && data["items"] != null) {
          fetched = true;
          final List items = data["items"] as List;
          for (var item in items) {
            final String rawTitle = _stripHtmlCompletly((item["title"] ?? "").toString());
            if (rawTitle.isEmpty) continue;

            String cleanTitle = rawTitle;
            String extractedSource =
                qType == "tv" ? "تقرير تلفزيوني / يوتيوب" : "المواقع الإخبارية";
            if (rawTitle.contains(" - ")) {
              final splitParts = rawTitle.split(" - ");
              extractedSource = splitParts.last.trim();
              cleanTitle =
                  splitParts.sublist(0, splitParts.length - 1).join(" - ").trim();
            }

            final String link = (item["link"] ?? "").toString().trim();
            final String rawDate = (item["pubDate"] ?? "").toString();
            final String rawDesc =
                (item["description"] ?? item["content"] ?? "").toString();

            final Map timeInfo = _parseRealTime(rawDate);
            if ((timeInfo["daysOld"] as int) > maxDaysOld) continue;

            bool isTissemsilt = forceLocal ||
                tissemsiltKeywords.any((k) =>
                    cleanTitle.contains(k.toString()) ||
                    rawDesc.contains(k.toString()));
            bool isVideoItem = qType == "tv" ||
                link.contains("youtube.com") ||
                link.contains("youtu.be") ||
                cleanTitle.contains("فيديو") ||
                cleanTitle.contains("تقرير") ||
                cleanTitle.contains("روبورتاج") ||
                cleanTitle.contains("شاهد") ||
                extractedSource.contains("النهار") ||
                extractedSource.contains("الشروق نيوز") ||
                extractedSource.contains("البلاد") ||
                extractedSource.contains("التلفزيون");

            String category = isTissemsilt
                ? "تيسمسيلت"
                : (isVideoItem ? "القنوات واليوتيوب" : "المواقع والصحافة");

            results.add({
              "title": cleanTitle,
              "summary": _cleanSummaryText(rawDesc, cleanTitle, extractedSource),
              "source": extractedSource,
              "category": category,
              "type": isVideoItem ? "tv" : "press",
              "time": timeInfo["display"],
              "timestamp": timeInfo["timestamp"],
              "url": link,
              "important": isTissemsilt
            });
          }
        }
      }
    } catch (_) {}

    if (!fetched) {
      try {
        final resp =
            await http.get(allOriginsUrl).timeout(const Duration(seconds: 7));
        if (resp.statusCode == 200) {
          final xmlBody = utf8.decode(resp.bodyBytes, allowMalformed: true);
          final parts = xmlBody.split("<item>");
          for (int i = 1; i < parts.length && i <= 15; i++) {
            final itemXml = parts[i];
            String rawTitle = _stripHtmlCompletly(_extractTagContent(itemXml, "title"));
            final link = _extractTagContent(itemXml, "link");
            final rawDate = _extractTagContent(itemXml, "pubDate");
            final rawDesc = _extractTagContent(itemXml, "description");
            String source = _stripHtmlCompletly(_extractTagContent(itemXml, "source"));

            if (rawTitle.isEmpty) continue;
            if (rawTitle.contains(" - ")) {
              final sp = rawTitle.split(" - ");
              if (source.isEmpty) source = sp.last.trim();
              rawTitle = sp.sublist(0, sp.length - 1).join(" - ").trim();
            }
            if (source.isEmpty) {
              source = qType == "tv" ? "قناة تلفزيونية / يوتيوب" : "موقع إخباري";
            }

            final Map timeInfo = _parseRealTime(rawDate);
            if ((timeInfo["daysOld"] as int) > maxDaysOld) continue;

            bool isTissemsilt = forceLocal ||
                tissemsiltKeywords.any((k) =>
                    rawTitle.contains(k.toString()) ||
                    rawDesc.contains(k.toString()));
            bool isVideoItem = qType == "tv" ||
                link.contains("youtube.com") ||
                link.contains("youtu.be") ||
                rawTitle.contains("فيديو") ||
                rawTitle.contains("تقرير") ||
                rawTitle.contains("شاهد");

            results.add({
              "title": rawTitle,
              "summary": _cleanSummaryText(rawDesc, rawTitle, source),
              "source": source,
              "category": isTissemsilt
                  ? "تيسمسيلت"
                  : (isVideoItem ? "القنوات واليوتيوب" : "المواقع والصحافة"),
              "type": isVideoItem ? "tv" : "press",
              "time": timeInfo["display"],
              "timestamp": timeInfo["timestamp"],
              "url": link,
              "important": isTissemsilt
            });
          }
        }
      } catch (_) {}
    }

    return results;
  }

  // محرك الجلب المتوازي الشامل (18 قناة تغطي تيسمسيلت، المواقع الإلكترونية، القنوات التلفزيونية، واليوتيوب)
  Future runFastParallelEngine() async {
    if (isScanning) return;
    setState(() => isScanning = true);

    await _fetchCloudPosts();

    final String timeFilter = "when:${maxDaysOld}d";

    final List queries = [
      // 1. أخبار ولاية تيسمسيلت وبلدياتها
      {"q": "تيسمسيلت تربية OR مديرية التربية تيسمسيلت $timeFilter", "type": "press", "forceLocal": true},
      {"q": "ولاية تيسمسيلت مدارس OR ثانوية OR متوسطة OR ابتدائية $timeFilter", "type": "press", "forceLocal": true},
      {"q": "تيسمسيلت (ثنية الحد OR برج بونعامة OR خميستي OR لرجام OR عماري) $timeFilter", "type": "press", "forceLocal": true},

      // 2. المواقع الإلكترونية والصحف الوطنية (كل ما يقال عن التعليم والتربية في الجزائر)
      {"q": "وزارة التربية الوطنية الجزائر OR وزير التربية $timeFilter", "type": "press", "forceLocal": false},
      {"q": "مديرية التربية الجزائر OR مديريات التربية الولائية $timeFilter", "type": "press", "forceLocal": false},
      {"q": "قطاع التربية والتعليم في الجزائر OR المنظومة التربوية OR المدارس الجزائرية $timeFilter", "type": "press", "forceLocal": false},
      {"q": "البكالوريا الجزائر OR شهادة التعليم المتوسط OR البيام OR تقييم المكتسبات $timeFilter", "type": "press", "forceLocal": false},
      {"q": "مسابقة الأساتذة OR توظيف التربية OR نتائج مسابقة التوظيف الجزائر $timeFilter", "type": "press", "forceLocal": false},
      {"q": "مدير متوسطة OR مدير ثانوية OR مفتش التربية OR مشرف تربية OR مقتصد $timeFilter", "type": "press", "forceLocal": false},
      {"q": "فضاء الأولياء OR الأرضية الرقمية وزارة التربية OR منحة التمدرس OR الكتاب المدرسي $timeFilter", "type": "press", "forceLocal": false},
      {"q": "نقابات التربية الجزائر OR القانون الأساسي لعمال التربية OR الإدماج $timeFilter", "type": "press", "forceLocal": false},
      {"q": "(الشروق أونلاين OR النهار أونلاين OR الخبر OR البلاد نت OR الجزائر الجديدة) التربية $timeFilter", "type": "press", "forceLocal": false},

      // 3. القنوات التلفزيونية الجزائرية والتقارير المصورة واليوتيوب حول التعليم
      {"q": "(قناة النهار OR الشروق نيوز) التربية OR التعليم OR المدارس OR الأساتذة $timeFilter", "type": "tv", "forceLocal": false},
      {"q": "(قناة البلاد OR التلفزيون الجزائري OR قناة الحياة OR الوطنية TV) التربية OR التعليم $timeFilter", "type": "tv", "forceLocal": false},
      {"q": "(تقرير OR فيديو OR روبورتاج OR تغطية) مديرية التربية OR قطاع التربية الجزائر $timeFilter", "type": "tv", "forceLocal": false},
      {"q": "(تقرير تلفزيوني OR شاهد OR بالصور والفيديو) مدارس الجزائر OR التلاميذ OR الامتحانات $timeFilter", "type": "tv", "forceLocal": false},
      {"q": "site:youtube.com وزارة التربية الوطنية الجزائر OR مديرية التربية $timeFilter", "type": "tv", "forceLocal": false},
      {"q": "site:youtube.com أخبار التربية والتعليم الجزائر OR مسابقة الأساتذة OR البكالوريا $timeFilter", "type": "tv", "forceLocal": false},
    ];

    final List<List> allBatches =
        await Future.wait(queries.map((q) => _fetchSingleChannel(q as Map)));

    int addedCount = 0;
    for (var batch in allBatches) {
      for (var item in batch) {
        final String title = (item['title'] ?? '').toString();
        bool exists = newsList.any((n) => n['title'].toString() == title);
        if (!exists && title.isNotEmpty) {
          newsList.add(item);
          addedCount++;
        }
      }
    }

    // تنظيف أي ملخص قديم يحتوي على أكواد HTML مشوهة من النسخة السابقة
    for (var item in newsList) {
      if (item is Map) {
        item['title'] = _stripHtmlCompletly((item['title'] ?? '').toString());
        item['summary'] = _cleanSummaryText(
          (item['summary'] ?? '').toString(),
          item['title'].toString(),
          (item['source'] ?? 'المصدر').toString(),
        );
      }
    }

    newsList.removeWhere((item) {
      if (item['cloudId'] != null) return false;
      final int ts = (item['timestamp'] ?? 0) as int;
      final ageDays = DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(ts))
          .inDays;
      return ageDays > maxDaysOld;
    });

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
              'اكتمل التحديث الفائق: تم جلب $addedCount خبر وتقرير تلفزيوني جديد.'),
          backgroundColor: const Color(0xFF0D9488),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future _searchCustomTopicOnline(String topic) async {
    final cleanTopic = topic.trim();
    if (cleanTopic.isEmpty || isCustomSearching) return;

    setState(() => isCustomSearching = true);

    final customQueries = [
      {"q": "$cleanTopic التربية والتعليم الجزائر", "type": "press", "forceLocal": cleanTopic.contains("تيسمسيلت")},
      {"q": "$cleanTopic (فيديو OR تقرير OR قناة النهار OR الشروق OR البلاد OR يوتيوب)", "type": "tv", "forceLocal": cleanTopic.contains("تيسمسيلت")},
    ];

    final batches = await Future.wait(
        customQueries.map((q) => _fetchSingleChannel(q as Map)));

    int found = 0;
    for (var batch in batches) {
      for (var item in batch) {
        final String title = (item['title'] ?? '').toString();
        if (!newsList.any((n) => n['title'].toString() == title)) {
          newsList.insert(0, item);
          found++;
        }
      }
    }

    await _saveNewsToStorage();
    if (mounted) {
      setState(() => isCustomSearching = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(found > 0
              ? 'تم جلب $found خبر وفيديو جديد حول "$cleanTopic"'
              : 'تمت فلترة الأخبار المعروضة حول "$cleanTopic"'),
          backgroundColor: const Color(0xFF0A1931),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showArticleSummarySheet(Map item) {
    final String type = (item["type"] ?? "press").toString();
    final bool isTv = type == "tv";
    final bool isFb = type == "facebook";

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isTv
                          ? Colors.red.shade50
                          : (isFb ? Colors.blue.shade50 : Colors.teal.shade50),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isTv
                          ? Icons.live_tv_rounded
                          : (isFb ? Icons.facebook_rounded : Icons.public_rounded),
                      color: isTv
                          ? Colors.red.shade700
                          : (isFb ? const Color(0xFF1877F2) : Colors.teal.shade700),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      (item["source"] ?? "").toString(),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Color(0xFF0A1931)),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  )
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.schedule_rounded,
                        size: 15, color: Colors.deepOrange),
                    const SizedBox(width: 6),
                    Text(
                      (item["time"] ?? "").toString(),
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepOrange),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A1931).withOpacity(0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border(
                    right: BorderSide(color: Colors.amber.shade700, width: 4),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "عنوان الخبر:",
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueGrey),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      (item["title"] ?? "").toString(),
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0A1931),
                          height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.indigo.shade100),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.auto_stories_rounded,
                            size: 16, color: Colors.amber.shade900),
                        const SizedBox(width: 6),
                        Text(
                          isTv ? "ملخص التقرير المتلفز / الفيديو:" : "ملخص الخبر الوافي:",
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Colors.amber.shade900),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      (item["summary"] ?? "").toString(),
                      style: const TextStyle(
                          fontSize: 14.5, height: 1.65, color: Colors.black87),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isTv ? Colors.red.shade700 : const Color(0xFF0A1931),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _openNewsLink((item["url"] ?? "").toString());
                  },
                  icon: Icon(
                      isTv ? Icons.play_circle_fill_rounded : Icons.open_in_new_rounded),
                  label: Text(
                    isTv
                        ? "مشاهدة الفيديو / التقرير من المصدر"
                        : "الدخول للموقع وقراءة المقال الكامل",
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // نافذة إضافة ومشاركة الروابط مع استخراج تلقائي لعنوان الخبر من فيسبوك ويوتيوب والمواقع
  void _showAddShareModal({
    String prefillUrl = "",
    String prefillTitle = "",
    String defaultCategory = "تيسمسيلت",
  }) {
    final linkController = TextEditingController(text: prefillUrl);
    final titleController = TextEditingController(text: prefillTitle);
    final summaryController = TextEditingController();
    String selectedCategory = defaultCategory;
    bool isFetchingTitle = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            // إذا تم تمرير رابط من المشاركة الخارجية ولم يكن له عنوان، نجلبه تلقائياً فوراً
            if (prefillUrl.isNotEmpty &&
                titleController.text.trim().isEmpty &&
                !isFetchingTitle) {
              isFetchingTitle = true;
              _autoFetchLinkMetadata(prefillUrl).then((meta) {
                if (meta["title"] != null && meta["title"]!.isNotEmpty) {
                  setModalState(() {
                    titleController.text = meta["title"]!;
                    if (meta["author"] != null && meta["author"]!.isNotEmpty) {
                      summaryController.text =
                          "تغطية مصورة / منشور من حساب (${meta["author"]}) حول: ${meta["title"]}";
                    }
                  });
                }
              });
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                left: 20,
                right: 20,
                top: 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1877F2).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.add_link_rounded,
                              color: Color(0xFF1877F2), size: 26),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            "إضافة خبر (فيسبوك / يوتيوب / موقع إلكتروني)",
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(context),
                        )
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: linkController,
                      onChanged: (val) async {
                        if (val.startsWith("http") &&
                            titleController.text.trim().isEmpty) {
                          final meta = await _autoFetchLinkMetadata(val.trim());
                          if (meta["title"] != null &&
                              meta["title"]!.isNotEmpty) {
                            setModalState(() {
                              titleController.text = meta["title"]!;
                            });
                          }
                        }
                      },
                      decoration: InputDecoration(
                        labelText: "رابط الخبر أو الفيديو (فيسبوك، يوتيوب، موقع...)",
                        prefixIcon: const Icon(Icons.link_rounded),
                        suffixIcon: IconButton(
                          tooltip: "جلب عنوان الخبر تلقائياً من الرابط",
                          icon: const Icon(Icons.auto_fix_high_rounded,
                              color: Color(0xFFD97706)),
                          onPressed: () async {
                            if (linkController.text.trim().isEmpty) return;
                            final meta = await _autoFetchLinkMetadata(
                                linkController.text.trim());
                            if (meta["title"] != null &&
                                meta["title"]!.isNotEmpty) {
                              setModalState(() {
                                titleController.text = meta["title"]!;
                              });
                            }
                          },
                        ),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: titleController,
                      decoration: InputDecoration(
                        labelText: "عنوان الخبر البارز في التطبيق (مهم)",
                        hintText: "اكتب عنواناً واضحاً للخبر أو الفيديو...",
                        prefixIcon: const Icon(Icons.title_rounded),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: summaryController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: "ملخص الخبر (اختياري - يتولد تلقائياً إن تركته فارغاً)",
                        prefixIcon: const Icon(Icons.notes_rounded),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField(
                      value: selectedCategory,
                      decoration: InputDecoration(
                        labelText: "القسم المناسب",
                        prefixIcon: const Icon(Icons.category_rounded),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: "تيسمسيلت",
                            child: Text("أخبار تيسمسيلت (أولوية قصوى)")),
                        DropdownMenuItem(
                            value: "المواقع والصحافة",
                            child: Text("المواقع الإلكترونية والصحافة الوطنية")),
                        DropdownMenuItem(
                            value: "القنوات واليوتيوب",
                            child: Text("التقارير المتلفزة واليوتيوب")),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setModalState(() => selectedCategory = val.toString());
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0A1931),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.cloud_upload_rounded),
                        label: const Text("نشر الخبر وعنوانه للجميع الآن",
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold)),
                        onPressed: () async {
                          String finalUrl = linkController.text.trim().isEmpty
                              ? "https://www.facebook.com"
                              : linkController.text.trim();
                          final bool isYt = finalUrl.contains("youtube.com") ||
                              finalUrl.contains("youtu.be");
                          final bool isFb = finalUrl.contains("facebook.com") ||
                              finalUrl.contains("fb.watch") ||
                              finalUrl.contains("fb.com");

                          String finalTitle = titleController.text.trim();
                          if (finalTitle.isEmpty) {
                            final meta = await _autoFetchLinkMetadata(finalUrl);
                            finalTitle = meta["title"] ?? "";
                          }
                          if (finalTitle.isEmpty) {
                            finalTitle = isYt
                                ? "تقرير مرئي وفيديو تربوي عبر يوتيوب"
                                : (isFb
                                    ? "مستجد تربوي هام عبر صفحة فيسبوك"
                                    : "مقال تربوي عبر موقع إلكتروني");
                          }

                          final int nowTs =
                              DateTime.now().millisecondsSinceEpoch;
                          final nowInfo =
                              _parseRealTime(DateTime.now().toIso8601String());

                          final String sourceName = isYt
                              ? "يوتيوب التعليمي"
                              : (isFb ? "فيسبوك التربوي" : "موقع إلكتروني");

                          final String finalSummary =
                              summaryController.text.trim().isEmpty
                                  ? _cleanSummaryText("", finalTitle, sourceName)
                                  : summaryController.text.trim();

                          final String itemType =
                              (selectedCategory == "القنوات واليوتيوب" || isYt)
                                  ? "tv"
                                  : (isFb ? "facebook" : "press");

                          final newPost = {
                            "title": finalTitle,
                            "summary": finalSummary,
                            "source": sourceName,
                            "category": selectedCategory,
                            "type": itemType,
                            "time": nowInfo["display"],
                            "timestamp": nowTs,
                            "url": finalUrl,
                            "important": selectedCategory == "تيسمسيلت",
                          };

                          setState(() {
                            newsList.insert(0, newPost);
                          });
                          if (context.mounted) Navigator.pop(context);
                          await _publishPostToCloud(newPost);
                          await _saveNewsToStorage();
                        },
                      ),
                    )
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future _openNewsLink(String urlString) async {
    if (urlString.isEmpty) return;
    final Uri url = Uri.parse(urlString);
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  @override
  void dispose() {
    _intentSub.cancel();
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List filteredNews = newsList.where((item) {
      bool matchesTab = true;
      if (selectedTab == "فيسبوك والمشاركات") {
        matchesTab = item["type"] == "facebook" || item["cloudId"] != null;
      } else if (selectedTab != "الكل") {
        matchesTab = item["category"] == selectedTab;
      }

      bool matchesSearch = searchQuery.isEmpty ||
          item["title"].toString().contains(searchQuery) ||
          (item["summary"] ?? "").toString().contains(searchQuery) ||
          item["source"].toString().contains(searchQuery);

      return matchesTab && matchesSearch;
    }).toList();

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(186),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0A1931), Color(0xFF153E90), Color(0xFF1E56A0)],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 10,
                offset: Offset(0, 4),
              )
            ],
          ),
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.amber.withOpacity(0.3),
                              blurRadius: 8,
                            )
                          ],
                        ),
                        child: const Icon(Icons.school_rounded,
                            color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "تطبيق Rabah لأخبار التربية والتعليم",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15.5,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Row(
                              children: [
                                const Icon(Icons.verified_rounded,
                                    color: Colors.amberAccent, size: 13),
                                const SizedBox(width: 4),
                                Text(
                                  "بوابة الجزائر وتيسمسيلت • ${newsList.length} عنوان",
                                  style: const TextStyle(
                                      fontSize: 11.5, color: Colors.amberAccent),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      PopupMenuButton(
                        tooltip: "نطاق البحث الزمني",
                        icon: const Icon(Icons.calendar_month_rounded,
                            color: Colors.white),
                        onSelected: (days) {
                          setState(() {
                            maxDaysOld = int.parse(days.toString());
                            newsList
                                .removeWhere((item) => item['cloudId'] == null);
                          });
                          runFastParallelEngine();
                        },
                        itemBuilder: (ctx) => const [
                          PopupMenuItem(
                              value: 1, child: Text("أخبار آخر 24 ساعة (عاجل)")),
                          PopupMenuItem(
                              value: 3, child: Text("أخبار آخر 3 أيام")),
                          PopupMenuItem(
                              value: 7, child: Text("أخبار الأسبوع (7 أيام)")),
                        ],
                      ),
                      IconButton(
                        onPressed: isScanning ? null : runFastParallelEngine,
                        tooltip: "تحديث فوري",
                        icon: isScanning
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.amberAccent, strokeWidth: 2))
                            : const Icon(Icons.bolt_rounded,
                                color: Colors.amberAccent, size: 28),
                      ),
                    ],
                  ),
                ),

                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        )
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(() => searchQuery = val),
                      onSubmitted: (val) => _searchCustomTopicOnline(val),
                      decoration: InputDecoration(
                        hintText: "اكتب عنواناً للبحث (مسابقة، قناة، مديرية، بكالوريا...)",
                        hintStyle: TextStyle(
                            fontSize: 12, color: Colors.grey.shade500),
                        prefixIcon: const Icon(Icons.manage_search_rounded,
                            color: Color(0xFF0A1931), size: 22),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (searchQuery.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.clear_rounded,
                                    size: 18, color: Colors.grey),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => searchQuery = "");
                                },
                              ),
                            InkWell(
                              onTap: () =>
                                  _searchCustomTopicOnline(_searchController.text),
                              child: Container(
                                margin: const EdgeInsets.all(5),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                alignment: Alignment.center,
                                child: isCustomSearching
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                            color: Colors.white, strokeWidth: 2))
                                    : const Row(
                                        children: [
                                          Icon(Icons.travel_explore_rounded,
                                              color: Colors.white, size: 14),
                                          SizedBox(width: 4),
                                          Text(
                                            "بحث شامل",
                                            style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ],
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                    ),
                  ),
                ),

                const Spacer(),

                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelColor: Colors.amberAccent,
                  unselectedLabelColor: Colors.white70,
                  indicatorColor: Colors.amberAccent,
                  indicatorWeight: 3,
                  dividerColor: Colors.transparent,
                  labelStyle: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13),
                  tabs: const [
                    Tab(
                      child: Row(
                        children: [
                          Icon(Icons.dashboard_rounded, size: 16),
                          SizedBox(width: 5),
                          Text("الكل"),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        children: [
                          Icon(Icons.location_on_rounded, size: 16),
                          SizedBox(width: 5),
                          Text("تيسمسيلت"),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        children: [
                          Icon(Icons.public_rounded, size: 16),
                          SizedBox(width: 5),
                          Text("المواقع والصحافة"),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        children: [
                          Icon(Icons.live_tv_rounded, size: 16),
                          SizedBox(width: 5),
                          Text("القنوات واليوتيوب"),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        children: [
                          Icon(Icons.facebook_rounded, size: 16),
                          SizedBox(width: 5),
                          Text("فيسبوك والمشاركات"),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
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
                    "جاري جلب أحدث العناوين من المواقع والقنوات التلفزيونية...",
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            )
          : filteredNews.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.travel_explore_rounded,
                            size: 64, color: Colors.indigo.shade200),
                        const SizedBox(height: 12),
                        Text(
                          searchQuery.isNotEmpty
                              ? 'لا توجد نتائج محلية لـ "$searchQuery"'
                              : 'لا توجد أخبار في هذا القسم حالياً',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        if (searchQuery.isNotEmpty)
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFD97706),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () =>
                                _searchCustomTopicOnline(searchQuery),
                            icon: const Icon(Icons.travel_explore_rounded),
                            label: Text('ابحث في المواقع والقنوات عن "$searchQuery"'),
                          )
                        else
                          ElevatedButton.icon(
                            onPressed: runFastParallelEngine,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text("جلب الأخبار الآن"),
                          ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: runFastParallelEngine,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 85),
                    itemCount: filteredNews.length,
                    itemBuilder: (context, index) {
                      final item = filteredNews[index] as Map;
                      final bool isImportant = item["important"] == true;
                      final String type = (item["type"] ?? "press").toString();

                      IconData badgeIcon = Icons.public_rounded;
                      Color badgeColor = const Color(0xFF0D9488);
                      String typeLabel = "موقع إخباري";
                      if (type == "facebook") {
                        badgeIcon = Icons.facebook_rounded;
                        badgeColor = const Color(0xFF1877F2);
                        typeLabel = "فيسبوك";
                      } else if (type == "tv") {
                        badgeIcon = Icons.live_tv_rounded;
                        badgeColor = const Color(0xFFDC2626);
                        typeLabel = "تقرير مرئي / قناة";
                      }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: isImportant
                                ? Colors.amber.shade600
                                : Colors.grey.shade200,
                            width: isImportant ? 1.6 : 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            )
                          ],
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => _showArticleSummarySheet(item),
                          child: Padding(
                            padding: const EdgeInsets.all(15),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(7),
                                      decoration: BoxDecoration(
                                        color: badgeColor.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(badgeIcon,
                                          size: 18, color: badgeColor),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            (item["source"] ?? "").toString(),
                                            style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                                color: badgeColor),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            typeLabel,
                                            style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.grey.shade500),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isImportant)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 9, vertical: 4),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              Colors.amber.shade100,
                                              Colors.amber.shade200
                                            ],
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(Icons.star_rounded,
                                                size: 13,
                                                color: Colors.amber.shade900),
                                            const SizedBox(width: 3),
                                            Text(
                                              "تيسمسيلت",
                                              style: TextStyle(
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.amber.shade900),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(Icons.access_time_filled_rounded,
                                        size: 13, color: Colors.grey.shade500),
                                    const SizedBox(width: 4),
                                    Text(
                                      (item["time"] ?? "").toString(),
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade600,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                // صندوق عنوان الخبر البارز
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0A1931)
                                        .withOpacity(0.03),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border(
                                      right: BorderSide(
                                          color: badgeColor, width: 3.5),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "عنوان الخبر:",
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold,
                                          color: badgeColor,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        (item["title"] ?? "").toString(),
                                        style: const TextStyle(
                                            fontSize: 15.5,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF0A1931),
                                            height: 1.38),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                // صندوق الملخص النظيف تماماً من أي كود
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: Colors.blueGrey.shade50),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.short_text_rounded,
                                              size: 15,
                                              color: Colors.amber.shade900),
                                          const SizedBox(width: 4),
                                          Text(
                                            "ملخص الخبر:",
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.amber.shade900,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        (item["summary"] ?? "").toString(),
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 12.5,
                                            color: Colors.grey.shade800,
                                            height: 1.45),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    TextButton.icon(
                                      onPressed: () =>
                                          _showArticleSummarySheet(item),
                                      icon: Icon(
                                          type == "tv"
                                              ? Icons.play_circle_fill_rounded
                                              : Icons.menu_book_rounded,
                                          size: 17,
                                          color: badgeColor),
                                      label: Text(
                                        type == "tv"
                                            ? "تفاصيل الفيديو"
                                            : "قراءة الملخص الكامل",
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: badgeColor),
                                      ),
                                    ),
                                    TextButton.icon(
                                      onPressed: () => _openNewsLink(
                                          (item["url"] ?? "").toString()),
                                      icon: const Icon(
                                          Icons.open_in_new_rounded,
                                          size: 15),
                                      label: const Text("فتح المصدر"),
                                    ),
                                    const Spacer(),
                                    IconButton(
                                      icon: const Icon(
                                          Icons.delete_outline_rounded,
                                          color: Colors.redAccent,
                                          size: 20),
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
        backgroundColor: const Color(0xFF0A1931),
        foregroundColor: Colors.white,
        elevation: 6,
        onPressed: () => _showAddShareModal(),
        icon: const Icon(Icons.add_link_rounded, color: Colors.amberAccent),
        label: const Text("إضافة رابط (فيسبوك / يوتيوب / موقع)",
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}