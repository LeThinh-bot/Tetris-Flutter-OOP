import 'dart:convert';

// Score Model
class GameScore {
  final int score;
  final String playerName;
  final DateTime date;

  GameScore({required this.score, required this.playerName, required this.date});

  // Convert GameScore to a JSON map
  Map<String, dynamic> toJson() => {
    'score': score,
    'playerName': playerName,
    'date': date.toIso8601String(),
  };

  // Create a GameScore from a JSON map
  factory GameScore.fromJson(Map<String, dynamic> json) {
    return GameScore(
      score: json['score'] as int,
      playerName: json['playerName'] as String,
      date: DateTime.parse(json['date'] as String),
    );
  }
}