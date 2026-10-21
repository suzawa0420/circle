class AddImageUrlToColumnProducts < ActiveRecord::Migration[8.1]
  def change
    add_column :column_products, :image_url, :string, limit: 2048
  end
end
