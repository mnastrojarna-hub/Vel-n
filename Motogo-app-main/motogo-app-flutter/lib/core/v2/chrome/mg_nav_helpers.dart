import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Route of the AI assistant (= `Routes.aiAgent`, kept here so v2 chrome
/// does not import the whole router).
const String kV2AiAgentRoute = '/ai-agent';

/// Route of Zprávy (= `Routes.messages`).
const String kV2MessagesRoute = '/messages';

/// Same rule as `BuildContext.pushOrGo` in router.dart: push when the top
/// page is inside the shell, `go` when a page OUTSIDE the shell is on top
/// (a push would duplicate the shell in go_router 13). No router → no-op.
void mgPushOrGo(BuildContext context, String location) {
  final GoRouter? router = GoRouter.maybeOf(context);
  if (router == null) return;
  var topInShell = true;
  try {
    topInShell = router.routerDelegate.currentConfiguration.matches.last is ShellRouteMatch;
  } catch (_) {}
  if (topInShell) {
    router.push(location);
  } else {
    router.go(location);
  }
}
