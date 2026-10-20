class AddYoutubeUrlToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :youtube_url, :string
  end
end
