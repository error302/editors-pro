import 'package:editors_pro/data/models/project_model.dart';
import 'package:editors_pro/features/projects/providers/project_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('media assets update when the current project keeps the same id', () {
    late _TestProjectNotifier notifier;
    final container = ProviderContainer(
      overrides: [
        projectProvider.overrideWith((ref) {
          return notifier = _TestProjectNotifier(ref);
        }),
      ],
    );
    addTearDown(container.dispose);

    final assetsSubscription = container.listen(
      mediaAssetsProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(assetsSubscription.close);

    const project = ProjectModel(
      id: 'project-1',
      name: 'Test project',
      createdAt: 1,
      updatedAt: 1,
      width: 1920,
      height: 1080,
      fps: 30,
    );
    notifier.setProject(project);
    expect(container.read(mediaAssetsProvider), isEmpty);

    const asset = MediaAssetModel(
      id: 'asset-1',
      filePath: '/media/image.png',
      fileName: 'image.png',
      mediaType: MediaType.image,
    );
    notifier.setProject(
      project.copyWith(
        updatedAt: 2,
        mediaAssets: const [asset],
      ),
    );

    expect(container.read(mediaAssetsProvider), [asset]);
  });
}

class _TestProjectNotifier extends ProjectNotifier {
  _TestProjectNotifier(super._ref);

  void setProject(ProjectModel project) {
    state = state.copyWith(currentProject: project);
  }
}
