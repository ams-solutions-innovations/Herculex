import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/router/router.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/features/friends/domain/friend_invite_payload.dart';

/// The app route a `herculex://` link opens, or null for links the app does
/// not handle (the Supabase auth callback is supabase_flutter's own business).
String? routeForDeepLink(Uri uri) {
  if (FriendInvitePayload.tryDecode(uri.toString()) case final invite?) {
    return AppPaths.friendInvite(invite.token);
  }
  return null;
}

/// Watched once from the app root. `uriLinkStream` also delivers the link
/// that cold-started the app, so there is no separate initial-link path.
final deepLinkListenerProvider = Provider<void>((ref) {
  final sub = AppLinks().uriLinkStream.listen(
    (uri) {
      final route = routeForDeepLink(uri);
      if (route == null) return;
      final router = ref.read(routerProvider)..go(AppRoutes.app);
      unawaited(router.push(route));
    },
    // A malformed link must not take the listener down with it.
    onError: (Object _) {},
  );
  ref.onDispose(sub.cancel);
});
