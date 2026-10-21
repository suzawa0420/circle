class AddEditorialFeaturesToColumns < ActiveRecord::Migration[8.1]
  def up
    # Existing public URLs stay public; the editor explicitly starts new articles as drafts.
    add_column :columns, :publication_status, :string, default: 'published', null: false
    add_column :columns, :published_at, :datetime
    add_column :columns, :audience, :string, default: 'all', null: false
    add_column :columns, :affiliate, :boolean, default: false, null: false
    add_reference :columns, :event, foreign_key: true
    add_index :columns, [:publication_status, :updated_at]
    execute 'UPDATE columns SET published_at = created_at'
    change_column_default :columns, :publication_status, from: 'published', to: 'draft'

    create_table :column_products do |t|
      t.references :column, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.text :amazon_url
      t.text :mercari_url
      t.integer :position, default: 0, null: false
      t.bigint :amazon_clicks, default: 0, null: false
      t.bigint :mercari_clicks, default: 0, null: false
      t.timestamps
    end
  end

  def down
    drop_table :column_products
    remove_index :columns, [:publication_status, :updated_at]
    remove_reference :columns, :event, foreign_key: true
    remove_column :columns, :affiliate
    remove_column :columns, :audience
    remove_column :columns, :published_at
    remove_column :columns, :publication_status
  end
end
