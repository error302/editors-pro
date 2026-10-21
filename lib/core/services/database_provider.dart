/// Database provider for EDITORS-PRO.
///
/// Exposes a singleton [AppDatabase] instance via Riverpod so that
/// all features can access the database without manual wiring.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';

/// Singleton database instance provider.
///
/// The database is lazily created on first access and shared across
/// the entire app lifecycle. Calling `ref.invalidate` on this provider
/// is safe — it will close the old database and open a new one.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});
