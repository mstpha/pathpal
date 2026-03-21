import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pathap/features/business/data/business_list_provider.dart';
import 'package:pathap/features/business/domain/business_model.dart';
import 'package:pathap/features/business/presentation/user_business_profile_screen.dart';
import 'package:pathap/shared/theme/app_colors.dart';
import 'package:pathap/shared/theme/theme_provider.dart';

class BrowseBusinessesScreen extends ConsumerStatefulWidget {
  const BrowseBusinessesScreen({Key? key}) : super(key: key);

  @override
  _BrowseBusinessesScreenState createState() => _BrowseBusinessesScreenState();
}

class _BrowseBusinessesScreenState
    extends ConsumerState<BrowseBusinessesScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    // Fetch all businesses when screen loads
    Future.microtask(() {
      ref.read(businessListProvider.notifier).fetchAllBusinesses();
    });

    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  DateTime _lastSearchTime = DateTime.now();
  void _onSearchChanged() {
    final now = DateTime.now();
    if (now.difference(_lastSearchTime) > const Duration(milliseconds: 300)) {
      _lastSearchTime = now;
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    }
  }

  void _navigateToBusinessProfile(BusinessModel business) {
    // Navigate to map with business location
    context.push('/map', extra: {
      'businessId': business.id,
      'latitude': business.latitude,
      'longitude': business.longitude,
    });
  }

  List<String> _extractCategories(List<BusinessModel> businesses) {
    final categories = businesses
        .where((b) => b.category != null)
        .map((b) => b.category!)
        .toSet()
        .toList();
    categories.sort();
    return categories;
  }

  List<BusinessModel> _filterBusinesses(List<BusinessModel> businesses) {
    var filtered = businesses;

    // Filter by category if selected
    if (_selectedCategory != null) {
      filtered = filtered
          .where((business) => business.category == _selectedCategory)
          .toList();
    }

    // Filter by search query
    if (_searchQuery.isEmpty) {
      return filtered;
    }

    return filtered.where((business) {
      final businessName = business.businessName.toLowerCase();
      final email = business.email.toLowerCase();
      final category = business.category?.toLowerCase() ?? '';

      return businessName.contains(_searchQuery) ||
          email.contains(_searchQuery) ||
          category.contains(_searchQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final businessesState = ref.watch(businessListProvider);
    final isDarkMode = ref.watch(themeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Browse Businesses',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: isDarkMode ? Colors.grey[900] : AppColors.primaryColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () {
              ref.read(businessListProvider.notifier).fetchAllBusinesses();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.grey[900] : AppColors.primaryColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Container(
              decoration: BoxDecoration(
                color: isDarkMode ? Colors.grey[800] : Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: TextField(
                controller: _searchController,
                style: TextStyle(
                  color: isDarkMode ? Colors.white : Colors.black,
                ),
                decoration: InputDecoration(
                  hintText: 'Search by name, email, or category...',
                  hintStyle: TextStyle(
                    color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    color:
                        isDarkMode ? Colors.grey[400] : AppColors.primaryColor,
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.clear,
                            color: isDarkMode ? Colors.grey[400] : Colors.grey,
                          ),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                            });
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ),
          ),

          // Category filter
          businessesState.maybeWhen(
            data: (businesses) {
              final categories = _extractCategories(businesses);
              if (categories.isEmpty) return const SizedBox.shrink();

              return Container(
                height: 50,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: isDarkMode ? Colors.grey[850] : Colors.grey[100],
                  border: Border(
                    bottom: BorderSide(
                      color: isDarkMode ? Colors.grey[800]! : Colors.grey[300]!,
                      width: 1,
                    ),
                  ),
                ),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    // "All" chip
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: const Text('All'),
                        selected: _selectedCategory == null,
                        onSelected: (selected) {
                          setState(() {
                            _selectedCategory = null;
                          });
                        },
                        selectedColor: AppColors.primaryColor.withOpacity(0.2),
                        checkmarkColor: AppColors.primaryColor,
                        labelStyle: TextStyle(
                          color: _selectedCategory == null
                              ? AppColors.primaryColor
                              : (isDarkMode
                                  ? Colors.grey[400]
                                  : Colors.grey[700]),
                          fontWeight: _selectedCategory == null
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                    // Category chips
                    ...categories.map((category) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(category),
                            selected: _selectedCategory == category,
                            onSelected: (selected) {
                              setState(() {
                                _selectedCategory = selected ? category : null;
                              });
                            },
                            selectedColor:
                                AppColors.primaryColor.withOpacity(0.2),
                            checkmarkColor: AppColors.primaryColor,
                            labelStyle: TextStyle(
                              color: _selectedCategory == category
                                  ? AppColors.primaryColor
                                  : (isDarkMode
                                      ? Colors.grey[400]
                                      : Colors.grey[700]),
                              fontWeight: _selectedCategory == category
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        )),
                  ],
                ),
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),

          // Business list
          Expanded(
            child: businessesState.when(
              data: (businesses) {
                final filteredBusinesses = _filterBusinesses(businesses);

                if (filteredBusinesses.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.business_center,
                          size: 80,
                          color:
                              isDarkMode ? Colors.grey[600] : Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isEmpty && _selectedCategory == null
                              ? 'No businesses found'
                              : 'No businesses match your filters',
                          style: TextStyle(
                            fontSize: 18,
                            color: isDarkMode
                                ? Colors.grey[400]
                                : Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (_searchQuery.isNotEmpty ||
                            _selectedCategory != null) ...[
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                                _selectedCategory = null;
                              });
                            },
                            child: const Text('Clear filters'),
                          ),
                        ],
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    await ref
                        .read(businessListProvider.notifier)
                        .fetchAllBusinesses();
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredBusinesses.length,
                    itemBuilder: (context, index) {
                      final business = filteredBusinesses[index];
                      return _buildBusinessCard(business, isDarkMode);
                    },
                  ),
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(
                  valueColor:
                      AlwaysStoppedAnimation<Color>(AppColors.primaryColor),
                ),
              ),
              error: (error, stackTrace) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 80,
                      color: Colors.red[300],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Error loading businesses',
                      style: TextStyle(
                        fontSize: 18,
                        color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        error.toString(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color:
                              isDarkMode ? Colors.grey[500] : Colors.grey[500],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        ref
                            .read(businessListProvider.notifier)
                            .fetchAllBusinesses();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryColor,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBusinessCard(BusinessModel business, bool isDarkMode) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: isDarkMode ? Colors.grey[800] : Colors.white,
      child: InkWell(
        onTap: () => _navigateToBusinessProfile(business),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Business image
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: business.imageUrl != null
                    ? Image.network(
                        business.imageUrl!,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _buildPlaceholderImage(isDarkMode),
                      )
                    : _buildPlaceholderImage(isDarkMode),
              ),
              const SizedBox(width: 16),

              // Business details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Business name with verified badge
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            business.businessName,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: isDarkMode
                                  ? Colors.white
                                  : AppColors.primaryColor,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (business.isVerified)
                          const Icon(
                            Icons.verified,
                            size: 20,
                            color: AppColors.primaryColor,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Category
                    if (business.category != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          business.category!,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.primaryColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],

                    // Email
                    Row(
                      children: [
                        Icon(
                          Icons.email,
                          size: 16,
                          color:
                              isDarkMode ? Colors.grey[400] : Colors.grey[600],
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            business.email,
                            style: TextStyle(
                              fontSize: 14,
                              color: isDarkMode
                                  ? Colors.grey[300]
                                  : Colors.grey[700],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Location
                    Row(
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 16,
                          color:
                              isDarkMode ? Colors.grey[400] : Colors.grey[600],
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${business.latitude.toStringAsFixed(4)}, ${business.longitude.toStringAsFixed(4)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDarkMode
                                ? Colors.grey[400]
                                : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Arrow icon
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: isDarkMode ? Colors.grey[400] : Colors.grey[500],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholderImage(bool isDarkMode) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[700] : Colors.grey[300],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.business,
        color: isDarkMode ? Colors.grey[500] : Colors.grey[600],
        size: 40,
      ),
    );
  }
}
