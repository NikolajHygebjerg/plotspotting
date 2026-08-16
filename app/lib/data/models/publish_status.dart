class PublishStatus {
  const PublishStatus({
    required this.allowed,
    required this.reason,
    required this.message,
    required this.alreadyPublished,
    this.organizationId,
    this.organizationName,
    this.plan,
  });

  final bool allowed;
  final String reason;
  final String message;
  final bool alreadyPublished;
  final String? organizationId;
  final String? organizationName;
  final String? plan;

  bool get isPlanBlocked => reason == 'plan_free';

  factory PublishStatus.fromJson(Map<String, dynamic> json) {
    return PublishStatus(
      allowed: json['allowed'] as bool? ?? false,
      reason: json['reason'] as String? ?? 'blocked',
      message: json['message'] as String? ?? '',
      alreadyPublished: json['already_published'] as bool? ?? false,
      organizationId: json['organization_id'] as String?,
      organizationName: json['organization_name'] as String?,
      plan: json['plan'] as String?,
    );
  }
}
