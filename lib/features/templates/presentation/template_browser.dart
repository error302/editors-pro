import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/template_provider.dart';

/// Template category filter options
enum TemplateCategoryFilter {
  all('All', Icons.apps),
  social('Social', Icons.share),
  cinematic('Cinematic', Icons.movie),
  tutorial('Tutorial', Icons.school),
  vlog('Vlog', Icons.videocam),
  business('Business', Icons.business),
  celebration('Celebration', Icons.celebration);

  const TemplateCategoryFilter(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Hardcoded built-in templates (mirrors Rust engine templates)
const _builtInTemplates = [
  TemplateData(
    id: 'tmpl-social-intro',
    name: 'Social Intro',
    description:
        'Eye-catching vertical intro for Instagram Reels and TikTok with animated title and transitions',
    category: 'Social',
    previewPath: 'assets/templates/social_intro.png',
    placeholderCount: 4,
    durationMs: 15000,
    aspectRatio: '9:16',
    tags: ['social', 'tiktok', 'instagram', 'intro', 'vertical'],
  ),
  TemplateData(
    id: 'tmpl-cinematic-widescreen',
    name: 'Cinematic Widescreen',
    description:
        'Dramatic widescreen opener with cinematic transitions, title cards, and slow reveals',
    category: 'Cinematic',
    previewPath: 'assets/templates/cinematic_widescreen.png',
    placeholderCount: 6,
    durationMs: 30000,
    aspectRatio: '16:9',
    tags: ['cinematic', 'widescreen', 'film', 'dramatic', 'opener'],
  ),
  TemplateData(
    id: 'tmpl-tutorial-steps',
    name: 'Tutorial Steps',
    description:
        'Step-by-step tutorial with 5 numbered sections, each with screen recording and title overlay',
    category: 'Tutorial',
    previewPath: 'assets/templates/tutorial_steps.png',
    placeholderCount: 10,
    durationMs: 60000,
    aspectRatio: '16:9',
    tags: ['tutorial', 'steps', 'education', 'how-to', 'instructional'],
  ),
  TemplateData(
    id: 'tmpl-vlog-highlight',
    name: 'Vlog Highlight',
    description:
        'Quick vertical vlog highlight reel with snappy cuts and energetic pacing',
    category: 'Vlog',
    previewPath: 'assets/templates/vlog_highlight.png',
    placeholderCount: 4,
    durationMs: 20000,
    aspectRatio: '9:16',
    tags: ['vlog', 'highlight', 'vertical', 'tiktok', 'instagram'],
  ),
  TemplateData(
    id: 'tmpl-business-presentation',
    name: 'Business Presentation',
    description:
        'Professional corporate presentation with video sections and lower-third text callouts',
    category: 'Business',
    previewPath: 'assets/templates/business_presentation.png',
    placeholderCount: 7,
    durationMs: 45000,
    aspectRatio: '16:9',
    tags: ['business', 'presentation', 'corporate', 'professional', 'pitch'],
  ),
  TemplateData(
    id: 'tmpl-celebration-card',
    name: 'Celebration Card',
    description:
        'Festive square video card with photo/video slots, confetti effects, and greeting text overlays',
    category: 'Celebration',
    previewPath: 'assets/templates/celebration_card.png',
    placeholderCount: 4,
    durationMs: 10000,
    aspectRatio: '1:1',
    tags: ['celebration', 'card', 'birthday', 'instagram', 'square'],
  ),
  TemplateData(
    id: 'tmpl-instagram-reel',
    name: 'Instagram Reel',
    description:
        'Instagram Reel template with trendy cuts, text caption overlay, and music-sync transitions',
    category: 'Social',
    previewPath: 'assets/templates/instagram_reel.png',
    placeholderCount: 4,
    durationMs: 15000,
    aspectRatio: '9:16',
    tags: ['instagram', 'reel', 'social', 'vertical', 'trending'],
  ),
  TemplateData(
    id: 'tmpl-product-showcase',
    name: 'Product Showcase',
    description:
        'Clean product showcase with feature highlight labels and professional transitions',
    category: 'Business',
    previewPath: 'assets/templates/product_showcase.png',
    placeholderCount: 6,
    durationMs: 20000,
    aspectRatio: '1:1',
    tags: ['product', 'showcase', 'ecommerce', 'square', 'business'],
  ),
  TemplateData(
    id: 'tmpl-travel-montage',
    name: 'Travel Montage',
    description:
        'Fast-paced travel montage with speed-ramp transitions and location title card',
    category: 'Cinematic',
    previewPath: 'assets/templates/travel_montage.png',
    placeholderCount: 6,
    durationMs: 30000,
    aspectRatio: '16:9',
    tags: ['travel', 'montage', 'speed-ramp', 'adventure', 'cinematic'],
  ),
  TemplateData(
    id: 'tmpl-quick-tutorial',
    name: 'Quick Tutorial',
    description:
        'Short-form tutorial with 3 demo clips and step-by-step text labels, perfect for quick how-tos',
    category: 'Tutorial',
    previewPath: 'assets/templates/quick_tutorial.png',
    placeholderCount: 6,
    durationMs: 30000,
    aspectRatio: '16:9',
    tags: ['tutorial', 'quick', 'how-to', 'education', 'demo'],
  ),
];

/// Placeholder slot definitions for each built-in template
const _templateSlots = <String, List<PlaceholderSlotData>>{
  'tmpl-social-intro': [
    PlaceholderSlotData(
      id: 'slot-social-intro-video-1',
      label: 'Opening hook clip',
      mediaType: 'video',
      startMs: 0,
      expectedDurationMs: 5000,
    ),
    PlaceholderSlotData(
      id: 'slot-social-intro-video-2',
      label: 'Main content clip',
      mediaType: 'video',
      startMs: 5000,
      expectedDurationMs: 5000,
    ),
    PlaceholderSlotData(
      id: 'slot-social-intro-video-3',
      label: 'Closing clip',
      mediaType: 'video',
      startMs: 10000,
      expectedDurationMs: 5000,
    ),
    PlaceholderSlotData(
      id: 'slot-social-intro-text-1',
      label: 'Title text overlay',
      mediaType: 'image',
      startMs: 0,
      expectedDurationMs: 4000,
    ),
  ],
  'tmpl-cinematic-widescreen': [
    PlaceholderSlotData(
      id: 'slot-cinematic-video-1',
      label: 'Opening wide shot',
      mediaType: 'video',
      startMs: 0,
      expectedDurationMs: 8000,
    ),
    PlaceholderSlotData(
      id: 'slot-cinematic-video-2',
      label: 'Reveal shot',
      mediaType: 'video',
      startMs: 8000,
      expectedDurationMs: 7000,
    ),
    PlaceholderSlotData(
      id: 'slot-cinematic-video-3',
      label: 'Action sequence',
      mediaType: 'video',
      startMs: 15000,
      expectedDurationMs: 8000,
    ),
    PlaceholderSlotData(
      id: 'slot-cinematic-video-4',
      label: 'Final establishing shot',
      mediaType: 'video',
      startMs: 23000,
      expectedDurationMs: 7000,
    ),
    PlaceholderSlotData(
      id: 'slot-cinematic-text-1',
      label: 'Opening title card',
      mediaType: 'image',
      startMs: 0,
      expectedDurationMs: 5000,
    ),
    PlaceholderSlotData(
      id: 'slot-cinematic-text-2',
      label: 'Closing title card',
      mediaType: 'image',
      startMs: 25000,
      expectedDurationMs: 5000,
    ),
  ],
  'tmpl-tutorial-steps': [
    PlaceholderSlotData(
      id: 'slot-tutorial-video-1',
      label: 'Step 1 recording',
      mediaType: 'video',
      startMs: 0,
      expectedDurationMs: 12000,
    ),
    PlaceholderSlotData(
      id: 'slot-tutorial-text-1',
      label: 'Step 1 title',
      mediaType: 'image',
      startMs: 0,
      expectedDurationMs: 4000,
    ),
    PlaceholderSlotData(
      id: 'slot-tutorial-video-2',
      label: 'Step 2 recording',
      mediaType: 'video',
      startMs: 12000,
      expectedDurationMs: 12000,
    ),
    PlaceholderSlotData(
      id: 'slot-tutorial-text-2',
      label: 'Step 2 title',
      mediaType: 'image',
      startMs: 12000,
      expectedDurationMs: 4000,
    ),
    PlaceholderSlotData(
      id: 'slot-tutorial-video-3',
      label: 'Step 3 recording',
      mediaType: 'video',
      startMs: 24000,
      expectedDurationMs: 12000,
    ),
    PlaceholderSlotData(
      id: 'slot-tutorial-text-3',
      label: 'Step 3 title',
      mediaType: 'image',
      startMs: 24000,
      expectedDurationMs: 4000,
    ),
    PlaceholderSlotData(
      id: 'slot-tutorial-video-4',
      label: 'Step 4 recording',
      mediaType: 'video',
      startMs: 36000,
      expectedDurationMs: 12000,
    ),
    PlaceholderSlotData(
      id: 'slot-tutorial-text-4',
      label: 'Step 4 title',
      mediaType: 'image',
      startMs: 36000,
      expectedDurationMs: 4000,
    ),
    PlaceholderSlotData(
      id: 'slot-tutorial-video-5',
      label: 'Step 5 recording',
      mediaType: 'video',
      startMs: 48000,
      expectedDurationMs: 12000,
    ),
    PlaceholderSlotData(
      id: 'slot-tutorial-text-5',
      label: 'Step 5 title',
      mediaType: 'image',
      startMs: 48000,
      expectedDurationMs: 4000,
    ),
  ],
  'tmpl-vlog-highlight': [
    PlaceholderSlotData(
      id: 'slot-vlog-video-1',
      label: 'Highlight clip 1',
      mediaType: 'video',
      startMs: 0,
      expectedDurationMs: 5000,
    ),
    PlaceholderSlotData(
      id: 'slot-vlog-video-2',
      label: 'Highlight clip 2',
      mediaType: 'video',
      startMs: 5000,
      expectedDurationMs: 5000,
    ),
    PlaceholderSlotData(
      id: 'slot-vlog-video-3',
      label: 'Highlight clip 3',
      mediaType: 'video',
      startMs: 10000,
      expectedDurationMs: 5000,
    ),
    PlaceholderSlotData(
      id: 'slot-vlog-video-4',
      label: 'Highlight clip 4',
      mediaType: 'video',
      startMs: 15000,
      expectedDurationMs: 5000,
    ),
  ],
  'tmpl-business-presentation': [
    PlaceholderSlotData(
      id: 'slot-biz-video-1',
      label: 'Introduction clip',
      mediaType: 'video',
      startMs: 0,
      expectedDurationMs: 15000,
    ),
    PlaceholderSlotData(
      id: 'slot-biz-video-2',
      label: 'Main content clip',
      mediaType: 'video',
      startMs: 15000,
      expectedDurationMs: 15000,
    ),
    PlaceholderSlotData(
      id: 'slot-biz-video-3',
      label: 'Conclusion clip',
      mediaType: 'video',
      startMs: 30000,
      expectedDurationMs: 15000,
    ),
    PlaceholderSlotData(
      id: 'slot-biz-text-1',
      label: 'Speaker name title',
      mediaType: 'image',
      startMs: 0,
      expectedDurationMs: 5000,
    ),
    PlaceholderSlotData(
      id: 'slot-biz-text-2',
      label: 'Key point 1 callout',
      mediaType: 'image',
      startMs: 15000,
      expectedDurationMs: 5000,
    ),
    PlaceholderSlotData(
      id: 'slot-biz-text-3',
      label: 'Key point 2 callout',
      mediaType: 'image',
      startMs: 22000,
      expectedDurationMs: 5000,
    ),
    PlaceholderSlotData(
      id: 'slot-biz-text-4',
      label: 'Closing title card',
      mediaType: 'image',
      startMs: 38000,
      expectedDurationMs: 7000,
    ),
  ],
  'tmpl-celebration-card': [
    PlaceholderSlotData(
      id: 'slot-celebration-video-1',
      label: 'Celebration moment 1',
      mediaType: 'video',
      startMs: 0,
      expectedDurationMs: 5000,
    ),
    PlaceholderSlotData(
      id: 'slot-celebration-video-2',
      label: 'Celebration moment 2',
      mediaType: 'video',
      startMs: 5000,
      expectedDurationMs: 5000,
    ),
    PlaceholderSlotData(
      id: 'slot-celebration-text-1',
      label: 'Greeting headline',
      mediaType: 'image',
      startMs: 0,
      expectedDurationMs: 5000,
    ),
    PlaceholderSlotData(
      id: 'slot-celebration-text-2',
      label: 'Personal message',
      mediaType: 'image',
      startMs: 5000,
      expectedDurationMs: 5000,
    ),
  ],
  'tmpl-instagram-reel': [
    PlaceholderSlotData(
      id: 'slot-reel-video-1',
      label: 'Hook clip',
      mediaType: 'video',
      startMs: 0,
      expectedDurationMs: 5000,
    ),
    PlaceholderSlotData(
      id: 'slot-reel-video-2',
      label: 'Main content clip',
      mediaType: 'video',
      startMs: 5000,
      expectedDurationMs: 5000,
    ),
    PlaceholderSlotData(
      id: 'slot-reel-video-3',
      label: 'Outro clip',
      mediaType: 'video',
      startMs: 10000,
      expectedDurationMs: 5000,
    ),
    PlaceholderSlotData(
      id: 'slot-reel-text-1',
      label: 'Caption overlay',
      mediaType: 'image',
      startMs: 0,
      expectedDurationMs: 6000,
    ),
  ],
  'tmpl-product-showcase': [
    PlaceholderSlotData(
      id: 'slot-product-video-1',
      label: 'Hero product shot',
      mediaType: 'video',
      startMs: 0,
      expectedDurationMs: 7000,
    ),
    PlaceholderSlotData(
      id: 'slot-product-video-2',
      label: 'Product detail closeup',
      mediaType: 'video',
      startMs: 7000,
      expectedDurationMs: 7000,
    ),
    PlaceholderSlotData(
      id: 'slot-product-video-3',
      label: 'Lifestyle / in-use shot',
      mediaType: 'video',
      startMs: 14000,
      expectedDurationMs: 6000,
    ),
    PlaceholderSlotData(
      id: 'slot-product-text-1',
      label: 'Product name label',
      mediaType: 'image',
      startMs: 0,
      expectedDurationMs: 5000,
    ),
    PlaceholderSlotData(
      id: 'slot-product-text-2',
      label: 'Feature highlight 1',
      mediaType: 'image',
      startMs: 7000,
      expectedDurationMs: 5000,
    ),
    PlaceholderSlotData(
      id: 'slot-product-text-3',
      label: 'Price / CTA label',
      mediaType: 'image',
      startMs: 14000,
      expectedDurationMs: 5000,
    ),
  ],
  'tmpl-travel-montage': [
    PlaceholderSlotData(
      id: 'slot-travel-video-1',
      label: 'Travel clip 1',
      mediaType: 'video',
      startMs: 0,
      expectedDurationMs: 6000,
    ),
    PlaceholderSlotData(
      id: 'slot-travel-video-2',
      label: 'Travel clip 2',
      mediaType: 'video',
      startMs: 6000,
      expectedDurationMs: 6000,
    ),
    PlaceholderSlotData(
      id: 'slot-travel-video-3',
      label: 'Travel clip 3',
      mediaType: 'video',
      startMs: 12000,
      expectedDurationMs: 6000,
    ),
    PlaceholderSlotData(
      id: 'slot-travel-video-4',
      label: 'Travel clip 4',
      mediaType: 'video',
      startMs: 18000,
      expectedDurationMs: 6000,
    ),
    PlaceholderSlotData(
      id: 'slot-travel-video-5',
      label: 'Travel clip 5',
      mediaType: 'video',
      startMs: 24000,
      expectedDurationMs: 6000,
    ),
    PlaceholderSlotData(
      id: 'slot-travel-text-1',
      label: 'Destination title card',
      mediaType: 'image',
      startMs: 0,
      expectedDurationMs: 6000,
    ),
  ],
  'tmpl-quick-tutorial': [
    PlaceholderSlotData(
      id: 'slot-qt-video-1',
      label: 'Step 1 demo clip',
      mediaType: 'video',
      startMs: 0,
      expectedDurationMs: 10000,
    ),
    PlaceholderSlotData(
      id: 'slot-qt-video-2',
      label: 'Step 2 demo clip',
      mediaType: 'video',
      startMs: 10000,
      expectedDurationMs: 10000,
    ),
    PlaceholderSlotData(
      id: 'slot-qt-video-3',
      label: 'Step 3 demo clip',
      mediaType: 'video',
      startMs: 20000,
      expectedDurationMs: 10000,
    ),
    PlaceholderSlotData(
      id: 'slot-qt-text-1',
      label: 'Step 1 label',
      mediaType: 'image',
      startMs: 0,
      expectedDurationMs: 5000,
    ),
    PlaceholderSlotData(
      id: 'slot-qt-text-2',
      label: 'Step 2 label',
      mediaType: 'image',
      startMs: 10000,
      expectedDurationMs: 5000,
    ),
    PlaceholderSlotData(
      id: 'slot-qt-text-3',
      label: 'Step 3 label',
      mediaType: 'image',
      startMs: 20000,
      expectedDurationMs: 5000,
    ),
  ],
};

/// Template browser screen — browse and select pre-built templates
class TemplateBrowserScreen extends ConsumerStatefulWidget {
  const TemplateBrowserScreen({super.key});

  @override
  ConsumerState<TemplateBrowserScreen> createState() =>
      _TemplateBrowserScreenState();
}

class _TemplateBrowserScreenState extends ConsumerState<TemplateBrowserScreen> {
  TemplateCategoryFilter _selectedCategory = TemplateCategoryFilter.all;
  String _searchQuery = '';

  List<TemplateData> get _filteredTemplates {
    var templates = _builtInTemplates;

    // Filter by category
    if (_selectedCategory != TemplateCategoryFilter.all) {
      final categoryName = _selectedCategory.label;
      templates = templates.where((t) => t.category == categoryName).toList();
    }

    // Filter by search query (matches name, description, or tags)
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      templates = templates
          .where(
            (t) =>
                t.name.toLowerCase().contains(query) ||
                t.description.toLowerCase().contains(query) ||
                t.tags.any((tag) => tag.contains(query)),
          )
          .toList();
    }

    return templates;
  }

  @override
  Widget build(BuildContext context) {
    final templates = _filteredTemplates;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Templates'),
        backgroundColor: AppTheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          // Search bar
          _buildSearchBar(),
          const SizedBox(height: AppTheme.spacing8),

          // Category filter chips
          _buildCategoryChips(),
          const SizedBox(height: AppTheme.spacing16),

          // Template grid
          Expanded(
            child: templates.isEmpty
                ? _buildEmptyState()
                : _buildTemplateGrid(templates),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing16,
        vertical: AppTheme.spacing8,
      ),
      child: TextField(
        onChanged: (value) => setState(() => _searchQuery = value),
        style: context.textTheme.bodyMedium,
        decoration: InputDecoration(
          hintText: 'Search templates...',
          hintStyle: const TextStyle(color: AppTheme.textDisabled),
          prefixIcon:
              const Icon(Icons.search, size: 20, color: AppTheme.textSecondary),
          filled: true,
          fillColor: AppTheme.surfaceVariant,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacing16,
            vertical: AppTheme.spacing12,
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryChips() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing16),
        itemCount: TemplateCategoryFilter.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = TemplateCategoryFilter.values[index];
          final isSelected = category == _selectedCategory;
          return _CategoryChip(
            category: category,
            isSelected: isSelected,
            onTap: () => setState(() => _selectedCategory = category),
          );
        },
      ),
    );
  }

  Widget _buildTemplateGrid(List<TemplateData> templates) {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing16,
        vertical: AppTheme.spacing8,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: AppTheme.spacing12,
        mainAxisSpacing: AppTheme.spacing12,
        childAspectRatio: 0.68,
      ),
      itemCount: templates.length,
      itemBuilder: (context, index) {
        return _TemplateCard(
          template: templates[index],
          onTap: () => _showTemplateDetails(templates[index]),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off,
            size: 64,
            color: AppTheme.textDisabled.withValues(alpha: 0.5),
          ),
          const SizedBox(height: AppTheme.spacing16),
          Text(
            'No templates found',
            style: context.textTheme.titleMedium?.copyWith(
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: AppTheme.spacing8),
          Text(
            'Try a different search or category',
            style: context.textTheme.bodySmall?.copyWith(
              color: AppTheme.textDisabled,
            ),
          ),
        ],
      ),
    );
  }

  void _showTemplateDetails(TemplateData template) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusXLarge),
        ),
      ),
      builder: (context) => _TemplateDetailSheet(template: template),
    );
  }
}

/// Category filter chip
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.isSelected,
    required this.onTap,
  });
  final TemplateCategoryFilter category;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacing12,
          vertical: AppTheme.spacing8,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary.withValues(alpha: 0.2)
              : AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          border: Border.all(
            color: isSelected ? AppTheme.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              category.icon,
              size: 16,
              color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              category.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Template card widget for the grid
class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.onTap,
  });
  final TemplateData template;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.cardColor,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(
            color: AppTheme.textDisabled.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Preview thumbnail area
            Expanded(
              flex: 3,
              child: Container(
                decoration: BoxDecoration(
                  color: _categoryColor().withValues(alpha: 0.15),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppTheme.radiusMedium),
                  ),
                ),
                child: Stack(
                  children: [
                    // Aspect ratio indicator
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _categoryIcon(),
                            size: 32,
                            color: _categoryColor().withValues(alpha: 0.7),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            template.aspectRatio,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _categoryColor().withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Duration badge
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          template.durationFormatted,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),

                    // Placeholder count badge
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.add_photo_alternate_outlined,
                              size: 12,
                              color: Colors.white70,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '${template.placeholderCount}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Template info
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.spacing8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Category badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _categoryColor().withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        template.category,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: _categoryColor(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),

                    // Template name
                    Text(
                      template.name,
                      style: context.textTheme.titleSmall?.copyWith(
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),

                    // Description
                    Text(
                      template.description,
                      style: context.textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _categoryIcon() {
    switch (template.category) {
      case 'Social':
        return Icons.share;
      case 'Cinematic':
        return Icons.movie;
      case 'Tutorial':
        return Icons.school;
      case 'Vlog':
        return Icons.videocam;
      case 'Business':
        return Icons.business;
      case 'Celebration':
        return Icons.celebration;
      default:
        return Icons.video_library;
    }
  }

  Color _categoryColor() {
    switch (template.category) {
      case 'Social':
        return AppTheme.secondary;
      case 'Cinematic':
        return AppTheme.primary;
      case 'Tutorial':
        return AppTheme.info;
      case 'Vlog':
        return AppTheme.success;
      case 'Business':
        return AppTheme.warning;
      case 'Celebration':
        return AppTheme.accent;
      default:
        return AppTheme.primaryLight;
    }
  }
}

/// Template detail bottom sheet with "Create Project" flow
class _TemplateDetailSheet extends ConsumerStatefulWidget {
  const _TemplateDetailSheet({required this.template});
  final TemplateData template;

  @override
  ConsumerState<_TemplateDetailSheet> createState() =>
      _TemplateDetailSheetState();
}

class _TemplateDetailSheetState extends ConsumerState<_TemplateDetailSheet> {
  /// Slot assignments: slotId -> mediaPath
  final Map<String, String> _assignments = {};
  bool _isCreating = false;

  /// Get the placeholder slots for this template
  List<PlaceholderSlotData> get _slots =>
      _templateSlots[widget.template.id] ?? [];

  /// Whether at least one video slot is filled
  bool get _canCreate {
    if (_isCreating) return false;
    // At least one video slot must be filled
    final videoSlots = _slots.where((s) => s.mediaType == 'video');
    return videoSlots.any((s) => _assignments.containsKey(s.id));
  }

  /// Number of filled slots
  int get _filledCount => _assignments.length;

  @override
  Widget build(BuildContext context) {
    final template = widget.template;
    final slots = _slots;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (context, scrollController) {
        return SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(AppTheme.spacing20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.textDisabled.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.spacing20),

              // Template name & category
              Row(
                children: [
                  Expanded(
                    child: Text(
                      template.name,
                      style: context.textTheme.headlineSmall,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      template.category,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spacing8),

              // Description
              Text(
                template.description,
                style: context.textTheme.bodyMedium?.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: AppTheme.spacing16),

              // Stats row
              Row(
                children: [
                  _StatBadge(
                    icon: Icons.timer_outlined,
                    label: template.durationFormatted,
                  ),
                  const SizedBox(width: 12),
                  _StatBadge(
                    icon: Icons.aspect_ratio,
                    label: template.aspectRatio,
                  ),
                  const SizedBox(width: 12),
                  _StatBadge(
                    icon: Icons.add_photo_alternate_outlined,
                    label: '${template.placeholderCount} slots',
                  ),
                ],
              ),

              // Tags row
              if (template.tags.isNotEmpty) ...[
                const SizedBox(height: AppTheme.spacing12),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: template.tags.map((tag) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '#$tag',
                        style: context.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: AppTheme.spacing24),

              // Progress indicator
              if (slots.isNotEmpty) ...[
                Row(
                  children: [
                    Text(
                      'PLACEHOLDER SLOTS',
                      style: context.textTheme.labelMedium?.copyWith(
                        color: AppTheme.textDisabled,
                        letterSpacing: 1,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$_filledCount / ${slots.length}',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: _filledCount == slots.length
                            ? AppTheme.success
                            : AppTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.spacing8),

                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: slots.isEmpty ? 0 : _filledCount / slots.length,
                    backgroundColor: AppTheme.surfaceVariant,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _filledCount == slots.length
                          ? AppTheme.success
                          : AppTheme.primary,
                    ),
                    minHeight: 4,
                  ),
                ),
                const SizedBox(height: AppTheme.spacing12),
              ],

              // Placeholder slot items
              ...slots.map((slot) {
                final isFilled = _assignments.containsKey(slot.id);
                return _PlaceholderSlotItem(
                  slot: slot,
                  isFilled: isFilled,
                  assignedPath: _assignments[slot.id],
                  onPickMedia: () => _pickMediaForSlot(slot),
                  onRemove:
                      isFilled ? () => _removeMediaFromSlot(slot.id) : null,
                );
              }),

              const SizedBox(height: AppTheme.spacing24),

              // Error message
              // (shown via provider if needed)

              // Create Project button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _canCreate ? _createProject : null,
                  icon: _isCreating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.auto_awesome, size: 18),
                  label: Text(
                    _isCreating
                        ? 'Creating Project...'
                        : _filledCount == slots.length
                            ? 'Create Project'
                            : 'Create with $_filledCount/${slots.length} slots',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _canCreate
                        ? AppTheme.primary
                        : AppTheme.textDisabled.withValues(alpha: 0.3),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.spacing16),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickMediaForSlot(PlaceholderSlotData slot) async {
    try {
      final allowedExtensions = slot.mediaType == 'video'
          ? ['mp4', 'mov', 'avi', 'mkv', 'webm']
          : ['jpg', 'jpeg', 'png', 'webp', 'gif'];

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: allowedExtensions,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _assignments[slot.id] = result.files.single.path!;
        });
      }
    } catch (e) {
      // File picker not available on all platforms; fall back gracefully
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not open file picker: $e',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _removeMediaFromSlot(String slotId) {
    setState(() {
      _assignments.remove(slotId);
    });
  }

  Future<void> _createProject() async {
    setState(() => _isCreating = true);

    // Use the template provider to create the project
    final notifier = ref.read(templateProvider.notifier);
    notifier.selectTemplate(widget.template);

    // Apply all assignments to the provider
    for (final entry in _assignments.entries) {
      notifier.assignMedia(entry.key, entry.value);
    }

    final projectId = await notifier.createProject();

    if (!mounted) return;
    setState(() => _isCreating = false);

    if (projectId != null) {
      // Navigate to the editor with the new project
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Created project from "${widget.template.name}"',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      context.go('/editor/$projectId');
    } else {
      // Show error
      final errorState = ref.read(templateProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorState.errorMessage ?? 'Failed to create project from template',
          ),
          duration: const Duration(seconds: 3),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }
}

/// Stat badge widget
class _StatBadge extends StatelessWidget {
  const _StatBadge({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: context.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Placeholder slot item in the detail sheet
class _PlaceholderSlotItem extends StatelessWidget {
  const _PlaceholderSlotItem({
    required this.slot,
    required this.isFilled,
    required this.onPickMedia,
    this.assignedPath,
    this.onRemove,
  });
  final PlaceholderSlotData slot;
  final bool isFilled;
  final String? assignedPath;
  final VoidCallback onPickMedia;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final isVideoSlot = slot.mediaType == 'video';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacing8),
      child: InkWell(
        onTap: onPickMedia,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        child: Container(
          padding: const EdgeInsets.all(AppTheme.spacing12),
          decoration: BoxDecoration(
            color: isFilled
                ? AppTheme.success.withValues(alpha: 0.08)
                : AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            border: Border.all(
              color: isFilled
                  ? AppTheme.success.withValues(alpha: 0.3)
                  : AppTheme.textDisabled.withValues(alpha: 0.15),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              // Slot type icon
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: isFilled
                      ? AppTheme.success.withValues(alpha: 0.15)
                      : (isVideoSlot
                          ? AppTheme.primary.withValues(alpha: 0.1)
                          : AppTheme.accent.withValues(alpha: 0.1)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: isFilled
                      ? const Icon(
                          Icons.check,
                          size: 16,
                          color: AppTheme.success,
                        )
                      : Icon(
                          isVideoSlot ? Icons.videocam : Icons.image,
                          size: 16,
                          color:
                              isVideoSlot ? AppTheme.primary : AppTheme.accent,
                        ),
                ),
              ),
              const SizedBox(width: 10),

              // Slot info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      slot.label,
                      style: context.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isFilled
                          ? assignedPath!.split('/').last
                          : 'Tap to select ${isVideoSlot ? "video" : "image"}',
                      style: context.textTheme.bodySmall?.copyWith(
                        color:
                            isFilled ? AppTheme.success : AppTheme.textDisabled,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Duration label
              Text(
                slot.expectedDurationFormatted,
                style: context.textTheme.bodySmall?.copyWith(
                  color: AppTheme.textDisabled,
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 8),

              // Action icon
              if (isFilled && onRemove != null)
                GestureDetector(
                  onTap: onRemove,
                  child: const Icon(
                    Icons.close,
                    size: 18,
                    color: AppTheme.textSecondary,
                  ),
                )
              else
                Icon(
                  isFilled ? Icons.swap_horiz : Icons.add_circle_outline,
                  size: 20,
                  color:
                      isFilled ? AppTheme.textSecondary : AppTheme.primaryLight,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
