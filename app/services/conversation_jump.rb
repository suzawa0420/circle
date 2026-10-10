# Select the initial page and target before a participant's read cursor advances.
class ConversationJump
  PAGE_SIZE = 50

  def initialize(conversation, role: nil)
    @conversation = conversation
    @role = role
  end

  def call
    base = @conversation.chat_messages
    scope = @role ? base.visible_to(@role) : base
    unread = if @role
      base.unread_by(@role, @conversation["#{@role}_read_message_id"])
    else
      base.unread_by('member', @conversation.member_read_message_id)
        .or(base.unread_by('owner', @conversation.owner_read_message_id))
    end
    order = @role ? 'COALESCE(released_at, created_at) ASC, id ASC' : 'id ASC'
    target = unread.reorder(Arel.sql(order)).first
    unread_target = target.present?
    target ||= @role ? scope.delivery_order.first : scope.order(id: :desc).first
    return unless target

    preceding = if @role
      time = target.released_at || target.created_at
      scope.where('COALESCE(released_at, created_at) > :time OR (COALESCE(released_at, created_at) = :time AND id > :id)', time: time, id: target.id)
    else
      scope.where('id < ?', target.id)
    end
    { message_id: target.id, page: preceding.count / PAGE_SIZE + 1, alignment: unread_target ? 'start' : 'end' }
  end
end
