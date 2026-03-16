import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/network/api_service.dart';
import '../../../../core/widgets/search_filter_bar.dart';

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  List<dynamic> _books = [];
  List<dynamic> _filteredBooks = [];
  List<dynamic> _categories = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _loadBooks();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final response = await ApiService().get('/api/library/categories/', useCache: false);
      setState(() {
        _categories = response.data is List ? response.data : (response.data['results'] ?? []);
      });
    } catch (_) {
      setState(() => _categories = []);
    }
  }

  Future<void> _loadBooks() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiService().get('/api/library/books/');
      setState(() {
        _books = response.data is List<dynamic>
            ? response.data
            : (response.data['results'] ?? []);
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredBooks = _books.where((book) {
        // Recherche
        if (_searchQuery.isNotEmpty) {
          final title = (book['title'] ?? '').toString().toLowerCase();
          final author = (book['author'] ?? '').toString().toLowerCase();
          if (!title.contains(_searchQuery.toLowerCase()) &&
              !author.contains(_searchQuery.toLowerCase())) {
            return false;
          }
        }
        // Filtre catégorie
        if (_selectedCategory != null) {
          if (book['category']?['id']?.toString() != _selectedCategory) {
            return false;
          }
        }
        return true;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bibliothèque'),
      ),
      body: Column(
        children: [
          SearchFilterBar(
            hintText: 'Rechercher un livre...',
            onSearchChanged: (value) {
              setState(() => _searchQuery = value);
              _applyFilters();
            },
            filters: [
              FilterOption(
                key: 'category',
                label: 'Catégorie',
                values: [
                  FilterValue(value: 'all', label: 'Toutes'),
                  ..._categories.map((c) => FilterValue(
                        value: (c['id'] ?? c['name']).toString(),
                        label: c['name'] ?? 'Catégorie',
                      )),
                ],
                selectedValue: _selectedCategory,
              ),
            ],
            onFiltersChanged: (filters) {
              setState(() {
                _selectedCategory = filters['category'] == 'all' ? null : filters['category'];
              });
              _applyFilters();
            },
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredBooks.isEmpty
                    ? const Center(child: Text('Aucun livre disponible'))
                    : RefreshIndicator(
                        onRefresh: _loadBooks,
                        child: GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                            childAspectRatio: 0.7,
                          ),
                          itemCount: _filteredBooks.length,
                          itemBuilder: (context, index) {
                            final book = _filteredBooks[index];
                      return Card(
                        child: InkWell(
                          onTap: () {
                            context.push('/library/${book['id']}');
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: book['cover_url'] != null
                                    ? CachedNetworkImage(
                                        imageUrl: book['cover_url'],
                                        fit: BoxFit.cover,
                                        placeholder: (context, url) => const Center(
                                          child: CircularProgressIndicator(),
                                        ),
                                        errorWidget: (context, url, error) => const Icon(
                                          Icons.book,
                                          size: 48,
                                        ),
                                      )
                                    : const Icon(Icons.book, size: 48),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      book['title'] ?? 'Sans titre',
                                      style: Theme.of(context).textTheme.titleSmall,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (book['author'] != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        book['author'],
                                        style: Theme.of(context).textTheme.bodySmall,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                            },
                          ),
                        ),
                      ),
        ],
      ),
    );
  }
}
