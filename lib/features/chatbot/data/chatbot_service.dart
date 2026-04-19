import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/gemini_config.dart';
import '../domain/message_model.dart';

class ChatbotService {
  final List<Map<String, String>> _history = [];

  Future<void> resetSession() async {
    _history.clear();
  }

  Future<ChatbotMessage> sendMessage(String message) async {
    try {
      _history.add({'role': 'user', 'content': message});

      // Keep only last 6 messages to save tokens
      final recentHistory = _history.length > 6
          ? _history.sublist(_history.length - 6)
          : _history;

      final response = await http.post(
        Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${GeminiConfig.apiKey}',
        },
        body: jsonEncode({
          'model': GeminiConfig.modelName,
          'messages': [
            {'role': 'system', 'content': GeminiConfig.systemPrompt},
            ...recentHistory,
          ],
          'max_tokens': 200,
          'temperature': 0.7,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text = data['choices'][0]['message']['content'];

        _history.add({'role': 'assistant', 'content': text});

        return ChatbotMessage(
          text: text,
          isUser: false,
          timestamp: DateTime.now(),
        );
      } else {
        debugPrint('Groq error: ${response.body}');
        throw Exception('API error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error sending message: $e');
      return ChatbotMessage(
        text: 'Am Slouma is resting right now 😴 Please try again in a moment!',
        isUser: false,
        timestamp: DateTime.now(),
      );
    }
  }
}