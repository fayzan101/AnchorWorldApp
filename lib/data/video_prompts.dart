/// Community-safe prompts for active voice/video calls.
class VideoPrompts {
  VideoPrompts._();

  static const List<String> community = [
    'What circle have you been most active in lately?',
    'What’s a hobby you’re exploring right now?',
    'Share a favorite spot in your city.',
    'What tip would you give a newcomer in your circle?',
    'What’s a post you saw recently that stuck with you?',
    'How do you usually take part — posting, chatting, or organizing?',
    'What’s one community goal you’re working toward?',
    'Recommend a book, show, or playlist for someone in your circle.',
    'What’s a local activity you’d invite a connection to?',
    'What brought you to Anchor World originally?',
    'What’s something practical you learned from the community?',
    'If you hosted a circle meetup, what would it be about?',
  ];

  static String atIndex(int index) {
    if (community.isEmpty) return 'Share something about your community.';
    return community[index % community.length];
  }
}
