class ReconcileMessagePenalties < ActiveRecord::Migration[8.1]
  def up
    # 旧お問い合わせの減点と、未配信・初回返信済み等の古い報告フラグによる減点を解消する。
    legacy_ids = UserContact.where(respond_check: "NG").select(:user_id)
    message_ids = Conversation.where(respond_check: "NG").select(:user_id)
    User.where(id: legacy_ids).or(User.where(id: message_ids)).find_each do |circle|
      circle.with_lock do
        CircleScoreUpdater.new.refresh(circle)
        circle.update_columns(cb_point: circle.cb_point)
      end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
