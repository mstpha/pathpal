import 'package:flutter_riverpod/flutter_riverpod.dart';

class PostNotificationState {
  final int? postId;
  final String? postType;
  final bool handled;

  PostNotificationState({this.postId, this.postType, this.handled = false});
}

final postNotificationProvider =
    StateProvider<PostNotificationState>((ref) => PostNotificationState());