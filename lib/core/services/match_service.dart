import 'package:dating_app/data/models/users/user_model.dart';

class MatchService {
  static const List<String> profilePhotoOptions = [
    'https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&w=900&q=80',
    'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?auto=format&fit=crop&w=900&q=80',
    'https://images.unsplash.com/photo-1517841905240-472988babdf9?auto=format&fit=crop&w=900&q=80',
    'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?auto=format&fit=crop&w=900&q=80',
    'https://images.unsplash.com/photo-1488426862026-3ee34a7d66df?auto=format&fit=crop&w=900&q=80',
    'https://images.unsplash.com/photo-1546961329-78bef0414d7c?auto=format&fit=crop&w=900&q=80',
    'https://images.unsplash.com/photo-1521119989659-a83eee488004?auto=format&fit=crop&w=900&q=80',
    'https://images.unsplash.com/photo-1521572267360-ee0c2909d518?auto=format&fit=crop&w=900&q=80',
  ];

  static const List<String> availableInterests = [
    'Art',
    'Travel',
    'Music',
    'Tech',
    'Nature',
    'Cooking',
    'Fitness',
    'Reading',
    'Photography',
    'Movies',
    'Running',
    'Design',
    'Coffee',
    'Wellness',
    'Gaming',
    'Dogs',
  ];

  Future<List<User>> getDiscoverableUsers() async {
    await Future.delayed(const Duration(milliseconds: 250));

    return const [
      User(
        id: 'emma',
        name: 'Emma',
        age: 26,
        photoUrl:
            'https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&w=900&q=80',
        bio:
            'Brand designer, pilates regular, and always planning a weekend escape.',
        distance: 2.3,
        interests: ['Art', 'Travel', 'Coffee'],
        likesYou: true,
      ),
      User(
        id: 'james',
        name: 'James',
        age: 29,
        photoUrl:
            'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?auto=format&fit=crop&w=900&q=80',
        bio:
            'Product builder by day, trail runner by sunrise, pasta loyalist always.',
        distance: 4.1,
        interests: ['Tech', 'Running', 'Cooking'],
      ),
      User(
        id: 'zoe',
        name: 'Zoe',
        age: 24,
        photoUrl:
            'https://images.unsplash.com/photo-1517841905240-472988babdf9?auto=format&fit=crop&w=900&q=80',
        bio:
            'Med student with a soft spot for bookstores, matcha, and long voice notes.',
        distance: 1.2,
        interests: ['Reading', 'Wellness', 'Music'],
        likesYou: true,
      ),
      User(
        id: 'liam',
        name: 'Liam',
        age: 31,
        photoUrl:
            'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?auto=format&fit=crop&w=900&q=80',
        bio:
            'Architect, amateur chef, and the friend who always knows the next good spot.',
        distance: 5.7,
        interests: ['Design', 'Cooking', 'Travel'],
      ),
      User(
        id: 'maya',
        name: 'Maya',
        age: 27,
        photoUrl:
            'https://images.unsplash.com/photo-1488426862026-3ee34a7d66df?auto=format&fit=crop&w=900&q=80',
        bio:
            'Photographer chasing clean light, live gigs, and strong iced coffee.',
        distance: 3.4,
        interests: ['Photography', 'Music', 'Coffee'],
      ),
      User(
        id: 'noah',
        name: 'Noah',
        age: 28,
        photoUrl:
            'https://images.unsplash.com/photo-1521119989659-a83eee488004?auto=format&fit=crop&w=900&q=80',
        bio:
            'Startup operator, dog uncle, and big believer in last-minute road trips.',
        distance: 6.2,
        interests: ['Dogs', 'Tech', 'Nature'],
        likesYou: true,
      ),
      User(
        id: 'ava',
        name: 'Ava',
        age: 25,
        photoUrl:
            'https://images.unsplash.com/photo-1546961329-78bef0414d7c?auto=format&fit=crop&w=900&q=80',
        bio:
            'Ceramics, film nights, and beach mornings. Looking for easy chemistry.',
        distance: 2.8,
        interests: ['Art', 'Movies', 'Nature'],
      ),
      User(
        id: 'elijah',
        name: 'Elijah',
        age: 30,
        photoUrl:
            'https://images.unsplash.com/photo-1521572267360-ee0c2909d518?auto=format&fit=crop&w=900&q=80',
        bio:
            'Guitar player, designer, and loyal fan of quiet dinners over loud bars.',
        distance: 4.8,
        interests: ['Music', 'Design', 'Reading'],
      ),
    ];
  }

  User createCurrentUser() {
    return User(
      id: 'current-user',
      name: 'Luna',
      age: 27,
      photoUrl: profilePhotoOptions.first,
      bio:
          'UX designer, coffee optimist, and always up for a rooftop sunset or a road trip.',
      distance: 12,
      interests: const ['Design', 'Travel', 'Coffee', 'Music'],
    );
  }

  bool shouldCreateMatch(User user, {bool isSuperLike = false}) {
    return isSuperLike || user.likesYou;
  }

  Future<void> simulateWrite() async {
    await Future.delayed(const Duration(milliseconds: 140));
  }
}
