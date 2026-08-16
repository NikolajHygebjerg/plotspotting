enum OrganizationKind {
  personal,
  customer,
  agency;

  static OrganizationKind fromJson(String? value) => switch (value) {
        'agency' => OrganizationKind.agency,
        'customer' => OrganizationKind.customer,
        _ => OrganizationKind.personal,
      };

  String get label => switch (this) {
        OrganizationKind.personal => 'Personligt',
        OrganizationKind.customer => 'Kunde',
        OrganizationKind.agency => 'Bureau',
      };
}

enum OrganizationMemberRole {
  owner,
  admin,
  editor,
  viewer;

  static OrganizationMemberRole fromJson(String? value) => switch (value) {
        'admin' => OrganizationMemberRole.admin,
        'editor' => OrganizationMemberRole.editor,
        'viewer' => OrganizationMemberRole.viewer,
        _ => OrganizationMemberRole.owner,
      };

  bool get canEdit =>
      this == OrganizationMemberRole.owner ||
      this == OrganizationMemberRole.admin ||
      this == OrganizationMemberRole.editor;
}

class Organization {
  const Organization({
    required this.id,
    required this.name,
    required this.slug,
    required this.kind,
    required this.plan,
    required this.role,
  });

  final String id;
  final String name;
  final String slug;
  final OrganizationKind kind;
  final String plan;
  final OrganizationMemberRole role;

  bool get canPublish =>
      plan == 'publish' || plan == 'pro' || plan == 'agency';

  bool get canEdit => role.canEdit;

  factory Organization.fromJson(Map<String, dynamic> json) {
    return Organization(
      id: json['id'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String,
      kind: OrganizationKind.fromJson(json['kind'] as String?),
      plan: json['plan'] as String? ?? 'free',
      role: OrganizationMemberRole.fromJson(json['role'] as String?),
    );
  }
}

class OrganizationEventSummary {
  const OrganizationEventSummary({
    required this.id,
    required this.name,
    required this.status,
    this.publicSlug,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String status;
  final String? publicSlug;
  final DateTime? updatedAt;

  bool get isPublished => status == 'published';

  factory OrganizationEventSummary.fromJson(Map<String, dynamic> json) {
    return OrganizationEventSummary(
      id: json['id'] as String,
      name: json['name'] as String,
      status: json['status'] as String? ?? 'draft',
      publicSlug: json['public_slug'] as String?,
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.tryParse(json['updated_at'] as String),
    );
  }
}
