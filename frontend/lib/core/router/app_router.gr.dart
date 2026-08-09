// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

part of 'app_router.dart';

abstract class _$AppRouter extends RootStackRouter {
  // ignore: unused_element
  _$AppRouter({super.navigatorKey});

  @override
  final Map<String, PageFactory> pagesMap = {
    ArtistRoute.name: (routeData) {
      final args = routeData.argsAs<ArtistRouteArgs>();
      return AutoRoutePage<dynamic>(
        routeData: routeData,
        child: ArtistPage(
          artistId: args.artistId,
          artistName: args.artistName,
          key: args.key,
        ),
      );
    },
    AudioPlayerRoute.name: (routeData) {
      final args = routeData.argsAs<AudioPlayerRouteArgs>();
      return AutoRoutePage<dynamic>(
        routeData: routeData,
        child: AudioPlayerScreen(
          media: args.media,
          key: args.key,
        ),
      );
    },
    AudioRoute.name: (routeData) {
      return AutoRoutePage<dynamic>(
        routeData: routeData,
        child: const AudioScreen(),
      );
    },
    CodeRoute.name: (routeData) {
      final args = routeData.argsAs<CodeRouteArgs>();
      return AutoRoutePage<dynamic>(
        routeData: routeData,
        child: CodeScreen(
          email: args.email,
          key: args.key,
          debugCode: args.debugCode,
        ),
      );
    },
    CollectionDetailRoute.name: (routeData) {
      final args = routeData.argsAs<CollectionDetailRouteArgs>();
      return AutoRoutePage<dynamic>(
        routeData: routeData,
        child: CollectionDetailScreen(
          collection: args.collection,
          key: args.key,
        ),
      );
    },
    LoginRoute.name: (routeData) {
      return AutoRoutePage<dynamic>(
        routeData: routeData,
        child: const LoginScreen(),
      );
    },
    MainRoute.name: (routeData) {
      return AutoRoutePage<dynamic>(
        routeData: routeData,
        child: const MainScreen(),
      );
    },
    MediaDetailRoute.name: (routeData) {
      final args = routeData.argsAs<MediaDetailRouteArgs>();
      return AutoRoutePage<dynamic>(
        routeData: routeData,
        child: MediaDetailScreen(
          mediaId: args.mediaId,
          key: args.key,
        ),
      );
    },
    PlayerRoute.name: (routeData) {
      final args = routeData.argsAs<PlayerRouteArgs>();
      return AutoRoutePage<dynamic>(
        routeData: routeData,
        child: PlayerScreen(
          media: args.media,
          key: args.key,
        ),
      );
    },
    ServerSetupRoute.name: (routeData) {
      return AutoRoutePage<dynamic>(
        routeData: routeData,
        child: const ServerSetupScreen(),
      );
    },
    SettingsRoute.name: (routeData) {
      return AutoRoutePage<dynamic>(
        routeData: routeData,
        child: const SettingsScreen(),
      );
    },
    UploadRoute.name: (routeData) {
      final args = routeData.argsAs<UploadRouteArgs>();
      return AutoRoutePage<dynamic>(
        routeData: routeData,
        child: UploadScreen(
          mediaType: args.mediaType,
          key: args.key,
        ),
      );
    },
    VideoRoute.name: (routeData) {
      return AutoRoutePage<dynamic>(
        routeData: routeData,
        child: const VideoScreen(),
      );
    },
  };
}

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

  static const PageInfo<ArtistRouteArgs> page = PageInfo<ArtistRouteArgs>(name);
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
          args: AudioPlayerRouteArgs(
            media: media,
            key: key,
          ),
          initialChildren: children,
        );

  static const String name = 'AudioPlayerRoute';

  static const PageInfo<AudioPlayerRouteArgs> page =
      PageInfo<AudioPlayerRouteArgs>(name);
}

class AudioPlayerRouteArgs {
  const AudioPlayerRouteArgs({
    required this.media,
    this.key,
  });

  final Media media;

  final Key? key;

  @override
  String toString() {
    return 'AudioPlayerRouteArgs{media: $media, key: $key}';
  }
}

/// generated route for
/// [AudioScreen]
class AudioRoute extends PageRouteInfo<void> {
  const AudioRoute({List<PageRouteInfo>? children})
      : super(
          AudioRoute.name,
          initialChildren: children,
        );

  static const String name = 'AudioRoute';

  static const PageInfo<void> page = PageInfo<void>(name);
}

/// generated route for
/// [CodeScreen]
class CodeRoute extends PageRouteInfo<CodeRouteArgs> {
  CodeRoute({
    required String email,
    Key? key,
    String? debugCode,
    List<PageRouteInfo>? children,
  }) : super(
          CodeRoute.name,
          args: CodeRouteArgs(
            email: email,
            key: key,
            debugCode: debugCode,
          ),
          initialChildren: children,
        );

  static const String name = 'CodeRoute';

  static const PageInfo<CodeRouteArgs> page = PageInfo<CodeRouteArgs>(name);
}

class CodeRouteArgs {
  const CodeRouteArgs({
    required this.email,
    this.key,
    this.debugCode,
  });

  final String email;

  final Key? key;

  final String? debugCode;

  @override
  String toString() {
    return 'CodeRouteArgs{email: $email, key: $key, debugCode: $debugCode}';
  }
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
          args: CollectionDetailRouteArgs(
            collection: collection,
            key: key,
          ),
          initialChildren: children,
        );

  static const String name = 'CollectionDetailRoute';

  static const PageInfo<CollectionDetailRouteArgs> page =
      PageInfo<CollectionDetailRouteArgs>(name);
}

class CollectionDetailRouteArgs {
  const CollectionDetailRouteArgs({
    required this.collection,
    this.key,
  });

  final Collection collection;

  final Key? key;

  @override
  String toString() {
    return 'CollectionDetailRouteArgs{collection: $collection, key: $key}';
  }
}

/// generated route for
/// [LoginScreen]
class LoginRoute extends PageRouteInfo<void> {
  const LoginRoute({List<PageRouteInfo>? children})
      : super(
          LoginRoute.name,
          initialChildren: children,
        );

  static const String name = 'LoginRoute';

  static const PageInfo<void> page = PageInfo<void>(name);
}

/// generated route for
/// [MainScreen]
class MainRoute extends PageRouteInfo<void> {
  const MainRoute({List<PageRouteInfo>? children})
      : super(
          MainRoute.name,
          initialChildren: children,
        );

  static const String name = 'MainRoute';

  static const PageInfo<void> page = PageInfo<void>(name);
}

/// generated route for
/// [MediaDetailScreen]
class MediaDetailRoute extends PageRouteInfo<MediaDetailRouteArgs> {
  MediaDetailRoute({
    required int mediaId,
    Key? key,
    List<PageRouteInfo>? children,
  }) : super(
          MediaDetailRoute.name,
          args: MediaDetailRouteArgs(
            mediaId: mediaId,
            key: key,
          ),
          initialChildren: children,
        );

  static const String name = 'MediaDetailRoute';

  static const PageInfo<MediaDetailRouteArgs> page =
      PageInfo<MediaDetailRouteArgs>(name);
}

class MediaDetailRouteArgs {
  const MediaDetailRouteArgs({
    required this.mediaId,
    this.key,
  });

  final int mediaId;

  final Key? key;

  @override
  String toString() {
    return 'MediaDetailRouteArgs{mediaId: $mediaId, key: $key}';
  }
}

/// generated route for
/// [PlayerScreen]
class PlayerRoute extends PageRouteInfo<PlayerRouteArgs> {
  PlayerRoute({
    required Media media,
    Key? key,
    List<PageRouteInfo>? children,
  }) : super(
          PlayerRoute.name,
          args: PlayerRouteArgs(
            media: media,
            key: key,
          ),
          initialChildren: children,
        );

  static const String name = 'PlayerRoute';

  static const PageInfo<PlayerRouteArgs> page = PageInfo<PlayerRouteArgs>(name);
}

class PlayerRouteArgs {
  const PlayerRouteArgs({
    required this.media,
    this.key,
  });

  final Media media;

  final Key? key;

  @override
  String toString() {
    return 'PlayerRouteArgs{media: $media, key: $key}';
  }
}

/// generated route for
/// [ServerSetupScreen]
class ServerSetupRoute extends PageRouteInfo<void> {
  const ServerSetupRoute({List<PageRouteInfo>? children})
      : super(
          ServerSetupRoute.name,
          initialChildren: children,
        );

  static const String name = 'ServerSetupRoute';

  static const PageInfo<void> page = PageInfo<void>(name);
}

/// generated route for
/// [SettingsScreen]
class SettingsRoute extends PageRouteInfo<void> {
  const SettingsRoute({List<PageRouteInfo>? children})
      : super(
          SettingsRoute.name,
          initialChildren: children,
        );

  static const String name = 'SettingsRoute';

  static const PageInfo<void> page = PageInfo<void>(name);
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
          args: UploadRouteArgs(
            mediaType: mediaType,
            key: key,
          ),
          initialChildren: children,
        );

  static const String name = 'UploadRoute';

  static const PageInfo<UploadRouteArgs> page = PageInfo<UploadRouteArgs>(name);
}

class UploadRouteArgs {
  const UploadRouteArgs({
    required this.mediaType,
    this.key,
  });

  final String mediaType;

  final Key? key;

  @override
  String toString() {
    return 'UploadRouteArgs{mediaType: $mediaType, key: $key}';
  }
}

/// generated route for
/// [VideoScreen]
class VideoRoute extends PageRouteInfo<void> {
  const VideoRoute({List<PageRouteInfo>? children})
      : super(
          VideoRoute.name,
          initialChildren: children,
        );

  static const String name = 'VideoRoute';

  static const PageInfo<void> page = PageInfo<void>(name);
}
