import 'package:equatable/equatable.dart';

enum AuthStatus { unknown, guest, authenticated }

class AuthViewState extends Equatable {
  const AuthViewState({
    required this.status,
    this.email,
    this.lastError,
  });

  final AuthStatus status;
  final String? email;
  final String? lastError;

  AuthViewState copyWith({
    AuthStatus? status,
    String? email,
    String? lastError,
    bool clearError = false,
  }) {
    return AuthViewState(
      status: status ?? this.status,
      email: email ?? this.email,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }

  @override
  List<Object?> get props => [status, email, lastError];
}
