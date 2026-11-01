import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const TikTokExplorerApp());
}

class TikTokExplorerApp extends StatelessWidget {
  const TikTokExplorerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TikTok Saved Feed',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF090A0F),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFE2C55),
          secondary: Color(0xFF25F4EE),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class VideoItem {
  final String id;
  final String date;
  final String link;
  final String content;
  String? coverUrl;
  String? author;
  String? title;

  VideoItem({
    required this.id,
    required this.date,
    required this.link,
    required this.content,
    this.coverUrl,
    this.author,
    this.title,
  });
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, List<VideoItem>> categories = {};
  String currentCategory = "Favorite Videos";
  List<VideoItem> displayedItems = [];
  bool isLoading = false;
  String statusText = "Pilih file user_data.json TikTok";

  Future<void> pickAndLoadJson() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    setState(() {
      isLoading = true;
      statusText = "Membaca file JSON (10.8 MB)...";
    });

    try {
      final bytes = result.files.first.bytes;
      if (bytes == null) throw Exception("Gagal membaca byte data");
      
      final jsonString = utf8.decode(bytes);
      final rawData = jsonDecode(jsonString);

      setState(() => statusText = "Mengekstrak data video...");

      final Map<String, List<VideoItem>> parsed = {};
      final block = _findBlock(rawData);

      if (block != null) {
        block.forEach((k, v) {
          List items = [];
          if (v is List) {
            items = v;
          } else if (v is Map) {
            for (var val in v.values) {
              if (val is List) { items = val; break; }
            }
          }

          parsed[k.toString()] = items.map((item) {
            final rawDate = item['Date'] ?? item['date'] ?? '';
            final link = (item['Link'] ?? item['link'] ?? item['VideoLink'] ?? '').toString();
            final content = (item['FavoriteComment'] ?? item['Comment'] ?? '').toString();

            String id = "";
            final match = RegExp(r'(?:video/|/share/video/)(\d{15,22})').firstMatch(link);
            if (match != null) id = match.group(1)!;

            return VideoItem(
              id: id,
              date: rawDate.toString().split(' ').first,
              link: link,
              content: content,
            );
          }).toList();
        });
      }

      setState(() {
        categories = parsed;
        if (categories.containsKey("Favorite Videos")) {
          currentCategory = "Favorite Videos";
        } else if (categories.isNotEmpty) {
          currentCategory = categories.keys.first;
        }
        displayedItems = categories[currentCategory] ?? [];
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
        statusText = "Gagal: $e";
      });
    }
  }

  dynamic _findBlock(dynamic root) {
    if (root is! Map) return null;
    for (var k in root.keys) {
      if (k.toString().toLowerCase().contains('likes and favorites') ||
          k.toString().toLowerCase() == 'favorite videos') {
        return root[k] is Map ? root[k] : root;
      }
    }
    for (var v in root.values) {
      if (v is Map) {
        final res = _findBlock(v);
        if (res != null) return res;
      }
    }
    return null;
  }

  void openVideo(VideoItem item, int index) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VideoPlayerModal(
        items: displayedItems,
        initialIndex: index,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              color: Colors.black.withOpacity(0.4),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.centerLeft,
              child: SafeArea(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'TikTok Feed',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFE2C55),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      onPressed: pickAndLoadJson,
                      icon: const Icon(Icons.folder_open, size: 16, color: Colors.white),
                      label: const Text('Buka JSON', style: TextStyle(color: Colors.white, fontSize: 12)),
                    )
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      body: displayedItems.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isLoading) const CircularProgressIndicator(color: Color(0xFFFE2C55)),
                  const SizedBox(height: 16),
                  Text(statusText, style: const TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(10, 85, 10, 20),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 9 / 14,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: displayedItems.length,
              itemBuilder: (context, index) {
                final item = displayedItems[index];
                return VideoCard(
                  item: item,
                  onTap: () => openVideo(item, index),
                );
              },
            ),
    );
  }
}

class VideoCard extends StatefulWidget {
  final VideoItem item;
  final VoidCallback onTap;

  const VideoCard({super.key, required this.item, required this.onTap});

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard> {
  @override
  void initState() {
    super.initState();
    if (widget.item.coverUrl == null && widget.item.id.isNotEmpty) {
      _fetchCover();
    }
  }

  Future<void> _fetchCover() async {
    try {
      final res = await http.get(Uri.parse('https://www.tikwm.com/api/?url=${widget.item.id}'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['data'];
        if (data != null && mounted) {
          setState(() {
            widget.item.coverUrl = data['cover'] ?? data['origin_cover'];
            widget.item.author = data['author']?['nickname'];
            widget.item.title = data['title'];
          });
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF161822),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (widget.item.coverUrl != null)
                CachedNetworkImage(
                  imageUrl: widget.item.coverUrl!,
                  fit: BoxFit.cover,
                )
              else
                Container(
                  color: const Color(0xFF12141D),
                  child: const Center(
                    child: Icon(Icons.play_circle_fill, size: 36, color: Colors.white24),
                  ),
                ),
              // Efek Liquid Glass Gradient
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.6),
                      Colors.transparent,
                      Colors.black.withOpacity(0.85),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: Text(
                  widget.item.author != null ? '@${widget.item.author}' : 'TikTok',
                  style: const TextStyle(fontSize: 10, color: Color(0xFF25F4EE), fontWeight: FontWeight.bold),
                ),
              ),
              Positioned(
                bottom: 8,
                left: 8,
                right: 8,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.item.title ?? widget.item.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(widget.item.date, style: const TextStyle(fontSize: 9, color: Colors.white54)),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}

class VideoPlayerModal extends StatefulWidget {
  final List<VideoItem> items;
  final int initialIndex;

  const VideoPlayerModal({super.key, required this.items, required this.initialIndex});

  @override
  State<VideoPlayerModal> createState() => _VideoPlayerModalState();
}

class _VideoPlayerModalState extends State<VideoPlayerModal> {
  late int currentIndex;

  @override
  void initState() {
    super.initState();
    currentIndex = widget.initialIndex;
  }

  void openInApp() async {
    final item = widget.items[currentIndex];
    final uri = Uri.parse('snssdk1180://aweme/detail/${item.id}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      await launchUrl(Uri.parse('https://www.tiktok.com/@/video/${item.id}'), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.items[currentIndex];

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.75),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: Colors.white.withOpacity(0.15)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('ID: ${item.id}', style: const TextStyle(color: Color(0xFF25F4EE), fontFamily: 'monospace')),
                IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context))
              ],
            ),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (item.coverUrl != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: CachedNetworkImage(imageUrl: item.coverUrl!, height: 350, fit: BoxFit.cover),
                      ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFE2C55),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      ),
                      onPressed: openInApp,
                      icon: const Icon(Icons.play_arrow, color: Colors.white),
                      label: const Text('Putar Video di Aplikasi TikTok', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    )
                  ],
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton(
                  onPressed: currentIndex > 0 ? () => setState(() => currentIndex--) : null,
                  child: const Text('⏮ Sebelumnya'),
                ),
                Text('${currentIndex + 1} / ${widget.items.length}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ElevatedButton(
                  onPressed: currentIndex < widget.items.length - 1 ? () => setState(() => currentIndex++) : null,
                  child: const Text('Berikutnya ⏭'),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
