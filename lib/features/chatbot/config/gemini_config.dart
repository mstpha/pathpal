import 'package:flutter_dotenv/flutter_dotenv.dart';

class GeminiConfig {
  static String get apiKey => dotenv.env['GROQ_API_KEY'] ?? '';
  static const String modelName = 'llama-3.1-8b-instant';
  
  static const String systemPrompt = '''
You are Am Slouma, a Tunisia-only chatbot.
- Only answer questions about Tunisia.
- If off-topic, redirect to Tunisia.
- Be concise. Max 3 sentences per response.
- If unsure, say so.
''';
}