// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $ProjectEntriesTable extends ProjectEntries
    with TableInfo<$ProjectEntriesTable, ProjectEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProjectEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('Untitled'));
  static const VerificationMeta _widthMeta = const VerificationMeta('width');
  @override
  late final GeneratedColumn<int> width = GeneratedColumn<int>(
      'width', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1920));
  static const VerificationMeta _heightMeta = const VerificationMeta('height');
  @override
  late final GeneratedColumn<int> height = GeneratedColumn<int>(
      'height', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1080));
  static const VerificationMeta _fpsMeta = const VerificationMeta('fps');
  @override
  late final GeneratedColumn<double> fps = GeneratedColumn<double>(
      'fps', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(30.0));
  static const VerificationMeta _durationMsMeta =
      const VerificationMeta('durationMs');
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
      'duration_ms', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _thumbnailPathMeta =
      const VerificationMeta('thumbnailPath');
  @override
  late final GeneratedColumn<String> thumbnailPath = GeneratedColumn<String>(
      'thumbnail_path', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _eppFilePathMeta =
      const VerificationMeta('eppFilePath');
  @override
  late final GeneratedColumn<String> eppFilePath = GeneratedColumn<String>(
      'epp_file_path', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        name,
        width,
        height,
        fps,
        durationMs,
        createdAt,
        updatedAt,
        thumbnailPath,
        eppFilePath
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'project_entries';
  @override
  VerificationContext validateIntegrity(Insertable<ProjectEntry> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    }
    if (data.containsKey('width')) {
      context.handle(
          _widthMeta, width.isAcceptableOrUnknown(data['width']!, _widthMeta));
    }
    if (data.containsKey('height')) {
      context.handle(_heightMeta,
          height.isAcceptableOrUnknown(data['height']!, _heightMeta));
    }
    if (data.containsKey('fps')) {
      context.handle(
          _fpsMeta, fps.isAcceptableOrUnknown(data['fps']!, _fpsMeta));
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
          _durationMsMeta,
          durationMs.isAcceptableOrUnknown(
              data['duration_ms']!, _durationMsMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('thumbnail_path')) {
      context.handle(
          _thumbnailPathMeta,
          thumbnailPath.isAcceptableOrUnknown(
              data['thumbnail_path']!, _thumbnailPathMeta));
    }
    if (data.containsKey('epp_file_path')) {
      context.handle(
          _eppFilePathMeta,
          eppFilePath.isAcceptableOrUnknown(
              data['epp_file_path']!, _eppFilePathMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProjectEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProjectEntry(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      width: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}width'])!,
      height: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}height'])!,
      fps: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}fps'])!,
      durationMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}duration_ms'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at'])!,
      thumbnailPath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}thumbnail_path']),
      eppFilePath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}epp_file_path']),
    );
  }

  @override
  $ProjectEntriesTable createAlias(String alias) {
    return $ProjectEntriesTable(attachedDatabase, alias);
  }
}

class ProjectEntry extends DataClass implements Insertable<ProjectEntry> {
  final String id;
  final String name;
  final int width;
  final int height;
  final double fps;
  final int durationMs;
  final int createdAt;
  final int updatedAt;
  final String? thumbnailPath;
  final String? eppFilePath;
  const ProjectEntry(
      {required this.id,
      required this.name,
      required this.width,
      required this.height,
      required this.fps,
      required this.durationMs,
      required this.createdAt,
      required this.updatedAt,
      this.thumbnailPath,
      this.eppFilePath});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['width'] = Variable<int>(width);
    map['height'] = Variable<int>(height);
    map['fps'] = Variable<double>(fps);
    map['duration_ms'] = Variable<int>(durationMs);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || thumbnailPath != null) {
      map['thumbnail_path'] = Variable<String>(thumbnailPath);
    }
    if (!nullToAbsent || eppFilePath != null) {
      map['epp_file_path'] = Variable<String>(eppFilePath);
    }
    return map;
  }

  ProjectEntriesCompanion toCompanion(bool nullToAbsent) {
    return ProjectEntriesCompanion(
      id: Value(id),
      name: Value(name),
      width: Value(width),
      height: Value(height),
      fps: Value(fps),
      durationMs: Value(durationMs),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      thumbnailPath: thumbnailPath == null && nullToAbsent
          ? const Value.absent()
          : Value(thumbnailPath),
      eppFilePath: eppFilePath == null && nullToAbsent
          ? const Value.absent()
          : Value(eppFilePath),
    );
  }

  factory ProjectEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProjectEntry(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      width: serializer.fromJson<int>(json['width']),
      height: serializer.fromJson<int>(json['height']),
      fps: serializer.fromJson<double>(json['fps']),
      durationMs: serializer.fromJson<int>(json['durationMs']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      thumbnailPath: serializer.fromJson<String?>(json['thumbnailPath']),
      eppFilePath: serializer.fromJson<String?>(json['eppFilePath']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'width': serializer.toJson<int>(width),
      'height': serializer.toJson<int>(height),
      'fps': serializer.toJson<double>(fps),
      'durationMs': serializer.toJson<int>(durationMs),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'thumbnailPath': serializer.toJson<String?>(thumbnailPath),
      'eppFilePath': serializer.toJson<String?>(eppFilePath),
    };
  }

  ProjectEntry copyWith(
          {String? id,
          String? name,
          int? width,
          int? height,
          double? fps,
          int? durationMs,
          int? createdAt,
          int? updatedAt,
          Value<String?> thumbnailPath = const Value.absent(),
          Value<String?> eppFilePath = const Value.absent()}) =>
      ProjectEntry(
        id: id ?? this.id,
        name: name ?? this.name,
        width: width ?? this.width,
        height: height ?? this.height,
        fps: fps ?? this.fps,
        durationMs: durationMs ?? this.durationMs,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        thumbnailPath:
            thumbnailPath.present ? thumbnailPath.value : this.thumbnailPath,
        eppFilePath: eppFilePath.present ? eppFilePath.value : this.eppFilePath,
      );
  ProjectEntry copyWithCompanion(ProjectEntriesCompanion data) {
    return ProjectEntry(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      width: data.width.present ? data.width.value : this.width,
      height: data.height.present ? data.height.value : this.height,
      fps: data.fps.present ? data.fps.value : this.fps,
      durationMs:
          data.durationMs.present ? data.durationMs.value : this.durationMs,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      thumbnailPath: data.thumbnailPath.present
          ? data.thumbnailPath.value
          : this.thumbnailPath,
      eppFilePath:
          data.eppFilePath.present ? data.eppFilePath.value : this.eppFilePath,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProjectEntry(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('fps: $fps, ')
          ..write('durationMs: $durationMs, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('thumbnailPath: $thumbnailPath, ')
          ..write('eppFilePath: $eppFilePath')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, width, height, fps, durationMs,
      createdAt, updatedAt, thumbnailPath, eppFilePath);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProjectEntry &&
          other.id == this.id &&
          other.name == this.name &&
          other.width == this.width &&
          other.height == this.height &&
          other.fps == this.fps &&
          other.durationMs == this.durationMs &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.thumbnailPath == this.thumbnailPath &&
          other.eppFilePath == this.eppFilePath);
}

class ProjectEntriesCompanion extends UpdateCompanion<ProjectEntry> {
  final Value<String> id;
  final Value<String> name;
  final Value<int> width;
  final Value<int> height;
  final Value<double> fps;
  final Value<int> durationMs;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<String?> thumbnailPath;
  final Value<String?> eppFilePath;
  final Value<int> rowid;
  const ProjectEntriesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.fps = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.thumbnailPath = const Value.absent(),
    this.eppFilePath = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProjectEntriesCompanion.insert({
    required String id,
    this.name = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.fps = const Value.absent(),
    this.durationMs = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.thumbnailPath = const Value.absent(),
    this.eppFilePath = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<ProjectEntry> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? width,
    Expression<int>? height,
    Expression<double>? fps,
    Expression<int>? durationMs,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<String>? thumbnailPath,
    Expression<String>? eppFilePath,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (fps != null) 'fps': fps,
      if (durationMs != null) 'duration_ms': durationMs,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (thumbnailPath != null) 'thumbnail_path': thumbnailPath,
      if (eppFilePath != null) 'epp_file_path': eppFilePath,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProjectEntriesCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<int>? width,
      Value<int>? height,
      Value<double>? fps,
      Value<int>? durationMs,
      Value<int>? createdAt,
      Value<int>? updatedAt,
      Value<String?>? thumbnailPath,
      Value<String?>? eppFilePath,
      Value<int>? rowid}) {
    return ProjectEntriesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      width: width ?? this.width,
      height: height ?? this.height,
      fps: fps ?? this.fps,
      durationMs: durationMs ?? this.durationMs,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      eppFilePath: eppFilePath ?? this.eppFilePath,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (width.present) {
      map['width'] = Variable<int>(width.value);
    }
    if (height.present) {
      map['height'] = Variable<int>(height.value);
    }
    if (fps.present) {
      map['fps'] = Variable<double>(fps.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (thumbnailPath.present) {
      map['thumbnail_path'] = Variable<String>(thumbnailPath.value);
    }
    if (eppFilePath.present) {
      map['epp_file_path'] = Variable<String>(eppFilePath.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProjectEntriesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('fps: $fps, ')
          ..write('durationMs: $durationMs, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('thumbnailPath: $thumbnailPath, ')
          ..write('eppFilePath: $eppFilePath, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MediaAssetEntriesTable extends MediaAssetEntries
    with TableInfo<$MediaAssetEntriesTable, MediaAssetEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MediaAssetEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _projectIdMeta =
      const VerificationMeta('projectId');
  @override
  late final GeneratedColumn<String> projectId = GeneratedColumn<String>(
      'project_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES project_entries (id)'));
  static const VerificationMeta _filePathMeta =
      const VerificationMeta('filePath');
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
      'file_path', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _fileNameMeta =
      const VerificationMeta('fileName');
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
      'file_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _mediaTypeMeta =
      const VerificationMeta('mediaType');
  @override
  late final GeneratedColumn<String> mediaType = GeneratedColumn<String>(
      'media_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _durationMsMeta =
      const VerificationMeta('durationMs');
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
      'duration_ms', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _widthMeta = const VerificationMeta('width');
  @override
  late final GeneratedColumn<int> width = GeneratedColumn<int>(
      'width', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _heightMeta = const VerificationMeta('height');
  @override
  late final GeneratedColumn<int> height = GeneratedColumn<int>(
      'height', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _fileSizeBytesMeta =
      const VerificationMeta('fileSizeBytes');
  @override
  late final GeneratedColumn<int> fileSizeBytes = GeneratedColumn<int>(
      'file_size_bytes', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _codecMeta = const VerificationMeta('codec');
  @override
  late final GeneratedColumn<String> codec = GeneratedColumn<String>(
      'codec', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _bitrateMeta =
      const VerificationMeta('bitrate');
  @override
  late final GeneratedColumn<int> bitrate = GeneratedColumn<int>(
      'bitrate', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _thumbnailPathMeta =
      const VerificationMeta('thumbnailPath');
  @override
  late final GeneratedColumn<String> thumbnailPath = GeneratedColumn<String>(
      'thumbnail_path', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _importedAtMeta =
      const VerificationMeta('importedAt');
  @override
  late final GeneratedColumn<int> importedAt = GeneratedColumn<int>(
      'imported_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        projectId,
        filePath,
        fileName,
        mediaType,
        durationMs,
        width,
        height,
        fileSizeBytes,
        codec,
        bitrate,
        thumbnailPath,
        importedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'media_asset_entries';
  @override
  VerificationContext validateIntegrity(Insertable<MediaAssetEntry> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('project_id')) {
      context.handle(_projectIdMeta,
          projectId.isAcceptableOrUnknown(data['project_id']!, _projectIdMeta));
    } else if (isInserting) {
      context.missing(_projectIdMeta);
    }
    if (data.containsKey('file_path')) {
      context.handle(_filePathMeta,
          filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta));
    } else if (isInserting) {
      context.missing(_filePathMeta);
    }
    if (data.containsKey('file_name')) {
      context.handle(_fileNameMeta,
          fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta));
    } else if (isInserting) {
      context.missing(_fileNameMeta);
    }
    if (data.containsKey('media_type')) {
      context.handle(_mediaTypeMeta,
          mediaType.isAcceptableOrUnknown(data['media_type']!, _mediaTypeMeta));
    } else if (isInserting) {
      context.missing(_mediaTypeMeta);
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
          _durationMsMeta,
          durationMs.isAcceptableOrUnknown(
              data['duration_ms']!, _durationMsMeta));
    }
    if (data.containsKey('width')) {
      context.handle(
          _widthMeta, width.isAcceptableOrUnknown(data['width']!, _widthMeta));
    }
    if (data.containsKey('height')) {
      context.handle(_heightMeta,
          height.isAcceptableOrUnknown(data['height']!, _heightMeta));
    }
    if (data.containsKey('file_size_bytes')) {
      context.handle(
          _fileSizeBytesMeta,
          fileSizeBytes.isAcceptableOrUnknown(
              data['file_size_bytes']!, _fileSizeBytesMeta));
    }
    if (data.containsKey('codec')) {
      context.handle(
          _codecMeta, codec.isAcceptableOrUnknown(data['codec']!, _codecMeta));
    }
    if (data.containsKey('bitrate')) {
      context.handle(_bitrateMeta,
          bitrate.isAcceptableOrUnknown(data['bitrate']!, _bitrateMeta));
    }
    if (data.containsKey('thumbnail_path')) {
      context.handle(
          _thumbnailPathMeta,
          thumbnailPath.isAcceptableOrUnknown(
              data['thumbnail_path']!, _thumbnailPathMeta));
    }
    if (data.containsKey('imported_at')) {
      context.handle(
          _importedAtMeta,
          importedAt.isAcceptableOrUnknown(
              data['imported_at']!, _importedAtMeta));
    } else if (isInserting) {
      context.missing(_importedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MediaAssetEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MediaAssetEntry(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      projectId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}project_id'])!,
      filePath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}file_path'])!,
      fileName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}file_name'])!,
      mediaType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}media_type'])!,
      durationMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}duration_ms']),
      width: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}width']),
      height: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}height']),
      fileSizeBytes: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}file_size_bytes'])!,
      codec: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}codec']),
      bitrate: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}bitrate']),
      thumbnailPath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}thumbnail_path']),
      importedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}imported_at'])!,
    );
  }

  @override
  $MediaAssetEntriesTable createAlias(String alias) {
    return $MediaAssetEntriesTable(attachedDatabase, alias);
  }
}

class MediaAssetEntry extends DataClass implements Insertable<MediaAssetEntry> {
  final String id;
  final String projectId;
  final String filePath;
  final String fileName;
  final String mediaType;
  final int? durationMs;
  final int? width;
  final int? height;
  final int fileSizeBytes;
  final String? codec;
  final int? bitrate;
  final String? thumbnailPath;
  final int importedAt;
  const MediaAssetEntry(
      {required this.id,
      required this.projectId,
      required this.filePath,
      required this.fileName,
      required this.mediaType,
      this.durationMs,
      this.width,
      this.height,
      required this.fileSizeBytes,
      this.codec,
      this.bitrate,
      this.thumbnailPath,
      required this.importedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['project_id'] = Variable<String>(projectId);
    map['file_path'] = Variable<String>(filePath);
    map['file_name'] = Variable<String>(fileName);
    map['media_type'] = Variable<String>(mediaType);
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    if (!nullToAbsent || width != null) {
      map['width'] = Variable<int>(width);
    }
    if (!nullToAbsent || height != null) {
      map['height'] = Variable<int>(height);
    }
    map['file_size_bytes'] = Variable<int>(fileSizeBytes);
    if (!nullToAbsent || codec != null) {
      map['codec'] = Variable<String>(codec);
    }
    if (!nullToAbsent || bitrate != null) {
      map['bitrate'] = Variable<int>(bitrate);
    }
    if (!nullToAbsent || thumbnailPath != null) {
      map['thumbnail_path'] = Variable<String>(thumbnailPath);
    }
    map['imported_at'] = Variable<int>(importedAt);
    return map;
  }

  MediaAssetEntriesCompanion toCompanion(bool nullToAbsent) {
    return MediaAssetEntriesCompanion(
      id: Value(id),
      projectId: Value(projectId),
      filePath: Value(filePath),
      fileName: Value(fileName),
      mediaType: Value(mediaType),
      durationMs: durationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMs),
      width:
          width == null && nullToAbsent ? const Value.absent() : Value(width),
      height:
          height == null && nullToAbsent ? const Value.absent() : Value(height),
      fileSizeBytes: Value(fileSizeBytes),
      codec:
          codec == null && nullToAbsent ? const Value.absent() : Value(codec),
      bitrate: bitrate == null && nullToAbsent
          ? const Value.absent()
          : Value(bitrate),
      thumbnailPath: thumbnailPath == null && nullToAbsent
          ? const Value.absent()
          : Value(thumbnailPath),
      importedAt: Value(importedAt),
    );
  }

  factory MediaAssetEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MediaAssetEntry(
      id: serializer.fromJson<String>(json['id']),
      projectId: serializer.fromJson<String>(json['projectId']),
      filePath: serializer.fromJson<String>(json['filePath']),
      fileName: serializer.fromJson<String>(json['fileName']),
      mediaType: serializer.fromJson<String>(json['mediaType']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
      width: serializer.fromJson<int?>(json['width']),
      height: serializer.fromJson<int?>(json['height']),
      fileSizeBytes: serializer.fromJson<int>(json['fileSizeBytes']),
      codec: serializer.fromJson<String?>(json['codec']),
      bitrate: serializer.fromJson<int?>(json['bitrate']),
      thumbnailPath: serializer.fromJson<String?>(json['thumbnailPath']),
      importedAt: serializer.fromJson<int>(json['importedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'projectId': serializer.toJson<String>(projectId),
      'filePath': serializer.toJson<String>(filePath),
      'fileName': serializer.toJson<String>(fileName),
      'mediaType': serializer.toJson<String>(mediaType),
      'durationMs': serializer.toJson<int?>(durationMs),
      'width': serializer.toJson<int?>(width),
      'height': serializer.toJson<int?>(height),
      'fileSizeBytes': serializer.toJson<int>(fileSizeBytes),
      'codec': serializer.toJson<String?>(codec),
      'bitrate': serializer.toJson<int?>(bitrate),
      'thumbnailPath': serializer.toJson<String?>(thumbnailPath),
      'importedAt': serializer.toJson<int>(importedAt),
    };
  }

  MediaAssetEntry copyWith(
          {String? id,
          String? projectId,
          String? filePath,
          String? fileName,
          String? mediaType,
          Value<int?> durationMs = const Value.absent(),
          Value<int?> width = const Value.absent(),
          Value<int?> height = const Value.absent(),
          int? fileSizeBytes,
          Value<String?> codec = const Value.absent(),
          Value<int?> bitrate = const Value.absent(),
          Value<String?> thumbnailPath = const Value.absent(),
          int? importedAt}) =>
      MediaAssetEntry(
        id: id ?? this.id,
        projectId: projectId ?? this.projectId,
        filePath: filePath ?? this.filePath,
        fileName: fileName ?? this.fileName,
        mediaType: mediaType ?? this.mediaType,
        durationMs: durationMs.present ? durationMs.value : this.durationMs,
        width: width.present ? width.value : this.width,
        height: height.present ? height.value : this.height,
        fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
        codec: codec.present ? codec.value : this.codec,
        bitrate: bitrate.present ? bitrate.value : this.bitrate,
        thumbnailPath:
            thumbnailPath.present ? thumbnailPath.value : this.thumbnailPath,
        importedAt: importedAt ?? this.importedAt,
      );
  MediaAssetEntry copyWithCompanion(MediaAssetEntriesCompanion data) {
    return MediaAssetEntry(
      id: data.id.present ? data.id.value : this.id,
      projectId: data.projectId.present ? data.projectId.value : this.projectId,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      mediaType: data.mediaType.present ? data.mediaType.value : this.mediaType,
      durationMs:
          data.durationMs.present ? data.durationMs.value : this.durationMs,
      width: data.width.present ? data.width.value : this.width,
      height: data.height.present ? data.height.value : this.height,
      fileSizeBytes: data.fileSizeBytes.present
          ? data.fileSizeBytes.value
          : this.fileSizeBytes,
      codec: data.codec.present ? data.codec.value : this.codec,
      bitrate: data.bitrate.present ? data.bitrate.value : this.bitrate,
      thumbnailPath: data.thumbnailPath.present
          ? data.thumbnailPath.value
          : this.thumbnailPath,
      importedAt:
          data.importedAt.present ? data.importedAt.value : this.importedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MediaAssetEntry(')
          ..write('id: $id, ')
          ..write('projectId: $projectId, ')
          ..write('filePath: $filePath, ')
          ..write('fileName: $fileName, ')
          ..write('mediaType: $mediaType, ')
          ..write('durationMs: $durationMs, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('fileSizeBytes: $fileSizeBytes, ')
          ..write('codec: $codec, ')
          ..write('bitrate: $bitrate, ')
          ..write('thumbnailPath: $thumbnailPath, ')
          ..write('importedAt: $importedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      projectId,
      filePath,
      fileName,
      mediaType,
      durationMs,
      width,
      height,
      fileSizeBytes,
      codec,
      bitrate,
      thumbnailPath,
      importedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MediaAssetEntry &&
          other.id == this.id &&
          other.projectId == this.projectId &&
          other.filePath == this.filePath &&
          other.fileName == this.fileName &&
          other.mediaType == this.mediaType &&
          other.durationMs == this.durationMs &&
          other.width == this.width &&
          other.height == this.height &&
          other.fileSizeBytes == this.fileSizeBytes &&
          other.codec == this.codec &&
          other.bitrate == this.bitrate &&
          other.thumbnailPath == this.thumbnailPath &&
          other.importedAt == this.importedAt);
}

class MediaAssetEntriesCompanion extends UpdateCompanion<MediaAssetEntry> {
  final Value<String> id;
  final Value<String> projectId;
  final Value<String> filePath;
  final Value<String> fileName;
  final Value<String> mediaType;
  final Value<int?> durationMs;
  final Value<int?> width;
  final Value<int?> height;
  final Value<int> fileSizeBytes;
  final Value<String?> codec;
  final Value<int?> bitrate;
  final Value<String?> thumbnailPath;
  final Value<int> importedAt;
  final Value<int> rowid;
  const MediaAssetEntriesCompanion({
    this.id = const Value.absent(),
    this.projectId = const Value.absent(),
    this.filePath = const Value.absent(),
    this.fileName = const Value.absent(),
    this.mediaType = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.fileSizeBytes = const Value.absent(),
    this.codec = const Value.absent(),
    this.bitrate = const Value.absent(),
    this.thumbnailPath = const Value.absent(),
    this.importedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MediaAssetEntriesCompanion.insert({
    required String id,
    required String projectId,
    required String filePath,
    required String fileName,
    required String mediaType,
    this.durationMs = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.fileSizeBytes = const Value.absent(),
    this.codec = const Value.absent(),
    this.bitrate = const Value.absent(),
    this.thumbnailPath = const Value.absent(),
    required int importedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        projectId = Value(projectId),
        filePath = Value(filePath),
        fileName = Value(fileName),
        mediaType = Value(mediaType),
        importedAt = Value(importedAt);
  static Insertable<MediaAssetEntry> custom({
    Expression<String>? id,
    Expression<String>? projectId,
    Expression<String>? filePath,
    Expression<String>? fileName,
    Expression<String>? mediaType,
    Expression<int>? durationMs,
    Expression<int>? width,
    Expression<int>? height,
    Expression<int>? fileSizeBytes,
    Expression<String>? codec,
    Expression<int>? bitrate,
    Expression<String>? thumbnailPath,
    Expression<int>? importedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (projectId != null) 'project_id': projectId,
      if (filePath != null) 'file_path': filePath,
      if (fileName != null) 'file_name': fileName,
      if (mediaType != null) 'media_type': mediaType,
      if (durationMs != null) 'duration_ms': durationMs,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (fileSizeBytes != null) 'file_size_bytes': fileSizeBytes,
      if (codec != null) 'codec': codec,
      if (bitrate != null) 'bitrate': bitrate,
      if (thumbnailPath != null) 'thumbnail_path': thumbnailPath,
      if (importedAt != null) 'imported_at': importedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MediaAssetEntriesCompanion copyWith(
      {Value<String>? id,
      Value<String>? projectId,
      Value<String>? filePath,
      Value<String>? fileName,
      Value<String>? mediaType,
      Value<int?>? durationMs,
      Value<int?>? width,
      Value<int?>? height,
      Value<int>? fileSizeBytes,
      Value<String?>? codec,
      Value<int?>? bitrate,
      Value<String?>? thumbnailPath,
      Value<int>? importedAt,
      Value<int>? rowid}) {
    return MediaAssetEntriesCompanion(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      filePath: filePath ?? this.filePath,
      fileName: fileName ?? this.fileName,
      mediaType: mediaType ?? this.mediaType,
      durationMs: durationMs ?? this.durationMs,
      width: width ?? this.width,
      height: height ?? this.height,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      codec: codec ?? this.codec,
      bitrate: bitrate ?? this.bitrate,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      importedAt: importedAt ?? this.importedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (projectId.present) {
      map['project_id'] = Variable<String>(projectId.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (mediaType.present) {
      map['media_type'] = Variable<String>(mediaType.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (width.present) {
      map['width'] = Variable<int>(width.value);
    }
    if (height.present) {
      map['height'] = Variable<int>(height.value);
    }
    if (fileSizeBytes.present) {
      map['file_size_bytes'] = Variable<int>(fileSizeBytes.value);
    }
    if (codec.present) {
      map['codec'] = Variable<String>(codec.value);
    }
    if (bitrate.present) {
      map['bitrate'] = Variable<int>(bitrate.value);
    }
    if (thumbnailPath.present) {
      map['thumbnail_path'] = Variable<String>(thumbnailPath.value);
    }
    if (importedAt.present) {
      map['imported_at'] = Variable<int>(importedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MediaAssetEntriesCompanion(')
          ..write('id: $id, ')
          ..write('projectId: $projectId, ')
          ..write('filePath: $filePath, ')
          ..write('fileName: $fileName, ')
          ..write('mediaType: $mediaType, ')
          ..write('durationMs: $durationMs, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('fileSizeBytes: $fileSizeBytes, ')
          ..write('codec: $codec, ')
          ..write('bitrate: $bitrate, ')
          ..write('thumbnailPath: $thumbnailPath, ')
          ..write('importedAt: $importedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UserPreferencesTable extends UserPreferences
    with TableInfo<$UserPreferencesTable, UserPreference> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UserPreferencesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
      'key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
      'value', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'user_preferences';
  @override
  VerificationContext validateIntegrity(Insertable<UserPreference> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
          _keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
          _valueMeta, value.isAcceptableOrUnknown(data['value']!, _valueMeta));
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  UserPreference map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UserPreference(
      key: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      value: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}value'])!,
    );
  }

  @override
  $UserPreferencesTable createAlias(String alias) {
    return $UserPreferencesTable(attachedDatabase, alias);
  }
}

class UserPreference extends DataClass implements Insertable<UserPreference> {
  final String key;
  final String value;
  const UserPreference({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  UserPreferencesCompanion toCompanion(bool nullToAbsent) {
    return UserPreferencesCompanion(
      key: Value(key),
      value: Value(value),
    );
  }

  factory UserPreference.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UserPreference(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  UserPreference copyWith({String? key, String? value}) => UserPreference(
        key: key ?? this.key,
        value: value ?? this.value,
      );
  UserPreference copyWithCompanion(UserPreferencesCompanion data) {
    return UserPreference(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UserPreference(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UserPreference &&
          other.key == this.key &&
          other.value == this.value);
}

class UserPreferencesCompanion extends UpdateCompanion<UserPreference> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const UserPreferencesCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UserPreferencesCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  })  : key = Value(key),
        value = Value(value);
  static Insertable<UserPreference> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UserPreferencesCompanion copyWith(
      {Value<String>? key, Value<String>? value, Value<int>? rowid}) {
    return UserPreferencesCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UserPreferencesCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ProjectEntriesTable projectEntries = $ProjectEntriesTable(this);
  late final $MediaAssetEntriesTable mediaAssetEntries =
      $MediaAssetEntriesTable(this);
  late final $UserPreferencesTable userPreferences =
      $UserPreferencesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [projectEntries, mediaAssetEntries, userPreferences];
}

typedef $$ProjectEntriesTableCreateCompanionBuilder = ProjectEntriesCompanion
    Function({
  required String id,
  Value<String> name,
  Value<int> width,
  Value<int> height,
  Value<double> fps,
  Value<int> durationMs,
  required int createdAt,
  required int updatedAt,
  Value<String?> thumbnailPath,
  Value<String?> eppFilePath,
  Value<int> rowid,
});
typedef $$ProjectEntriesTableUpdateCompanionBuilder = ProjectEntriesCompanion
    Function({
  Value<String> id,
  Value<String> name,
  Value<int> width,
  Value<int> height,
  Value<double> fps,
  Value<int> durationMs,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<String?> thumbnailPath,
  Value<String?> eppFilePath,
  Value<int> rowid,
});

final class $$ProjectEntriesTableReferences
    extends BaseReferences<_$AppDatabase, $ProjectEntriesTable, ProjectEntry> {
  $$ProjectEntriesTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$MediaAssetEntriesTable, List<MediaAssetEntry>>
      _mediaAssetEntriesRefsTable(_$AppDatabase db) =>
          MultiTypedResultKey.fromTable(db.mediaAssetEntries,
              aliasName: $_aliasNameGenerator(
                  db.projectEntries.id, db.mediaAssetEntries.projectId));

  $$MediaAssetEntriesTableProcessedTableManager get mediaAssetEntriesRefs {
    final manager = $$MediaAssetEntriesTableTableManager(
            $_db, $_db.mediaAssetEntries)
        .filter((f) => f.projectId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache =
        $_typedResult.readTableOrNull(_mediaAssetEntriesRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$ProjectEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $ProjectEntriesTable> {
  $$ProjectEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get width => $composableBuilder(
      column: $table.width, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get height => $composableBuilder(
      column: $table.height, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get fps => $composableBuilder(
      column: $table.fps, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get durationMs => $composableBuilder(
      column: $table.durationMs, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get thumbnailPath => $composableBuilder(
      column: $table.thumbnailPath, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get eppFilePath => $composableBuilder(
      column: $table.eppFilePath, builder: (column) => ColumnFilters(column));

  Expression<bool> mediaAssetEntriesRefs(
      Expression<bool> Function($$MediaAssetEntriesTableFilterComposer f) f) {
    final $$MediaAssetEntriesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.mediaAssetEntries,
        getReferencedColumn: (t) => t.projectId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$MediaAssetEntriesTableFilterComposer(
              $db: $db,
              $table: $db.mediaAssetEntries,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$ProjectEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $ProjectEntriesTable> {
  $$ProjectEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get width => $composableBuilder(
      column: $table.width, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get height => $composableBuilder(
      column: $table.height, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get fps => $composableBuilder(
      column: $table.fps, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get durationMs => $composableBuilder(
      column: $table.durationMs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get thumbnailPath => $composableBuilder(
      column: $table.thumbnailPath,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get eppFilePath => $composableBuilder(
      column: $table.eppFilePath, builder: (column) => ColumnOrderings(column));
}

class $$ProjectEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProjectEntriesTable> {
  $$ProjectEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get width =>
      $composableBuilder(column: $table.width, builder: (column) => column);

  GeneratedColumn<int> get height =>
      $composableBuilder(column: $table.height, builder: (column) => column);

  GeneratedColumn<double> get fps =>
      $composableBuilder(column: $table.fps, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
      column: $table.durationMs, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get thumbnailPath => $composableBuilder(
      column: $table.thumbnailPath, builder: (column) => column);

  GeneratedColumn<String> get eppFilePath => $composableBuilder(
      column: $table.eppFilePath, builder: (column) => column);

  Expression<T> mediaAssetEntriesRefs<T extends Object>(
      Expression<T> Function($$MediaAssetEntriesTableAnnotationComposer a) f) {
    final $$MediaAssetEntriesTableAnnotationComposer composer =
        $composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.id,
            referencedTable: $db.mediaAssetEntries,
            getReferencedColumn: (t) => t.projectId,
            builder: (joinBuilder,
                    {$addJoinBuilderToRootComposer,
                    $removeJoinBuilderFromRootComposer}) =>
                $$MediaAssetEntriesTableAnnotationComposer(
                  $db: $db,
                  $table: $db.mediaAssetEntries,
                  $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                  joinBuilder: joinBuilder,
                  $removeJoinBuilderFromRootComposer:
                      $removeJoinBuilderFromRootComposer,
                ));
    return f(composer);
  }
}

class $$ProjectEntriesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ProjectEntriesTable,
    ProjectEntry,
    $$ProjectEntriesTableFilterComposer,
    $$ProjectEntriesTableOrderingComposer,
    $$ProjectEntriesTableAnnotationComposer,
    $$ProjectEntriesTableCreateCompanionBuilder,
    $$ProjectEntriesTableUpdateCompanionBuilder,
    (ProjectEntry, $$ProjectEntriesTableReferences),
    ProjectEntry,
    PrefetchHooks Function({bool mediaAssetEntriesRefs})> {
  $$ProjectEntriesTableTableManager(
      _$AppDatabase db, $ProjectEntriesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProjectEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProjectEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProjectEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<int> width = const Value.absent(),
            Value<int> height = const Value.absent(),
            Value<double> fps = const Value.absent(),
            Value<int> durationMs = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> updatedAt = const Value.absent(),
            Value<String?> thumbnailPath = const Value.absent(),
            Value<String?> eppFilePath = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ProjectEntriesCompanion(
            id: id,
            name: name,
            width: width,
            height: height,
            fps: fps,
            durationMs: durationMs,
            createdAt: createdAt,
            updatedAt: updatedAt,
            thumbnailPath: thumbnailPath,
            eppFilePath: eppFilePath,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            Value<String> name = const Value.absent(),
            Value<int> width = const Value.absent(),
            Value<int> height = const Value.absent(),
            Value<double> fps = const Value.absent(),
            Value<int> durationMs = const Value.absent(),
            required int createdAt,
            required int updatedAt,
            Value<String?> thumbnailPath = const Value.absent(),
            Value<String?> eppFilePath = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ProjectEntriesCompanion.insert(
            id: id,
            name: name,
            width: width,
            height: height,
            fps: fps,
            durationMs: durationMs,
            createdAt: createdAt,
            updatedAt: updatedAt,
            thumbnailPath: thumbnailPath,
            eppFilePath: eppFilePath,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$ProjectEntriesTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({mediaAssetEntriesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (mediaAssetEntriesRefs) db.mediaAssetEntries
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (mediaAssetEntriesRefs)
                    await $_getPrefetchedData<ProjectEntry,
                            $ProjectEntriesTable, MediaAssetEntry>(
                        currentTable: table,
                        referencedTable: $$ProjectEntriesTableReferences
                            ._mediaAssetEntriesRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$ProjectEntriesTableReferences(db, table, p0)
                                .mediaAssetEntriesRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.projectId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$ProjectEntriesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ProjectEntriesTable,
    ProjectEntry,
    $$ProjectEntriesTableFilterComposer,
    $$ProjectEntriesTableOrderingComposer,
    $$ProjectEntriesTableAnnotationComposer,
    $$ProjectEntriesTableCreateCompanionBuilder,
    $$ProjectEntriesTableUpdateCompanionBuilder,
    (ProjectEntry, $$ProjectEntriesTableReferences),
    ProjectEntry,
    PrefetchHooks Function({bool mediaAssetEntriesRefs})>;
typedef $$MediaAssetEntriesTableCreateCompanionBuilder
    = MediaAssetEntriesCompanion Function({
  required String id,
  required String projectId,
  required String filePath,
  required String fileName,
  required String mediaType,
  Value<int?> durationMs,
  Value<int?> width,
  Value<int?> height,
  Value<int> fileSizeBytes,
  Value<String?> codec,
  Value<int?> bitrate,
  Value<String?> thumbnailPath,
  required int importedAt,
  Value<int> rowid,
});
typedef $$MediaAssetEntriesTableUpdateCompanionBuilder
    = MediaAssetEntriesCompanion Function({
  Value<String> id,
  Value<String> projectId,
  Value<String> filePath,
  Value<String> fileName,
  Value<String> mediaType,
  Value<int?> durationMs,
  Value<int?> width,
  Value<int?> height,
  Value<int> fileSizeBytes,
  Value<String?> codec,
  Value<int?> bitrate,
  Value<String?> thumbnailPath,
  Value<int> importedAt,
  Value<int> rowid,
});

final class $$MediaAssetEntriesTableReferences extends BaseReferences<
    _$AppDatabase, $MediaAssetEntriesTable, MediaAssetEntry> {
  $$MediaAssetEntriesTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $ProjectEntriesTable _projectIdTable(_$AppDatabase db) =>
      db.projectEntries.createAlias($_aliasNameGenerator(
          db.mediaAssetEntries.projectId, db.projectEntries.id));

  $$ProjectEntriesTableProcessedTableManager get projectId {
    final $_column = $_itemColumn<String>('project_id')!;

    final manager = $$ProjectEntriesTableTableManager($_db, $_db.projectEntries)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_projectIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$MediaAssetEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $MediaAssetEntriesTable> {
  $$MediaAssetEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get filePath => $composableBuilder(
      column: $table.filePath, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get fileName => $composableBuilder(
      column: $table.fileName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get mediaType => $composableBuilder(
      column: $table.mediaType, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get durationMs => $composableBuilder(
      column: $table.durationMs, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get width => $composableBuilder(
      column: $table.width, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get height => $composableBuilder(
      column: $table.height, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get fileSizeBytes => $composableBuilder(
      column: $table.fileSizeBytes, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get codec => $composableBuilder(
      column: $table.codec, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get bitrate => $composableBuilder(
      column: $table.bitrate, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get thumbnailPath => $composableBuilder(
      column: $table.thumbnailPath, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get importedAt => $composableBuilder(
      column: $table.importedAt, builder: (column) => ColumnFilters(column));

  $$ProjectEntriesTableFilterComposer get projectId {
    final $$ProjectEntriesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.projectId,
        referencedTable: $db.projectEntries,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProjectEntriesTableFilterComposer(
              $db: $db,
              $table: $db.projectEntries,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$MediaAssetEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $MediaAssetEntriesTable> {
  $$MediaAssetEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get filePath => $composableBuilder(
      column: $table.filePath, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get fileName => $composableBuilder(
      column: $table.fileName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get mediaType => $composableBuilder(
      column: $table.mediaType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get durationMs => $composableBuilder(
      column: $table.durationMs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get width => $composableBuilder(
      column: $table.width, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get height => $composableBuilder(
      column: $table.height, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get fileSizeBytes => $composableBuilder(
      column: $table.fileSizeBytes,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get codec => $composableBuilder(
      column: $table.codec, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get bitrate => $composableBuilder(
      column: $table.bitrate, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get thumbnailPath => $composableBuilder(
      column: $table.thumbnailPath,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get importedAt => $composableBuilder(
      column: $table.importedAt, builder: (column) => ColumnOrderings(column));

  $$ProjectEntriesTableOrderingComposer get projectId {
    final $$ProjectEntriesTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.projectId,
        referencedTable: $db.projectEntries,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProjectEntriesTableOrderingComposer(
              $db: $db,
              $table: $db.projectEntries,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$MediaAssetEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MediaAssetEntriesTable> {
  $$MediaAssetEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  GeneratedColumn<String> get mediaType =>
      $composableBuilder(column: $table.mediaType, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
      column: $table.durationMs, builder: (column) => column);

  GeneratedColumn<int> get width =>
      $composableBuilder(column: $table.width, builder: (column) => column);

  GeneratedColumn<int> get height =>
      $composableBuilder(column: $table.height, builder: (column) => column);

  GeneratedColumn<int> get fileSizeBytes => $composableBuilder(
      column: $table.fileSizeBytes, builder: (column) => column);

  GeneratedColumn<String> get codec =>
      $composableBuilder(column: $table.codec, builder: (column) => column);

  GeneratedColumn<int> get bitrate =>
      $composableBuilder(column: $table.bitrate, builder: (column) => column);

  GeneratedColumn<String> get thumbnailPath => $composableBuilder(
      column: $table.thumbnailPath, builder: (column) => column);

  GeneratedColumn<int> get importedAt => $composableBuilder(
      column: $table.importedAt, builder: (column) => column);

  $$ProjectEntriesTableAnnotationComposer get projectId {
    final $$ProjectEntriesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.projectId,
        referencedTable: $db.projectEntries,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProjectEntriesTableAnnotationComposer(
              $db: $db,
              $table: $db.projectEntries,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$MediaAssetEntriesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $MediaAssetEntriesTable,
    MediaAssetEntry,
    $$MediaAssetEntriesTableFilterComposer,
    $$MediaAssetEntriesTableOrderingComposer,
    $$MediaAssetEntriesTableAnnotationComposer,
    $$MediaAssetEntriesTableCreateCompanionBuilder,
    $$MediaAssetEntriesTableUpdateCompanionBuilder,
    (MediaAssetEntry, $$MediaAssetEntriesTableReferences),
    MediaAssetEntry,
    PrefetchHooks Function({bool projectId})> {
  $$MediaAssetEntriesTableTableManager(
      _$AppDatabase db, $MediaAssetEntriesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MediaAssetEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MediaAssetEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MediaAssetEntriesTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> projectId = const Value.absent(),
            Value<String> filePath = const Value.absent(),
            Value<String> fileName = const Value.absent(),
            Value<String> mediaType = const Value.absent(),
            Value<int?> durationMs = const Value.absent(),
            Value<int?> width = const Value.absent(),
            Value<int?> height = const Value.absent(),
            Value<int> fileSizeBytes = const Value.absent(),
            Value<String?> codec = const Value.absent(),
            Value<int?> bitrate = const Value.absent(),
            Value<String?> thumbnailPath = const Value.absent(),
            Value<int> importedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MediaAssetEntriesCompanion(
            id: id,
            projectId: projectId,
            filePath: filePath,
            fileName: fileName,
            mediaType: mediaType,
            durationMs: durationMs,
            width: width,
            height: height,
            fileSizeBytes: fileSizeBytes,
            codec: codec,
            bitrate: bitrate,
            thumbnailPath: thumbnailPath,
            importedAt: importedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String projectId,
            required String filePath,
            required String fileName,
            required String mediaType,
            Value<int?> durationMs = const Value.absent(),
            Value<int?> width = const Value.absent(),
            Value<int?> height = const Value.absent(),
            Value<int> fileSizeBytes = const Value.absent(),
            Value<String?> codec = const Value.absent(),
            Value<int?> bitrate = const Value.absent(),
            Value<String?> thumbnailPath = const Value.absent(),
            required int importedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              MediaAssetEntriesCompanion.insert(
            id: id,
            projectId: projectId,
            filePath: filePath,
            fileName: fileName,
            mediaType: mediaType,
            durationMs: durationMs,
            width: width,
            height: height,
            fileSizeBytes: fileSizeBytes,
            codec: codec,
            bitrate: bitrate,
            thumbnailPath: thumbnailPath,
            importedAt: importedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$MediaAssetEntriesTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({projectId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (projectId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.projectId,
                    referencedTable:
                        $$MediaAssetEntriesTableReferences._projectIdTable(db),
                    referencedColumn: $$MediaAssetEntriesTableReferences
                        ._projectIdTable(db)
                        .id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$MediaAssetEntriesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $MediaAssetEntriesTable,
    MediaAssetEntry,
    $$MediaAssetEntriesTableFilterComposer,
    $$MediaAssetEntriesTableOrderingComposer,
    $$MediaAssetEntriesTableAnnotationComposer,
    $$MediaAssetEntriesTableCreateCompanionBuilder,
    $$MediaAssetEntriesTableUpdateCompanionBuilder,
    (MediaAssetEntry, $$MediaAssetEntriesTableReferences),
    MediaAssetEntry,
    PrefetchHooks Function({bool projectId})>;
typedef $$UserPreferencesTableCreateCompanionBuilder = UserPreferencesCompanion
    Function({
  required String key,
  required String value,
  Value<int> rowid,
});
typedef $$UserPreferencesTableUpdateCompanionBuilder = UserPreferencesCompanion
    Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $$UserPreferencesTableFilterComposer
    extends Composer<_$AppDatabase, $UserPreferencesTable> {
  $$UserPreferencesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnFilters(column));
}

class $$UserPreferencesTableOrderingComposer
    extends Composer<_$AppDatabase, $UserPreferencesTable> {
  $$UserPreferencesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnOrderings(column));
}

class $$UserPreferencesTableAnnotationComposer
    extends Composer<_$AppDatabase, $UserPreferencesTable> {
  $$UserPreferencesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$UserPreferencesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $UserPreferencesTable,
    UserPreference,
    $$UserPreferencesTableFilterComposer,
    $$UserPreferencesTableOrderingComposer,
    $$UserPreferencesTableAnnotationComposer,
    $$UserPreferencesTableCreateCompanionBuilder,
    $$UserPreferencesTableUpdateCompanionBuilder,
    (
      UserPreference,
      BaseReferences<_$AppDatabase, $UserPreferencesTable, UserPreference>
    ),
    UserPreference,
    PrefetchHooks Function()> {
  $$UserPreferencesTableTableManager(
      _$AppDatabase db, $UserPreferencesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UserPreferencesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UserPreferencesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UserPreferencesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              UserPreferencesCompanion(
            key: key,
            value: value,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String key,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) =>
              UserPreferencesCompanion.insert(
            key: key,
            value: value,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$UserPreferencesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $UserPreferencesTable,
    UserPreference,
    $$UserPreferencesTableFilterComposer,
    $$UserPreferencesTableOrderingComposer,
    $$UserPreferencesTableAnnotationComposer,
    $$UserPreferencesTableCreateCompanionBuilder,
    $$UserPreferencesTableUpdateCompanionBuilder,
    (
      UserPreference,
      BaseReferences<_$AppDatabase, $UserPreferencesTable, UserPreference>
    ),
    UserPreference,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ProjectEntriesTableTableManager get projectEntries =>
      $$ProjectEntriesTableTableManager(_db, _db.projectEntries);
  $$MediaAssetEntriesTableTableManager get mediaAssetEntries =>
      $$MediaAssetEntriesTableTableManager(_db, _db.mediaAssetEntries);
  $$UserPreferencesTableTableManager get userPreferences =>
      $$UserPreferencesTableTableManager(_db, _db.userPreferences);
}
