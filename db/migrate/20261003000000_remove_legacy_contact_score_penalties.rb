class RemoveLegacyContactScorePenalties < ActiveRecord::Migration[8.1]
  def up
    # 検索順位用の保存済みポイントも更新する。活動日時や他の設定は変更しない。
    affected_ids = UserContact.where(respond_check: "NG").select(:user_id)
    User.where(id: affected_ids).find_each do |circle|
      circle.with_lock do
        CircleScoreUpdater.new.refresh(circle)
        circle.update_columns(cb_point: circle.cb_point)
      end
    end
  end

  def down
    # 旧お問い合わせへの減点は復活させない。以前の計算結果は保存していない。
    raise ActiveRecord::IrreversibleMigration
  end
end
