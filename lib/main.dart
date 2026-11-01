import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      title: 'TikTok Saved Explorer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF000000), // iOS True Black
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF007AFF), // iOS System Blue
          secondary: Color(0xFFFE2C55),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class VideoItem {
  final String id;
  final String date;
  final int timestamp;
  final String link;
  final String content;
  String? coverUrl;
  String? author;
  String? title;
  String? videoDownloadUrl;

  VideoItem({
    required this.id,
    required this.date,
    required this.timestamp,
    required this.link,
    required this.content,
    this.coverUrl,
    this.author,
    this.title,
    this.videoDownloadUrl,
  });
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, List<VideoItem>> allCategories = {};
  String selectedCategory = "Favorite Videos";
  List<VideoItem> activeList = [];
  List<VideoItem> filteredList = [];

  bool isLoading = false;
  String statusMessage = "Pilih file user_data.json TikTok";
  String searchQuery = "";
  String sortOrder = "newest";
  String selectedYear = "Semua";

  int currentPage = 1;
  int pageSize = 24;

  final TextEditingController searchController = TextEditingController();

  Future<void> pickJsonFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    setState(() {
      isLoading = true;
      statusMessage = "Membaca arsip data...";
    });

    try {
      String rawString = "";
      final fileData = result.files.first;

      if (fileData.bytes != null) {
        rawString = utf8.decode(fileData.bytes!);
      } else if (fileData.path != null) {
        final file = File(fileData.path!);
        rawString = await file.readAsString();
      } else {
        throw Exception("Gagal membaca file");
      }

      final dynamic root = jsonDecode(rawString);

      setState(() => statusMessage = "Menyusun feed video...");

      final Map<String, List<VideoItem>> parsed = {};
      final block = _findLikesFavorites(root);

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
            final rawDate = (item['Date'] ?? item['date'] ?? item['DateAdd'] ?? '').toString();
            final link = (item['Link'] ?? item['link'] ?? item['VideoLink'] ?? '').toString();
            final content = (item['FavoriteComment'] ?? item['FavoriteCollection'] ?? item['Comment'] ?? '').toString();

            String id = "";
            final match = RegExp(r'(?:video/|/share/video/)(\d{15,22})').firstMatch(link);
            if (match != null) id = match.group(1)!;

            int ts = 0;
            String displayDate = rawDate.split(' ').first;
            try {
              ts = DateTime.parse(rawDate.replaceAll(' ', 'T')).millisecondsSinceEpoch;
            } catch (_) {}

            return VideoItem(
              id: id,
              date: displayDate.isEmpty ? 'No Date' : displayDate,
              timestamp: ts,
              link: link,
              content: content,
            );
          }).toList();
        });
      }

      setState(() {
        allCategories = parsed;
        if (allCategories.containsKey("Favorite Videos")) {
          selectedCategory = "Favorite Videos";
        } else if (allCategories.isNotEmpty) {
          selectedCategory = allCategories.keys.first;
        }
        activeList = allCategories[selectedCategory] ?? [];
        isLoading = false;
        currentPage = 1;
        _applyFilter();
      });
    } catch (e) {
      setState(() {
        isLoading = false;
        statusMessage = "Gagal memproses data: $e";
      });
    }
  }

  dynamic _findLikesFavorites(dynamic root) {
    if (root is! Map) return null;
    for (var k in root.keys) {
      final str = k.toString().toLowerCase();
      if (str.contains('likes and favorites') || str == 'favorite videos' || str == 'like list') {
        return root[k] is Map ? root[k] : root;
      }
    }
    for (var v in root.values) {
      if (v is Map) {
        final res = _findLikesFavorites(v);
        if (res != null) return res;
      }
    }
    return null;
  }

  void _applyFilter() {
    List<VideoItem> temp = List.from(activeList);

    if (searchQuery.isNotEmpty) {
      final q = searchQuery.toLowerCase();
      temp = temp.where((item) {
        return item.id.contains(q) ||
               item.date.toLowerCase().contains(q) ||
               item.content.toLowerCase().contains(q) ||
               (item.title != null && item.title!.toLowerCase().contains(q)) ||
               (item.author != null && item.author!.toLowerCase().contains(q));
      }).toList();
    }

    if (selectedYear != "Semua") {
      temp = temp.where((item) => item.date.contains(selectedYear)).toList();
    }

    if (sortOrder == "newest") {
      temp.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    } else {
      temp.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    }

    setState(() {
      filteredList = temp;
      currentPage = 1;
    });
  }

  List<VideoItem> get pagedItems {
    final start = (currentPage - 1) * pageSize;
    if (start >= filteredList.length) return [];
    final end = (start + pageSize) > filteredList.length ? filteredList.length : start + pageSize;
    return filteredList.sublist(start, end);
  }

  int get totalPages => (filteredList.length / pageSize).ceil() == 0 ? 1 : (filteredList.length / pageSize).ceil();

  void openPlayerModal(int pagedIndex) {
    final absoluteIndex = (currentPage - 1) * pageSize + pagedIndex;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VideoDetailModal(
        items: filteredList,
        initialIndex: absoluteIndex,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      // iOS Navigation Bar
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              color: const Color(0x991C1C1E), // Apple Frosted Navigation Material
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SafeArea(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Tersimpan',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                    // iOS Capsule Button
                    GestureDetector(
                      onTap: pickJsonFile,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: const Color(0xFF007AFF), // Apple Blue
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.add, size: 16, color: Colors.white),
                            SizedBox(width: 4),
                            Text('Impor Data', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                          ],
                        ),
                      ),
                    )
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      body: allCategories.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isLoading)
                      const CircularProgressIndicator(color: Color(0xFF007AFF))
                    else
                      Icon(Icons.folder_outlined, size: 64, color: Colors.white.withOpacity(0.3)),
                    const SizedBox(height: 16),
                    Text(
                      statusMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13, height: 1.4),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                const SizedBox(height: 75),

                // 1. iOS CATEGORY PILLS (Apple Segmented Style)
                SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: allCategories.keys.map((cat) {
                      final isSelected = cat == selectedCategory;
                      final count = allCategories[cat]?.length ?? 0;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              selectedCategory = cat;
                              activeList = allCategories[cat] ?? [];
                              _applyFilter();
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.white : const Color(0xFF1C1C1E),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: isSelected ? Colors.transparent : Colors.white.withOpacity(0.08),
                                width: 0.5,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                '$cat ${count > 0 ? "($count)" : ""}',
                                style: TextStyle(
                                  color: isSelected ? Colors.black : Colors.white.withOpacity(0.7),
                                  fontSize: 12,
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                // 2. iOS SEARCH BAR & CONTROLS
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                  child: Row(
                    children: [
                      // iOS Rounded Search Box
                      Expanded(
                        child: Container(
                          height: 36,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1C1C1E),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white.withOpacity(0.08), width: 0.5),
                          ),
                          child: TextField(
                            controller: searchController,
                            style: const TextStyle(fontSize: 13, color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'Cari koleksi...',
                              hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13),
                              prefixIcon: Icon(Icons.search, size: 18, color: Colors.white.withOpacity(0.4)),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(vertical: 9),
                            ),
                            onChanged: (val) {
                              searchQuery = val;
                              _applyFilter();
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Dropdown Urutan
                      _buildIosDropdown<String>(
                        value: sortOrder,
                        items: const [
                          DropdownMenuItem(value: "newest", child: Text("Terbaru")),
                          DropdownMenuItem(value: "oldest", child: Text("Terlama")),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            sortOrder = val;
                            _applyFilter();
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                      // Dropdown Tahun
                      _buildIosDropdown<String>(
                        value: selectedYear,
                        accentColor: const Color(0xFF007AFF),
                        items: ["Semua", "2026", "2025", "2024", "2023", "2022", "2021", "2020"]
                            .map((y) => DropdownMenuItem(value: y, child: Text(y))).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            selectedYear = val;
                            _applyFilter();
                          }
                        },
                      ),
                    ],
                  ),
                ),

                // Sub-label Info & Paging Size
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${filteredList.length} video • Hal $currentPage dari $totalPages',
                        style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.5)),
                      ),
                      DropdownButton<int>(
                        value: pageSize,
                        isDense: true,
                        underline: const SizedBox(),
                        dropdownColor: const Color(0xFF1C1C1E),
                        style: const TextStyle(fontSize: 11, color: Color(0xFF007AFF), fontWeight: FontWeight.w500),
                        items: const [
                          DropdownMenuItem(value: 24, child: Text("24 per hal")),
                          DropdownMenuItem(value: 48, child: Text("48 per hal")),
                          DropdownMenuItem(value: 96, child: Text("96 per hal")),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              pageSize = val;
                              currentPage = 1;
                            });
                          }
                        },
                      )
                    ],
                  ),
                ),

                // 3. GRID VIDEO FEED iOS STYLE
                Expanded(
                  child: pagedItems.isEmpty
                      ? Center(child: Text("Tidak ada konten yang sesuai", style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13)))
                      : GridView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 9 / 14,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemCount: pagedItems.length,
                          itemBuilder: (context, index) {
                            final item = pagedItems[index];
                            return IosVideoCard(
                              item: item,
                              onTap: () => openPlayerModal(index),
                            );
                          },
                        ),
                ),

                // 4. iOS BOTTOM TOOLBAR (FROSTED GLASS PAGINATION)
                ClipRRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0x991C1C1E),
                        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08), width: 0.5)),
                      ),
                      child: SafeArea(
                        top: false,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            TextButton.icon(
                              onPressed: currentPage > 1 ? () => setState(() => currentPage--) : null,
                              icon: const Icon(Icons.arrow_back_ios, size: 14),
                              label: const Text('Sebelumnya', style: TextStyle(fontSize: 12)),
                            ),
                            Text(
                              '$currentPage / $totalPages',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                            ),
                            TextButton.icon(
                              onPressed: currentPage < totalPages ? () => setState(() => currentPage++) : null,
                              label: const Text('Berikutnya', style: TextStyle(fontSize: 12)),
                              icon: const Icon(Icons.arrow_forward_ios, size: 14),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              ],
            ),
    );
  }

  Widget _buildIosDropdown<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    Color? accentColor,
  }) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.08), width: 0.5),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          dropdownColor: const Color(0xFF1C1C1E),
          style: TextStyle(fontSize: 12, color: accentColor ?? Colors.white.withOpacity(0.85), fontWeight: FontWeight.w500),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class IosVideoCard extends StatefulWidget {
  final VideoItem item;
  final VoidCallback onTap;

  const IosVideoCard({super.key, required this.item, required this.onTap});

  @override
  State<IosVideoCard> createState() => _IosVideoCardState();
}

class _IosVideoCardState extends State<IosVideoCard> {
  @override
  void initState() {
    super.initState();
    if (widget.item.coverUrl == null && widget.item.id.isNotEmpty) {
      _fetchCover();
    }
  }

  Future<void> _fetchCover() async {
    try {
      final res = await http.get(Uri.parse('https://www.tikwm.com/api/?url=${widget.item.id}')).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['data'];
        if (data != null && mounted) {
          setState(() {
            widget.item.coverUrl = data['cover'] ?? data['origin_cover'];
            widget.item.author = data['author']?['nickname'];
            widget.item.title = data['title'];
            widget.item.videoDownloadUrl = data['play'];
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
        borderRadius: BorderRadius.circular(14), // Apple Squircle Curves
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E),
            border: Border.all(color: Colors.white.withOpacity(0.06), width: 0.5),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Apple Material Dark Fallback
              Container(
                color: const Color(0xFF1C1C1E),
                child: Center(
                  child: Icon(Icons.music_note, color: Colors.white.withOpacity(0.08), size: 36),
                ),
              ),

              // 2. Poster Image
              if (widget.item.coverUrl != null && widget.item.coverUrl!.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: widget.item.coverUrl!,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) => const SizedBox(),
                ),

              // 3. Apple Vignette Gradient
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.65),
                      Colors.transparent,
                      Colors.black.withOpacity(0.85),
                    ],
                  ),
                ),
              ),

              // Top Label (Creator & Date)
              Positioned(
                top: 8, left: 8, right: 8,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        widget.item.author != null ? '@${widget.item.author}' : 'TikTok',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      widget.item.date,
                      style: TextStyle(fontSize: 9, color: Colors.white.withOpacity(0.6)),
                    ),
                  ],
                ),
              ),

              // Apple Translucent Frosted Center Play Indicator
              Center(
                child: ClipOval(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withOpacity(0.35),
                        border: Border.all(color: Colors.white.withOpacity(0.4), width: 0.5),
                      ),
                      child: const Icon(Icons.play_arrow_rounded, size: 24, color: Colors.white),
                    ),
                  ),
                ),
              ),

              // Bottom Caption
              Positioned(
                bottom: 8, left: 8, right: 8,
                child: Text(
                  widget.item.title ?? (widget.item.content.isNotEmpty ? widget.item.content : 'Video #${widget.item.id}'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: Colors.white, height: 1.3, fontWeight: FontWeight.w400),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}

// iOS ACTION SHEET MODAL
class VideoDetailModal extends StatefulWidget {
  final List<VideoItem> items;
  final int initialIndex;

  const VideoDetailModal({super.key, required this.items, required this.initialIndex});

  @override
  State<VideoDetailModal> createState() => _VideoDetailModalState();
}

class _VideoDetailModalState extends State<VideoDetailModal> {
  late int currentIndex;

  @override
  void initState() {
    super.initState();
    currentIndex = widget.initialIndex;
    _checkDownloadLink();
  }

  void _checkDownloadLink() async {
    final item = widget.items[currentIndex];
    if (item.videoDownloadUrl == null && item.id.isNotEmpty) {
      try {
        final res = await http.get(Uri.parse('https://www.tikwm.com/api/?url=${item.id}')).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body)['data'];
          if (data != null && mounted) {
            setState(() {
              item.videoDownloadUrl = data['play'];
            });
          }
        }
      } catch (_) {}
    }
  }

  void watchInApp() async {
    final item = widget.items[currentIndex];
    final url = Uri.parse('https://www.tiktok.com/player/v1/${item.id}?autoplay=1&loop=1');
    await launchUrl(url, mode: LaunchMode.inAppBrowserView);
  }

  void openTikTokApp() async {
    final item = widget.items[currentIndex];
    final uri = Uri.parse('snssdk1180://aweme/detail/${item.id}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      await launchUrl(Uri.parse('https://www.tiktok.com/@/video/${item.id}'), mode: LaunchMode.externalApplication);
    }
  }

  void downloadVideo() async {
    final item = widget.items[currentIndex];
    if (item.videoDownloadUrl != null && item.videoDownloadUrl!.isNotEmpty) {
      final uri = Uri.parse(item.videoDownloadUrl!);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mengunduh video MP4 tanpa watermark...')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Menyiapkan tautan video...')),
        );
      }
      _checkDownloadLink();
    }
  }

  void copyLink() {
    final item = widget.items[currentIndex];
    Clipboard.setData(ClipboardData(text: item.link.isNotEmpty ? item.link : 'https://www.tiktok.com/@/video/${item.id}'));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tautan berhasil disalin'), duration: Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.items[currentIndex];

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 35, sigmaY: 35),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.90,
        decoration: BoxDecoration(
          color: const Color(0xE61C1C1E), // Apple Dark Action Sheet Material
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          border: Border.all(color: Colors.white.withOpacity(0.08), width: 0.5),
        ),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          children: [
            // iOS Grabber Bar
            Center(
              child: Container(
                width: 36, height: 5,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
            ),

            // Top Bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'ID: ${item.id}',
                  style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11, fontFamily: 'monospace'),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.12),
                    ),
                    child: const Icon(Icons.close, size: 16, color: Colors.white),
                  ),
                )
              ],
            ),

            // Konten Tengah
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (item.coverUrl != null && item.coverUrl!.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: CachedNetworkImage(imageUrl: item.coverUrl!, height: 290, fit: BoxFit.cover),
                        ),
                      const SizedBox(height: 12),
                      Text(
                        item.author != null ? '@${item.author}' : 'TikTok Video',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          item.title ?? item.content,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.7), height: 1.3),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // 1. iOS Primary Blue Action Button
                      _buildIosButton(
                        onTap: watchInApp,
                        color: const Color(0xFF007AFF),
                        icon: Icons.play_arrow_rounded,
                        label: 'Putar di Aplikasi',
                      ),
                      const SizedBox(height: 8),

                      // 2. TikTok Accent Button
                      _buildIosButton(
                        onTap: openTikTokApp,
                        color: const Color(0xFFFE2C55),
                        icon: Icons.open_in_new_rounded,
                        label: 'Buka di TikTok',
                      ),
                      const SizedBox(height: 8),

                      // 3. Apple Sub-Action Button (Download MP4)
                      _buildIosButton(
                        onTap: downloadVideo,
                        color: Colors.white.withOpacity(0.1),
                        icon: Icons.arrow_downward_rounded,
                        label: 'Unduh Video MP4',
                        textColor: Colors.white,
                      ),

                      const SizedBox(height: 6),
                      TextButton(
                        onPressed: copyLink,
                        child: Text('Salin Tautan', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
                      )
                    ],
                  ),
                ),
              ),
            ),

            // Bottom Navigation Segment
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Colors.white),
                  onPressed: currentIndex > 0 ? () {
                    setState(() => currentIndex--);
                    _checkDownloadLink();
                  } : null,
                ),
                Text(
                  '${currentIndex + 1} dari ${widget.items.length}',
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward_ios_rounded, size: 18, color: Colors.white),
                  onPressed: currentIndex < widget.items.length - 1 ? () {
                    setState(() => currentIndex++);
                    _checkDownloadLink();
                  } : null,
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildIosButton({
    required VoidCallback onTap,
    required Color color,
    required IconData icon,
    required String label,
    Color textColor = Colors.white,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: textColor),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: textColor)),
          ],
        ),
      ),
    );
  }
}
