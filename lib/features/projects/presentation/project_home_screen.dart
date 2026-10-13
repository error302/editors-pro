import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../data/models/project_model.dart';
import '../providers/project_provider.dart';

/// Home screen showing project list, templates, and create button.
class ProjectHomeScreen extends ConsumerStatefulWidget {
  const ProjectHomeScreen({super.key});

  @override
  ConsumerState<ProjectHomeScreen> createState() => _ProjectHomeScreenState();
}

class _ProjectHomeScreenState extends ConsumerState<ProjectHomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Load persisted projects on startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(projectProvider.notifier).loadProjects();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final projectState = ref.watch(projectProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            _buildTabBar(context),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildRecentProjects(context, projectState),
                  _buildTemplates(context),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: projectState.recentProjects.isEmpty ? null : _buildCreateButton(context),
    );
  }

  // ─── Header ───────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          // Logo in 44x44 clean rounded container
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                'assets/icons/logo.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Title + subtitle
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'EDITORS-PRO',
                style: context.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.0,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Video Editor',
                style: context.textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSecondary,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const Spacer(),
          // Search
          _buildHeaderIconButton(
            icon: AppIcons.search,
            tooltip: 'Search projects',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Search coming soon!'),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          // Settings
          _buildHeaderIconButton(
            icon: AppIcons.settings,
            tooltip: 'Settings',
            onTap: () => context.go('/settings'),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.05, end: 0);
  }

  Widget _buildHeaderIconButton({
    required String icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppTheme.surfaceVariant,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            child: AppIcon(icon, size: 18, color: AppTheme.textSecondary),
          ),
        ),
      ),
    );
  }

  // ─── Clean Underline Tab Bar ─────────────────────────────────
  Widget _buildTabBar(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          bottom: BorderSide(color: AppTheme.border, width: 1),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: const UnderlineTabIndicator(
          borderSide: BorderSide(color: AppTheme.primary, width: 2),
          insets: EdgeInsets.zero,
        ),
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelColor: AppTheme.textPrimary,
        unselectedLabelColor: AppTheme.textSecondary,
        labelPadding: const EdgeInsets.symmetric(vertical: 12),
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 12,
          letterSpacing: 0.5,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 12,
          letterSpacing: 0.5,
        ),
        tabs: const [
          Tab(text: 'Recent'),
          Tab(text: 'Templates'),
        ],
      ),
    );
  }

  // ─── Recent Projects Tab ──────────────────────────────────────
  Widget _buildRecentProjects(BuildContext context, ProjectState state) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.recentProjects.isEmpty) {
      return _buildEmptyState(context);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 600;
        final crossAxisCount = isWide ? 2 : 1;
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            // The 16:9 preview and project metadata need more vertical room
            // on phones than the old 1.4 ratio allowed.
            childAspectRatio: isWide ? 1.15 : 1.22,
          ),
          itemCount: state.recentProjects.length,
          itemBuilder: (context, index) {
            final project = state.recentProjects[index];
            return _ProjectCard(
              project: project,
              onTap: () => _openProject(context, project),
              onMore: () => _showProjectActions(context, project),
            )
                .animate(delay: (index * 80).ms)
                .fadeIn(duration: 400.ms)
                .slideY(begin: 0.15, end: 0, duration: 400.ms);
          },
        );
      },
    );
  }

  Future<void> _openProject(BuildContext context, ProjectModel project) async {
    final opened =
        await ref.read(projectProvider.notifier).openProject(project);
    if (!mounted || !context.mounted) return;
    if (opened) {
      context.go('/editor/${project.id}');
      return;
    }

    final message =
        ref.read(projectProvider).error ?? 'Could not open project.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 80x80 rounded icon container — clean and minimal
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
              ),
              alignment: Alignment.center,
              child: AppIcon(
                AppIcons.film,
                size: 36,
                color: AppTheme.textSecondary,
              ),
            ).animate().scaleXY(
                  duration: 600.ms,
                  curve: Curves.elasticOut,
                  begin: 0.5,
                  end: 1.0,
                ),
            const SizedBox(height: 24),
            Text(
              'Start Creating',
              style: context.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Import a video to get started — no setup required',
              textAlign: TextAlign.center,
              style: context.textTheme.bodyMedium?.copyWith(
                color: AppTheme.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                ),
              ),
              onPressed: () => _showCreateProjectDialog(context),
              child: const Text(
                'New Project',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Templates Tab ────────────────────────────────────────────
  Widget _buildTemplates(BuildContext context) {
    final templates = <_TemplateData>[
      _TemplateData(
        name: 'Social Vertical',
        icon: AppIcons.phone,
        aspectRatio: '9:16',
        dimensions: '1080 × 1920',
        width: 1080,
        height: 1920,
        gradient: AppTheme.accentGradient,
        color: AppTheme.accent,
      ),
      _TemplateData(
        name: 'Social Square',
        icon: AppIcons.crop,
        aspectRatio: '1:1',
        dimensions: '1080 × 1080',
        width: 1080,
        height: 1080,
        gradient: AppTheme.secondaryGradient,
        color: AppTheme.secondary,
      ),
      _TemplateData(
        name: 'YouTube',
        icon: AppIcons.monitor,
        aspectRatio: '16:9',
        dimensions: '1920 × 1080',
        width: 1920,
        height: 1080,
        gradient: AppTheme.primaryGradient,
        color: AppTheme.primary,
      ),
      _TemplateData(
        name: 'Cinematic',
        icon: AppIcons.film,
        aspectRatio: '21:9',
        dimensions: '2560 × 1080',
        width: 2560,
        height: 1080,
        gradient: const LinearGradient(
          colors: [Color(0xFFFFB84D), Color(0xFFFF7E5F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        color: AppTheme.warning,
      ),
    ];

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.0,
      ),
      itemCount: templates.length,
      itemBuilder: (context, index) {
        final t = templates[index];
        return _TemplateCard(
          data: t,
          onTap: () => _createProjectFromTemplate(
            context,
            t.name,
            width: t.width,
            height: t.height,
          ),
        )
            .animate(delay: (index * 80).ms)
            .fadeIn(duration: 400.ms)
            .scaleXY(
              begin: 0.9,
              end: 1.0,
              duration: 400.ms,
              curve: Curves.easeOutBack,
            );
      },
    );
  }

  // ─── Circular FAB ────────────────────────────────────────────
  Widget _buildCreateButton(BuildContext context) {
    return FloatingActionButton(
      backgroundColor: AppTheme.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      highlightElevation: 0,
      shape: const CircleBorder(),
      onPressed: () => _showCreateProjectDialog(context),
      child: const AppIcon(AppIcons.plus, size: 24, color: Colors.white),
    ).animate().scaleXY(
          duration: 600.ms,
          delay: 500.ms,
          curve: Curves.elasticOut,
          begin: 0.5,
          end: 1.0,
        );
  }

  // ─── Dialogs & Project Ops ────────────────────────────────────
  void _showCreateProjectDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => _CreateProjectDialog(
        onCreate: (name, width, height, fps) async {
          final project = await _createProject(
            name,
            width: width,
            height: height,
            fps: fps,
            navigate: false,
          );
          if (project == null) {
            return ref.read(projectProvider).error ??
                'Could not create the project. Please try again.';
          }
          if (!mounted || !dialogContext.mounted) return null;
          Navigator.pop(dialogContext);
          context.go('/editor/${project.id}');
          return null;
        },
      ),
    );
  }

  void _createProjectFromTemplate(
    BuildContext context,
    String templateName, {
    int width = 1920,
    int height = 1080,
  }) {
    unawaited(_createProject(templateName, width: width, height: height));
  }

  Future<ProjectModel?> _createProject(
    String name, {
    int width = 1920,
    int height = 1080,
    double fps = 30,
    bool navigate = true,
  }) async {
    final effectiveName = name.trim().isEmpty ? 'Untitled Project' : name.trim();
    final project = await ref
        .read(projectProvider.notifier)
        .createProject(effectiveName, width: width, height: height, fps: fps);
    if (!mounted) return null;
    if (project == null) {
      if (navigate) {
        final message = ref.read(projectProvider).error ??
            'Could not create the project. Please try again.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
      return null;
    }
    if (navigate) {
      context.go('/editor/${project.id}');
    }
    return project;
  }

  void _duplicateProject(ProjectModel project) {
    unawaited(_duplicateProjectAsync(project));
  }

  Future<void> _duplicateProjectAsync(ProjectModel project) async {
    final duplicate = await ref
        .read(projectProvider.notifier)
        .createProject('${project.name} (Copy)');
    if (!mounted) return;
    if (duplicate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ref.read(projectProvider).error ??
              'Could not duplicate the project.'),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Duplicated "${project.name}"'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, ProjectModel project) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${project.name}"?'),
        content: const Text(
          'This will permanently delete the project and all its media. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () {
              Navigator.pop(ctx);
              unawaited(
                ref.read(projectProvider.notifier).deleteProject(project.id),
              );
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  /// Phase F.2: Show a bottom sheet with project actions (Open, Duplicate,
  /// Delete). Replaces the old "more" button that only offered delete.
  /// This is the pro workflow pattern — duplicate to fork a delivery
  /// variant, delete to remove, open to edit.
  void _showProjectActions(BuildContext context, ProjectModel project) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusXLarge),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.textDisabled,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacing16, vertical: AppTheme.spacing4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  project.name,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('Share Project Backup'),
              subtitle: const Text(
                'Timeline data only; source media stays on this device',
              ),
              onTap: () {
                Navigator.pop(ctx);
                unawaited(_shareProjectBackup(context, project));
              },
            ),
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: const Text('Open project'),
              subtitle: const Text('Continue editing in the timeline'),
              onTap: () {
                Navigator.pop(ctx);
                unawaited(_openProject(context, project));
              },
            ),
            ListTile(
              leading: const Icon(Icons.content_copy),
              title: const Text('Duplicate project'),
              subtitle: const Text(
                'Create a copy with the same media for a delivery variant',
              ),
              onTap: () {
                Navigator.pop(ctx);
                unawaited(
                  ref.read(projectProvider.notifier).duplicateProject(project.id).then((_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('"${project.name}" duplicated.'),
                          action: SnackBarAction(
                            label: 'Open copy',
                            onPressed: () {
                              // The duplicated project is at the top of recentProjects
                              final dup = ref.read(projectProvider).recentProjects.first;
                              context.go('/editor/${dup.id}');
                            },
                          ),
                        ),
                      );
                    }
                  }).catchError((e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Duplicate failed: $e')),
                      );
                    }
                  }),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: AppTheme.error),
              title: Text('Delete project',
                  style: TextStyle(color: AppTheme.error)),
              subtitle: const Text(
                'Permanently remove the project and its media references',
              ),
              onTap: () {
                Navigator.pop(ctx);
                _showDeleteConfirmation(context, project);
              },
            ),
            const SizedBox(height: AppTheme.spacing8),
          ],
        ),
      ),
    );
  }

  Future<void> _shareProjectBackup(
    BuildContext context,
    ProjectModel project,
  ) async {
    try {
      final path = await ref
          .read(projectProvider.notifier)
          .prepareProjectExport(project);
      if (path == null || path.isEmpty) {
        throw StateError('Could not save the project backup.');
      }

      await Share.shareXFiles(
        [XFile(path, name: '${project.name}.epp')],
        text: 'EDITORS-PRO timeline backup. Source media is not included.',
        subject: '${project.name} project backup',
      );
    } catch (error) {
      if (!mounted || !context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not share project backup: $error')),
      );
    }
  }
}

// ─── Project Card ────────────────────────────────────────────────
class _ProjectCard extends StatelessWidget {
  final ProjectModel project;
  final VoidCallback onTap;
  final VoidCallback onMore;

  const _ProjectCard({
    required this.project,
    required this.onTap,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─ Thumbnail (16:9) with dark placeholder ─
              Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceVariant,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(AppTheme.radiusLarge),
                        ),
                      ),
                      child: Center(
                        child: AppIcon(
                          AppIcons.film,
                          size: 28,
                          color: AppTheme.textDisabled,
                        ),
                      ),
                    ),
                  ),
                  // More options button (top-right)
                  Positioned(
                    top: 2,
                    right: 2,
                    child: IconButton(
                      tooltip: 'Project actions',
                      onPressed: onMore,
                      constraints:
                          const BoxConstraints.tightFor(width: 44, height: 44),
                      padding: EdgeInsets.zero,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black.withOpacity(0.58),
                        foregroundColor: Colors.white,
                      ),
                      icon: const AppIcon(
                        AppIcons.moreHorizontal,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  // Duration badge (bottom-right)
                  Positioned(
                    bottom: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusSmall),
                      ),
                      child: Text(
                        _formatDuration(project.durationMs),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              // ─ Info section — name + last modified ─
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      project.name,
                      style: context.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Edited ${_formatDate(project.updatedAt)}',
                      style: context.textTheme.labelSmall?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(int durationMs) {
    if (durationMs <= 0) return '0:00';
    final duration = Duration(milliseconds: durationMs);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatDate(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.day}/${date.month}/${date.year}';
  }
}

// ─── Template Data + Card ────────────────────────────────────────
class _TemplateData {
  final String name;
  final String icon;
  final String aspectRatio;
  final String dimensions;
  final int width;
  final int height;
  final Gradient gradient;
  final Color color;

  const _TemplateData({
    required this.name,
    required this.icon,
    required this.aspectRatio,
    required this.dimensions,
    required this.width,
    required this.height,
    required this.gradient,
    required this.color,
  });
}

class _TemplateCard extends StatelessWidget {
  final _TemplateData data;
  final VoidCallback onTap;

  const _TemplateCard({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Solid tinted icon container — no gradient
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: data.color.withOpacity(0.15),
                    borderRadius:
                        BorderRadius.circular(AppTheme.radiusMedium),
                  ),
                  alignment: Alignment.center,
                  child: AppIcon(data.icon, size: 22, color: data.color),
                ),
                const SizedBox(height: 12),
                Text(
                  data.name,
                  style: context.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  data.aspectRatio,
                  style: context.textTheme.labelSmall?.copyWith(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  data.dimensions,
                  style: context.textTheme.labelSmall?.copyWith(
                    color: AppTheme.textDisabled,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Reusable Gradient Button ────────────────────────────────────
class _GradientButton extends StatelessWidget {
  final String icon;
  final String label;
  final Gradient gradient;
  final List<BoxShadow>? shadow;
  final VoidCallback onPressed;
  final EdgeInsets padding;
  final bool isLoading;
  final bool enabled;

  const _GradientButton({
    required this.icon,
    required this.label,
    required this.gradient,
    required this.onPressed,
    this.shadow,
    this.padding = const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
    this.isLoading = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        boxShadow: shadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          child: Padding(
            padding: padding,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isLoading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                else
                  AppIcon(icon, size: 18, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Create Project Dialog ───────────────────────────────────────
class _CreateProjectDialog extends StatefulWidget {
  final Future<String?> Function(
    String name,
    int width,
    int height,
    double fps,
  ) onCreate;

  const _CreateProjectDialog({required this.onCreate});

  @override
  State<_CreateProjectDialog> createState() => _CreateProjectDialogState();
}

class _CreateProjectDialogState extends State<_CreateProjectDialog> {
  final _nameController = TextEditingController(text: 'Untitled Project');
  String _selectedResolution = '1080p';
  _CanvasPreset _selectedCanvas = _CanvasPreset.landscape;
  double _selectedFrameRate = 30;
  bool _isCreating = false;
  String? _errorMessage;

  static const _resolutions = <_ResolutionOption>[
    _ResolutionOption('720p', 1280, 720),
    _ResolutionOption('1080p', 1920, 1080),
    _ResolutionOption('4K', 3840, 2160),
  ];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      backgroundColor: AppTheme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      ),
      title: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.16),
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            ),
            child: const SizedBox(
              width: 40,
              height: 40,
              child: Icon(
                Icons.movie_creation_outlined,
                color: AppTheme.primaryLight,
                size: 21,
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(child: Text('New Project')),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(context, 'Project name'),
          const SizedBox(height: 8),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              hintText: 'Enter project name',
              counterText: '',
            ),
            autofocus: false,
            maxLength: 60,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onChanged: (_) {
              if (_errorMessage != null) {
                setState(() => _errorMessage = null);
              }
            },
          ),
          const SizedBox(height: 18),
          _sectionLabel(context, 'Canvas'),
          const SizedBox(height: 8),
          SegmentedButton<_CanvasPreset>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: _CanvasPreset.landscape, label: Text('16:9')),
              ButtonSegment(value: _CanvasPreset.portrait, label: Text('9:16')),
              ButtonSegment(value: _CanvasPreset.square, label: Text('1:1')),
            ],
            selected: {_selectedCanvas},
            onSelectionChanged: (selection) => setState(
              () => _selectedCanvas = selection.first,
            ),
          ),
          const SizedBox(height: 18),
          _sectionLabel(context, 'Resolution'),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: _resolutions
                .map((option) => ButtonSegment<String>(
                      value: option.label,
                      label: Text(option.label),
                    ))
                .toList(),
            selected: {_selectedResolution},
            onSelectionChanged: (selection) => setState(
              () => _selectedResolution = selection.first,
            ),
          ),
          const SizedBox(height: 18),
          _sectionLabel(context, 'Frame rate'),
          const SizedBox(height: 8),
          SegmentedButton<double>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 24.0, label: Text('24 fps')),
              ButtonSegment(value: 30.0, label: Text('30 fps')),
              ButtonSegment(value: 60.0, label: Text('60 fps')),
            ],
            selected: {_selectedFrameRate},
            onSelectionChanged: (selection) => setState(
              () => _selectedFrameRate = selection.first,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            ),
            child: Text(
              '${_dimensions.width} x ${_dimensions.height}  ·  ${_selectedFrameRate.toInt()} fps',
              textAlign: TextAlign.center,
              style: context.textTheme.labelLarge?.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: context.textTheme.bodySmall?.copyWith(
                color: AppTheme.error,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isCreating ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        _GradientButton(
          icon: AppIcons.plus,
          label: _isCreating ? 'Creating...' : 'Create project',
          gradient: AppTheme.primaryGradient,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          onPressed: _submit,
          isLoading: _isCreating,
          enabled: !_isCreating,
        ),
      ],
    );
  }

  _ResolutionOption get _selectedResolutionOption =>
      _resolutions.firstWhere((option) => option.label == _selectedResolution);

  ({int width, int height}) get _dimensions {
    final resolution = _selectedResolutionOption;
    return switch (_selectedCanvas) {
      _CanvasPreset.landscape =>
        (width: resolution.width, height: resolution.height),
      _CanvasPreset.portrait =>
        (width: resolution.height, height: resolution.width),
      _CanvasPreset.square =>
        (width: resolution.height, height: resolution.height),
    };
  }

  Widget _sectionLabel(BuildContext context, String label) => Padding(
        padding: const EdgeInsets.only(left: 2),
        child: Text(
          label,
          style: context.textTheme.labelLarge?.copyWith(
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  Future<void> _submit() async {
    if (_isCreating) return;
    setState(() {
      _isCreating = true;
      _errorMessage = null;
    });
    final dimensions = _dimensions;
    final error = await widget.onCreate(
      _nameController.text,
      dimensions.width,
      dimensions.height,
      _selectedFrameRate,
    );
    if (!mounted) return;
    setState(() {
      _isCreating = false;
      _errorMessage = error;
    });
  }
}

enum _CanvasPreset { landscape, portrait, square }

class _ResolutionOption {
  final String label;
  final int width;
  final int height;
  const _ResolutionOption(this.label, this.width, this.height);
}
