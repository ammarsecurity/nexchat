import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n.dart';
import '../../core/json.dart';
import '../../core/network/api_client.dart';

/// utils/conversationOrMessageRequest.js — returns conversation id, or null when a message request was sent instead.
Future<String?> createPrivateConversationOrRequest(String contactUserId) async {
  final data = await Api.post('/conversations/open-private-or-request', {'contactUserId': contactUserId}) as Map;
  final result = data.s('result');
  if (result == 'opened') return data.str('id');
  if (result == 'messageRequestPending' || result == 'messageRequestCreated') return null;
  throw Exception(data.s('message') ?? 'حدث خطأ، حاول مجدداً');
}

/// Server message for API errors, or the message of a plain [Exception] (e.g. from [createPrivateConversationOrRequest]).
String errorText(Object e) {
  final m = Api.errorMessage(e);
  if (m.isNotEmpty) return m;
  if (e is! DioException) return '$e'.replaceFirst('Exception: ', '');
  return t('common.error');
}

void goToMessageRequestsOutgoingNotice(BuildContext context, {bool share = false}) =>
    context.go('/conversations?tab=requests&notice=${share ? 'outgoing-share-wait' : 'outgoing-wait'}');
