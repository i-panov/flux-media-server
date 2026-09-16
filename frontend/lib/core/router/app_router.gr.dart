// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

part of 'app_router.dart';

/// generated route for
/// [ArtistPage]
class ArtistRoute extends PageRouteInfo<ArtistRouteArgs> {
  ArtistRoute({
    required int artistId,
    required String artistName,
    Key? key,
    List<PageRouteInfo>? children,
  }) : super(
         ArtistRoute.name,
         args: ArtistRouteArgs(
           artistId: artistId,
           artistName: artistName,
           key: key,
         ),
         initialChildren: children,
       );

  static const String name = 'ArtistRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<ArtistRouteArgs>();
      return ArtistPage(
        artistId: args.artistId,
        artistName: args.artistName,
        key: args.key,
      );
    },
  );
}

class ArtistRouteArgs {
  const ArtistRouteArgs({
    required this.artistId,
    required this.artistName,
    this.key,
  });

  final int artistId;

  final String artistName;

  final Key? key;

  @override
  String toString() {
    return 'ArtistRouteArgs{artistId: $artistId, artistName: $artistName, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ArtistRouteArgs) return false;
    return artistId == other.artistId &&
        artistName == other.artistName &&
        key == other.key;
  }

  @override
  int get hashCode => artistId.hashCode ^ artistName.hashCode ^ key.hashCode;
}

/// generated route for
/// [AudioPlayerScreen]
class AudioPlayerRoute extends PageRouteInfo<AudioPlayerRouteArgs> {
  AudioPlayerRoute({
    required Media media,
    Key? key,
    List<PageRouteInfo>? children,
  }) : super(
         AudioPlayerRoute.name,
         args: AudioPlayerRouteArgs(media: media, key: key),
         initialChildren: children,
       );

  static const String name = 'AudioPlayerRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<AudioPlayerRouteArgs>();
      return AudioPlayerScreen(media: args.media, key: args.key);
    },
  );
}

class AudioPlayerRouteArgs {
  const AudioPlayerRouteArgs({required this.media, this.key});

  final Media media;

  final Key? key;

  @override
  String toString() {
    return 'AudioPlayerRouteArgs{media: $media, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AudioPlayerRouteArgs) return false;
    return media == other.media && key == other.key;
  }

  @override
  int get hashCode => media.hashCode ^ key.hashCode;
}

/// generated route for
/// [AudioScreen]
class AudioRoute extends PageRouteInfo<void> {
  const AudioRoute({List<PageRouteInfo>? children})
    : super(AudioRoute.name, initialChildren: children);

  static const String name = 'AudioRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const AudioScreen();
    },
  );
}

/// generated route for
/// [CodeScreen]
class CodeRoute extends PageRouteInfo<CodeRouteArgs> {
  CodeRoute({required String email, Key? key, List<PageRouteInfo>? children})
    : super(
        CodeRoute.name,
        args: CodeRouteArgs(email: email, key: key),
        initialChildren: children,
      );

  static const String name = 'CodeRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<CodeRouteArgs>();
      return CodeScreen(email: args.email, key: args.key);
    },
  );
}

class CodeRouteArgs {
  const CodeRouteArgs({required this.email, this.key});

  final String email;

  final Key? key;

  @override
  String toString() {
    return 'CodeRouteArgs{email: $email, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CodeRouteArgs) return false;
    return email == other.email && key == other.key;
  }

  @override
  int get hashCode => email.hashCode ^ key.hashCode;
}

/// generated route for
/// [CollectionDetailScreen]
class CollectionDetailRoute extends PageRouteInfo<CollectionDetailRouteArgs> {
  CollectionDetailRoute({
    required Collection collection,
    Key? key,
    List<PageRouteInfo>? children,
  }) : super(
         CollectionDetailRoute.name,
         args: CollectionDetailRouteArgs(collection: collection, key: key),
         initialChildren: children,
       );

  static const String name = 'CollectionDetailRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<CollectionDetailRouteArgs>();
      return CollectionDetailScreen(collection: args.collection, key: args.key);
    },
  );
}

class CollectionDetailRouteArgs {
  const CollectionDetailRouteArgs({required this.collection, this.key});

  final Collection collection;

  final Key? key;

  @override
  String toString() {
    return 'CollectionDetailRouteArgs{collection: $collection, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CollectionDetailRouteArgs) return false;
    return collection == other.collection && key == other.key;
  }

  @override
  int get hashCode => collection.hashCode ^ key.hashCode;
}

/// generated route for
/// [LoginScreen]
class LoginRoute extends PageRouteInfo<void> {
  const LoginRoute({List<PageRouteInfo>? children})
    : super(LoginRoute.name, initialChildren: children);

  static const String name = 'LoginRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const LoginScreen();
    },
  );
}

/// generated route for
/// [MainRoutePage]
class MainRoute extends PageRouteInfo<void> {
  const MainRoute({List<PageRouteInfo>? children})
    : super(MainRoute.name, initialChildren: children);

  static const String name = 'MainRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const MainRoutePage();
    },
  );
}

/// generated route for
/// [ServerSetupScreen]
class ServerSetupRoute extends PageRouteInfo<void> {
  const ServerSetupRoute({List<PageRouteInfo>? children})
    : super(ServerSetupRoute.name, initialChildren: children);

  static const String name = 'ServerSetupRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const ServerSetupScreen();
    },
  );
}

/// generated route for
/// [SettingsScreen]
class SettingsRoute extends PageRouteInfo<void> {
  const SettingsRoute({List<PageRouteInfo>? children})
    : super(SettingsRoute.name, initialChildren: children);

  static const String name = 'SettingsRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const SettingsScreen();
    },
  );
}

/// generated route for
/// [UploadScreen]
class UploadRoute extends PageRouteInfo<UploadRouteArgs> {
  UploadRoute({
    required String mediaType,
    Key? key,
    List<PageRouteInfo>? children,
  }) : super(
         UploadRoute.name,
         args: UploadRouteArgs(mediaType: mediaType, key: key),
         initialChildren: children,
       );

  static const String name = 'UploadRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<UploadRouteArgs>();
      return UploadScreen(mediaType: args.mediaType, key: args.key);
    },
  );
}

class UploadRouteArgs {
  const UploadRouteArgs({required this.mediaType, this.key});

  final String mediaType;

  final Key? key;

  @override
  String toString() {
    return 'UploadRouteArgs{mediaType: $mediaType, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! UploadRouteArgs) return false;
    return mediaType == other.mediaType && key == other.key;
  }

  @override
  int get hashCode => mediaType.hashCode ^ key.hashCode;
}

/// generated route for
/// [VideoDetailScreen]
class VideoDetailRoute extends PageRouteInfo<VideoDetailRouteArgs> {
  VideoDetailRoute({
    required int mediaId,
    Key? key,
    List<PageRouteInfo>? children,
  }) : super(
         VideoDetailRoute.name,
         args: VideoDetailRouteArgs(mediaId: mediaId, key: key),
         initialChildren: children,
       );

  static const String name = 'VideoDetailRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<VideoDetailRouteArgs>();
      return VideoDetailScreen(mediaId: args.mediaId, key: args.key);
    },
  );
}

class VideoDetailRouteArgs {
  const VideoDetailRouteArgs({required this.mediaId, this.key});

  final int mediaId;

  final Key? key;

  @override
  String toString() {
    return 'VideoDetailRouteArgs{mediaId: $mediaId, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! VideoDetailRouteArgs) return false;
    return mediaId == other.mediaId && key == other.key;
  }

  @override
  int get hashCode => mediaId.hashCode ^ key.hashCode;
}

/// generated route for
/// [VideoScreen]
class VideoRoute extends PageRouteInfo<void> {
  const VideoRoute({List<PageRouteInfo>? children})
    : super(VideoRoute.name, initialChildren: children);

  static const String name = 'VideoRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const VideoScreen();
    },
  );
}
