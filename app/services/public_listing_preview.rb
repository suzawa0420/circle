# Select a tiny homepage preview before fetching full profiles/article bodies.
# Split the moderation tiers so the normal tier can use the existing order
# indexes, instead of sorting every public record by a cross-table CASE.
class PublicListingPreview
  def self.call(relation, limit:)
    predicate = relation.klass.moderation_order_predicate
    priority = "CASE WHEN #{predicate} THEN 1 ELSE 0 END ASC"
    raise ArgumentError, 'Expected moderation_last ordering' unless relation.order_values.first.to_s == priority
    raise ArgumentError, 'Preview must not be paginated' if relation.offset_value || relation.limit_value

    ordered = relation.reorder(*relation.order_values.drop(1))
    ids = ordered.where("(#{predicate}) IS NOT TRUE").limit(limit).pluck(:id)
    if ids.size < limit
      ids += ordered.where(predicate).limit(limit - ids.size).pluck(:id)
    end
    # Retain the original predicates, live owner visibility, ordering and preloads.
    relation.where(id: ids).limit(limit)
  end
end
