class PlaceImportCandidate < ApplicationRecord
  STATUSES = { 'queued' => '未処理', 'collected' => '判定待ち', 'ready' => '登録可能', 'pending' => '確認待ち', 'registered' => '登録済み', 'duplicate' => '重複候補', 'dismissed' => '見送り' }.freeze
  belongs_to :place, optional: true
  belongs_to :place_import_run
  serialize :payload, coder: JSON
  validates :source, :source_url, :fingerprint, :checked_at, presence: true
  validates :status, inclusion: { in: STATUSES.keys }
end
