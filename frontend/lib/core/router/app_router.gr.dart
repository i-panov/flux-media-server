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
          key: args.key,
          artistName: args.artistName,
        ),
      );
    },
    AudioPlayerRoute.name: (routeData) {
      final args = routeData.argsAs<AudioPlayerRouteArgs>();
      return AutoRoutePage<dynamic>(
        routeData: routeData,
        child: AudioPlayerScreen(
          key: args.key,
          media: args.media,
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
          key: args.key,
          email: args.email,
          debugCode: args.debugCode,
        ),
      );
    },
    CollectionDetailRoute.name: (routeData) {
      final args = routeData.argsAs<CollectionDetailRouteArgs>();
      return AutoRoutePage<dynamic>(
        routeData: routeData,
        child: CollectionDetailScreen(
          key: args.key,
          collection: args.collection,
        ),
      );
    },
    DownloadsRoute.name: (routeData) {
      return AutoRoutePage<dynamic>(
        routeData: routeData,
        child: const DownloadsScreen(),
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
          key: args.key,
          mediaId: args.mediaId,
        ),
      );
    },
    PlayerRoute.name: (routeData) {
      final args = routeData.argsAs<PlayerRouteArgs>();
      return AutoRoutePage<dynamic>(
        routeData: routeData,
        child: PlayerScreen(
          key: args.key,
          media: args.media,
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
          key: args.key,
          mediaType: args.mediaType,
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
    Key? key,
    required String artistName,
    List<PageRouteInfo>? children,
  }) : super(
          ArtistRoute.name,
          args: ArtistRouteArgs(
            key: key,
            artistName: artistName,
          ),
          initialChildren: children,
        );

  static const String name = 'ArtistRoute';

  static const PageInfo<ArtistRouteArgs> page = PageInfo<ArtistRouteArgs>(name);
}

class ArtistRouteArgs {
  const ArtistRouteArgs({
    this.key,
    required this.artistName,
  });

  final Key? key;

  final String artistName;

  @override
  String toString() {
    return 'ArtistRouteArgs{key: $key, artistName: $artistName}';
  }
}

/// generated route for
/// [AudioPlayerScreen]
class AudioPlayerRoute extends PageRouteInfo<AudioPlayerRouteArgs> {
  AudioPlayerRoute({
    Key? key,
    required Media media,
    List<PageRouteInfo>? children,
  }) : super(
          AudioPlayerRoute.name,
          args: AudioPlayerRouteArgs(
            key: key,
            media: media,
          ),
          initialChildren: children,
        );

  static const String name = 'AudioPlayerRoute';

  static const PageInfo<AudioPlayerRouteArgs> page =
      PageInfo<AudioPlayerRouteArgs>(name);
}

class AudioPlayerRouteArgs {
  const AudioPlayerRouteArgs({
    this.key,
    required this.media,
  });

  final Key? key;

  final Media media;

  @override
  String toString() {
    return 'AudioPlayerRouteArgs{key: $key, media: $media}';
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
    Key? key,
    required String email,
    String? debugCode,
    List<PageRouteInfo>? children,
  }) : super(
          CodeRoute.name,
          args: CodeRouteArgs(
            key: key,
            email: email,
            debugCode: debugCode,
          ),
          initialChildren: children,
        );

  static const String name = 'CodeRoute';

  static const PageInfo<CodeRouteArgs> page = PageInfo<CodeRouteArgs>(name);
}

class CodeRouteArgs {
  const CodeRouteArgs({
    this.key,
    required this.email,
    this.debugCode,
  });

  final Key? key;

  final String email;

  final String? debugCode;

  @override
  String toString() {
    return 'CodeRouteArgs{key: $key, email: $email, debugCode: $debugCode}';
  }
}

/// generated route for
/// [CollectionDetailScreen]
class CollectionDetailRoute extends PageRouteInfo<CollectionDetailRouteArgs> {
  CollectionDetailRoute({
    Key? key,
    required Collection collection,
    List<PageRouteInfo>? children,
  }) : super(
          CollectionDetailRoute.name,
          args: CollectionDetailRouteArgs(
            key: key,
            collection: collection,
          ),
          initialChildren: children,
        );

  static const String name = 'CollectionDetailRoute';

  static const PageInfo<CollectionDetailRouteArgs> page =
      PageInfo<CollectionDetailRouteArgs>(name);
}

class CollectionDetailRouteArgs {
  const CollectionDetailRouteArgs({
    this.key,
    required this.collection,
  });

  final Key? key;

  final Collection collection;

  @override
  String toString() {
    return 'CollectionDetailRouteArgs{key: $key, collection: $collection}';
  }
}

/// generated route for
/// [DownloadsScreen]
class DownloadsRoute extends PageRouteInfo<void> {
  const DownloadsRoute({List<PageRouteInfo>? children})
      : super(
          DownloadsRoute.name,
          initialChildren: children,
        );

  static const String name = 'DownloadsRoute';

  static const PageInfo<void> page = PageInfo<void>(name);
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
    Key? key,
    required int mediaId,
    List<PageRouteInfo>? children,
  }) : super(
          MediaDetailRoute.name,
          args: MediaDetailRouteArgs(
            key: key,
            mediaId: mediaId,
          ),
          initialChildren: children,
        );

  static const String name = 'MediaDetailRoute';

  static const PageInfo<MediaDetailRouteArgs> page =
      PageInfo<MediaDetailRouteArgs>(name);
}

class MediaDetailRouteArgs {
  const MediaDetailRouteArgs({
    this.key,
    required this.mediaId,
  });

  final Key? key;

  final int mediaId;

  @override
  String toString() {
    return 'MediaDetailRouteArgs{key: $key, mediaId: $mediaId}';
  }
}

/// generated route for
/// [PlayerScreen]
class PlayerRoute extends PageRouteInfo<PlayerRouteArgs> {
  PlayerRoute({
    Key? key,
    required Media media,
    List<PageRouteInfo>? children,
  }) : super(
          PlayerRoute.name,
          args: PlayerRouteArgs(
            key: key,
            media: media,
          ),
          initialChildren: children,
        );

  static const String name = 'PlayerRoute';

  static const PageInfo<PlayerRouteArgs> page = PageInfo<PlayerRouteArgs>(name);
}

class PlayerRouteArgs {
  const PlayerRouteArgs({
    this.key,
    required this.media,
  });

  final Key? key;

  final Media media;

  @override
  String toString() {
    return 'PlayerRouteArgs{key: $key, media: $media}';
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
    Key? key,
    required String mediaType,
    List<PageRouteInfo>? children,
  }) : super(
          UploadRoute.name,
          args: UploadRouteArgs(
            key: key,
            mediaType: mediaType,
          ),
          initialChildren: children,
        );

  static const String name = 'UploadRoute';

  static const PageInfo<UploadRouteArgs> page = PageInfo<UploadRouteArgs>(name);
}

class UploadRouteArgs {
  const UploadRouteArgs({
    this.key,
    required this.mediaType,
  });

  final Key? key;

  final String mediaType;

  @override
  String toString() {
    return 'UploadRouteArgs{key: $key, mediaType: $mediaType}';
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
