class AddMemberCompositionToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :member_age_percentages, :jsonb
    add_column :users, :member_male_percentage, :integer, limit: 2
  end
end
