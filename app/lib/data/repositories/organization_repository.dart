import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/organization.dart';

class OrganizationRepository {
  OrganizationRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<Organization>> listMyOrganizations() async {
    final response = await _client.rpc('list_my_organizations');
    final rows = response as List? ?? const [];
    return rows
        .map((row) => Organization.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  Future<List<OrganizationEventSummary>> listEvents(String organizationId) async {
    final response = await _client.rpc(
      'list_organization_events',
      params: {'p_organization_id': organizationId},
    );
    final rows = response as List? ?? const [];
    return rows
        .map(
          (row) => OrganizationEventSummary.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList();
  }

  Future<Organization> createOrganization({
    required String name,
    OrganizationKind kind = OrganizationKind.customer,
  }) async {
    final response = await _client.rpc(
      'create_organization',
      params: {
        'p_name': name,
        'p_kind': kind.name,
      },
    );
    return Organization.fromJson(Map<String, dynamic>.from(response as Map));
  }
}
