class AddDateOfBirthToMembers < ActiveRecord::Migration[8.1]
  def change
    add_column :members, :date_of_birth, :date
  end
end
