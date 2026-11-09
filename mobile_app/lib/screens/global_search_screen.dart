import 'dart:async';

import 'package:flutter/material.dart';

import '../data/local_database.dart';
import '../theme/app_theme.dart';

class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Map<String, Object?>> _results = [];
  bool _loading = false;
  String? _error;
  String _filter = 'सभी';

  static const _filters = ['सभी', 'मुकदमा', 'डाक', 'रिमांड', 'संपर्क', 'दस्तावेज'];

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < 2) {
      setState(() {
        _results = [];
        _loading = false;
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), _search);
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.length < 2) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await LocalDatabase.instance.globalSearch(query);
      if (!mounted || query != _controller.text.trim()) return;
      setState(() {
        _results = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'खोज पूरी नहीं हो सकी: $e';
      });
    }
  }

  List<Map<String, Object?>> get _visibleResults => _filter == 'सभी'
      ? _results
      : _results.where((row) => row['record_type'] == _filter).toList();

  IconData _icon(String type) {
    switch (type) {
      case 'मुकदमा':
        return Icons.gavel_rounded;
      case 'डाक':
        return Icons.mark_email_unread_rounded;
      case 'रिमांड':
        return Icons.assignment_turned_in_rounded;
      case 'संपर्क':
        return Icons.contact_phone_rounded;
      default:
        return Icons.description_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleResults;
    return Scaffold(
      appBar: AppBar(
        title: const Text('सभी रिकॉर्ड में खोज'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              onSubmitted: (_) {
                _debounce?.cancel();
                _search();
              },
              decoration: InputDecoration(
                hintText: 'नाम, FIR, ST No., धारा, मोबाइल...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'खोज साफ करें',
                        onPressed: () {
                          _controller.clear();
                          _onChanged('');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 46,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: _filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final item = _filters[index];
                return ChoiceChip(
                  label: Text(item),
                  selected: _filter == item,
                  onSelected: (_) => setState(() => _filter = item),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_error!, textAlign: TextAlign.center),
                        ),
                      )
                    : _controller.text.trim().length < 2
                        ? _emptyState(
                            Icons.manage_search_rounded,
                            'खोज शुरू करें',
                            'कम से कम 2 अक्षर लिखें। खोज मुकदमे, डाक, रिमांड, संपर्क और दस्तावेजों में होगी।',
                          )
                        : visible.isEmpty
                            ? _emptyState(
                                Icons.search_off_rounded,
                                'कोई रिकॉर्ड नहीं मिला',
                                'दूसरा नाम, FIR नंबर, ST नंबर या मोबाइल नंबर आजमाएँ।',
                              )
                            : Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
                                    child: Row(
                                      children: [
                                        Text(
                                          '${visible.length} परिणाम',
                                          style: Theme.of(context).textTheme.labelLarge,
                                        ),
                                        const Spacer(),
                                        const Text(
                                          'अधिकतम 200 रिकॉर्ड',
                                          style: TextStyle(
                                            color: AppTheme.muted,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: ListView.separated(
                                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                                      itemCount: visible.length,
                                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                                      itemBuilder: (context, index) {
                                        final row = visible[index];
                                        final type = row['record_type']?.toString() ?? '';
                                        final title = row['title']?.toString() ?? 'रिकॉर्ड';
                                        final subtitle = row['subtitle']?.toString() ?? '';
                                        final detail = row['detail']?.toString() ?? '';
                                        return Card(
                                          child: ListTile(
                                            contentPadding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 7,
                                            ),
                                            leading: CircleAvatar(
                                              backgroundColor: AppTheme.blue.withValues(alpha: .09),
                                              child: Icon(_icon(type), color: AppTheme.blue, size: 20),
                                            ),
                                            title: Text(
                                              title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontWeight: FontWeight.w700),
                                            ),
                                            subtitle: Padding(
                                              padding: const EdgeInsets.only(top: 4),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                                                  if (detail.trim().isNotEmpty) ...[
                                                    const SizedBox(height: 3),
                                                    Text(
                                                      detail,
                                                      maxLines: 2,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: Theme.of(context).textTheme.bodySmall,
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            trailing: Text(
                                              type,
                                              style: const TextStyle(
                                                color: AppTheme.teal,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(IconData icon, String title, String message) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 44, color: AppTheme.muted.withValues(alpha: .65)),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
}
